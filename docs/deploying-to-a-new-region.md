# Deploying to a New Region

Runbook for standing this project up in a fresh AWS region. Walkthrough uses `eu-west-1`. Swap in your target region everywhere.

Also the right doc to follow for a **first-time deploy** from a clean clone — the steps are identical.

---

## Prerequisites

- [ ] AWS credentials for the target account (named profile or env creds)
- [ ] `terragrunt` v1.0.1, `terraform` v1.14.8, `packer`, `docker`, `aws` CLI v2 installed locally
- [ ] Target region picked. Confirm `t3.medium` (or your chosen instance type) is offered in at least 3 AZs:
  ```bash
  aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=instance-type,Values=t3.medium \
    --region eu-west-1 \
    --query 'InstanceTypeOfferings[].Location'
  ```
- [ ] EC2 vCPU quota in target region checked. Service Quotas → EC2 → "Running On-Demand Standard…". Default is 5 vCPUs on new accounts — raise if you plan more than ~2 `t3.medium` instances.

---

## Step 1 — Pre-create the State Bucket

Terragrunt can auto-create on first init, but pre-creating is safer and lets you enable versioning + encryption up front. Bucket names are globally unique.

```bash
aws s3api create-bucket \
  --bucket myproject-terraform-state \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket myproject-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket myproject-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket myproject-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

---

## Step 2 — Edit Root Deployment Config

Open `terragrunt/root.hcl`. Change the four locals under the **DEPLOYMENT CONFIGURATION** banner:

| Local | What to set |
|---|---|
| `project_name` | Your project identity (flows into tags + default bucket prefix) |
| `state_bucket` | Name from Step 1. Default derives from `project_name` — leave as-is if you accept that name. |
| `state_region` | `eu-west-1` |
| `aws_region` | `eu-west-1` |

---

## Step 3 — Edit Environment Config

Open `terragrunt/production/env.hcl`. Update `azs` to match the new region:

```hcl
azs = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
```

Change `vpc_cidr` / `public_subnet_cidrs` only if the defaults clash with existing VPC peering.

---

## Step 4 — Build AMI in New Region

```bash
cd packer
packer init ubuntu-docker.pkr.hcl
packer build -var 'aws_region=eu-west-1' ubuntu-docker.pkr.hcl
```

Note the AMI ID from the build output. Look it up later with:

```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=ubuntu-docker-*" \
  --query 'Images | sort_by(@, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --region eu-west-1 \
  --output table
```

---

## Step 5 — Create ECR Repo + Push First Image

One ECR repo per app. For the `web` unit:

```bash
aws ecr create-repository \
  --repository-name web \
  --region eu-west-1 \
  --image-scanning-configuration scanOnPush=true

aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin \
  <acct>.dkr.ecr.eu-west-1.amazonaws.com

docker tag web:latest <acct>.dkr.ecr.eu-west-1.amazonaws.com/web:latest
docker push <acct>.dkr.ecr.eu-west-1.amazonaws.com/web:latest
```

Replace `<acct>` with your AWS account ID. Image MUST be pushed before the first apply or user-data's `docker compose up` fails.

---

## Step 6 — Edit App Unit(s)

Open `terragrunt/production/apps/web/terragrunt.hcl`. Update:

| Input | New value |
|---|---|
| `ami_id` | AMI ID from Step 4 |
| `docker_image_repo` | `<acct>.dkr.ecr.eu-west-1.amazonaws.com/web` |

Repeat for every unit under `terragrunt/production/apps/`.

---

## Step 7 — Plan

```bash
terragrunt run --working-dir terragrunt/production/shared-infra -- plan
terragrunt run --working-dir terragrunt/production/apps/web -- plan
```

Review carefully:
- All resources show CREATE (fresh region — nothing should UPDATE or DESTROY).
- Region segment in every ARN = `eu-west-1`.
- Subnet CIDRs match `env.hcl`.

---

## Step 8 — Get Approval, Then Apply

**Do not apply without explicit approval.**

```bash
terragrunt run --working-dir terragrunt/production/shared-infra -- apply
terragrunt run --working-dir terragrunt/production/apps/web -- apply
```

Or once both plans look clean:

```bash
terragrunt run --all --working-dir terragrunt/production -- apply
```

Shared-infra finishes in 2–3 minutes. Each app unit takes 3–5 minutes for ASG instances to boot, pull the image, and signal `CONTINUE` to the launch lifecycle hook.

---

## Step 9 — Verify

No ALB is provisioned — hit an instance directly on its public IP:

```bash
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=myproject-production-web-asg" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text \
  --region eu-west-1)

curl -i "http://$INSTANCE_IP:8080/health"
```

Expect `HTTP/1.1 200 OK` from your app. Connection hang / refused = container not healthy yet or SG doesn't allow your source IP.

Deeper verification (ASG capacity, target-group health, user-data logs): see [adding-a-new-app.md](adding-a-new-app.md#step-5--verify).

---

## Gotchas

| Symptom | Likely cause | Fix |
|---|---|---|
| `packer build` fails: instance-type unavailable | `t3.medium` not in every AZ | Override with `packer build -var 'instance_type=t3a.medium' ...` or pick a different region |
| `terragrunt init` fails: `BucketAlreadyExists` | S3 bucket names are globally unique | Pick a new `state_bucket` in `root.hcl` |
| ASG launches instances that fail to reach InService | vCPU quota too low in new region | Service Quotas → EC2 → Running On-Demand Standard → request increase |
| `terragrunt apply` fails: AMI not found | AMI was built in a different region | Rebuild with Packer in target region (Step 4) |
| Instances launch but can't pull from ECR | ECR repo in wrong region, or URL mismatch | Verify `docker_image_repo` region segment matches `aws_region` in `root.hcl` |
| First deploy: container starts, target-group target stays unhealthy | SSM `docker-image-tag` points at a tag that doesn't exist in ECR | Push the tag, or update the SSM param, then `start-instance-refresh` |
| Plan shows VPC peering errors | `vpc_cidr` clashes with an existing VPC | Change `vpc_cidr` in `env.hcl` |

---

## Running Multiple Regions

This repo is single-region by design — `root.hcl` holds one `aws_region` local. To run two regions from one repo you'd either:

- Maintain separate branches per region, or
- Refactor `root.hcl` so region is per-environment (e.g., `terragrunt/production-eu/env.hcl`, `terragrunt/production-us/env.hcl`).

Neither is wired up today. Talk to the team before going down this path.

---

## See Also

- [architecture-overview.md](architecture-overview.md)
- [adding-a-new-app.md](adding-a-new-app.md)
- [autoscaling-behavior.md](autoscaling-behavior.md)
- [updating-with-cicd.md](updating-with-cicd.md)
