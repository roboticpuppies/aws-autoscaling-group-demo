# Adding New App

No Terraform code changes needed. Copy one Terragrunt unit file, wire it up. Walkthrough uses `api` in `production`. Swap your own `app_name`.

---

## Prerequisites

- [ ] `shared-infra` applied (VPC exists). Verify:
  ```bash
  terragrunt run --working-dir terragrunt/production/shared-infra -- output
  ```
- [ ] **ECR repo** exists. Create if missing:
  ```bash
  aws ecr create-repository \
    --repository-name api \
    --region ap-southeast-3 \
    --image-scanning-configuration scanOnPush=true
  ```
- [ ] **AMI ID** from Packer. Check latest:
  ```bash
  aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=ubuntu-docker-*" \
    --query 'Images | sort_by(@, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
    --region ap-southeast-3 \
    --output table
  ```
  Need new AMI: `packer build packer/ubuntu-docker.pkr.hcl`.
- [ ] **Container port** + **health check path** known.
- [ ] **Env var map** ready (become SSM `SecureString` params).

---

## Step 1 — Copy Unit File

```bash
cp -r terragrunt/production/apps/web terragrunt/production/apps/api
```

New unit points at same `terraform/modules/app`. No new Terraform code.

---

## Step 2 — Edit `terragrunt.hcl`

Open `terragrunt/production/apps/api/terragrunt.hcl`. Set in `inputs` block:

| Input | What to set | Notes |
|---|---|---|
| `app_name` | `"api"` | Namespaces all resources, SSM path, compose dir. |
| `app_port` | e.g., `3000` | Container listen port. |
| `health_check_path` | e.g., `/healthz` | Target group probes here; must return 200. |
| `app_port_allowed_cidrs` | e.g., `["203.0.113.0/24"]` | CIDRs allowed to reach `app_port` on the instance public IPs. Default `["0.0.0.0/0"]`. |
| `ami_id` | Packer AMI ID | |
| `instance_type` | e.g., `t3.medium` | |
| `key_name` | SSH key pair name | `""` = no SSH key. |
| `ssh_allowed_cidrs` | e.g., `["10.20.0.0/16"]` | Empty = SSH closed. |
| `asg_min_size`, `asg_max_size`, `asg_desired_capacity` | Capacity targets | |
| `docker_image_repo` | Full ECR URI | |
| `docker_image_tag` | Initial tag, e.g., `"v0.1.0"` | CI/CD overwrites in SSM on every deploy. |
| `app_env_vars` | `{ NODE_ENV = "production", ... }` | SSM `SecureString`. CI/CD owns values after first apply. |
| `alert_email` | Operator email | `""` = skip SNS email sub (topic still created). |

`vpc_cidr`, `azs`, `public_subnet_cidrs` from `env.hcl` and `project_name` from `root.hcl` flow in automatically.

---

## Step 3 — Plan

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- plan
```

Expected CREATE plan:
- 1 IAM role + instance profile + 5 inline policies
- 1 launch template
- 1 ASG + launch lifecycle hook + instance refresh config
- 1 target group
- 1 EC2 SG + ingress/egress rules
- 1 SNS topic (+ optional email sub)
- ~3+ SSM params (`docker-image-repo`, `docker-image-tag`, one per `app_env_vars` entry)

Review:
- `ami_id` = correct Packer AMI.
- `docker_image_repo` = ECR repo from prerequisites.
- No `destroy` or `replace` on anything outside this app.

---

## Step 4 — Get Approval, Then Apply

**Do not run without explicit approval.**

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- apply
```

Takes a few minutes — ASG creates launch template, requests initial instances, each runs user-data → pulls image → starts container → signals `CONTINUE` to lifecycle hook. Heartbeat = `launch_lifecycle_heartbeat` seconds (default 600). user-data failure = instance ABANDONed + replaced.

Terragrunt returns when ASG resources created. Instances may still boot for 1–3 more minutes.

---

## Step 5 — Verify

### ASG reached desired capacity

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names myproject-production-api-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:length(Instances),Healthy:Instances[?HealthStatus==`Healthy`] | length(@)}'
```

All 3 numbers match = good.

### Target group healthy

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terragrunt run --working-dir terragrunt/production/apps/api -- output -raw target_group_arn)"
```

All targets `healthy`. If `unhealthy` = container not responding on `health_check_path:app_port`.

### End-to-end smoke test

No ALB is provisioned, so hit an instance directly on its public IP:

```bash
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=myproject-production-api-asg" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

curl -i "http://$INSTANCE_IP:3000/healthz"   # swap port + path for your app
```

Expect `HTTP/1.1 200 OK`. Connection refused / timeout = the SG doesn't allow your source IP, or the container isn't up yet.

### user-data log (if broken)

SSH to instance:

```bash
sudo tail -n 200 /var/log/user-data.log
```

Script logs every step + publishes errors to SNS before exit.

---

## Step 6 — Wire into CI/CD

Deploys from here don't need Terraform/Terragrunt. Pipeline needs:

1. Build + push Docker image to ECR.
2. Update SSM: `/myproject/production/api/docker-image-tag`.
3. Trigger instance refresh: `myproject-production-api-asg`.

Copy Jenkins template from [updating-with-cicd.md](updating-with-cicd.md), substitute:
- `SSM_PREFIX = /myproject/production/api`
- `ASG_NAME  = myproject-production-api-asg`
- `ECR_REPO  = api`

---

## Updating Env Vars Later

Two ways:

1. **Out-of-band (fastest, best for rotations):**
   ```bash
   aws ssm put-parameter \
     --name "/myproject/production/api/env/DATABASE_URL" \
     --value "postgresql://newhost:5432/db" \
     --type SecureString --overwrite
   aws autoscaling start-instance-refresh \
     --auto-scaling-group-name myproject-production-api-asg
   ```

2. **Through Terraform (adding new key):** edit `app_env_vars` in `terragrunt.hcl`, plan + apply. New keys seeded; existing keys untouched (`ignore_changes = [value]`). Trigger instance refresh after.

---

## Removing App

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- destroy
rm -rf terragrunt/production/apps/api
```

Confirm destroy plan first — should delete only per-app resources (ASG, target group, IAM role, SSM params, SNS topic, EC2 SG). shared-infra untouched.

ECR repo + S3 state object remain. Clean up if app gone for good:

```bash
aws ecr delete-repository --repository-name api --force
# State bucket is the `state_bucket` local in terragrunt/root.hcl (default: myproject-terraform-state)
aws s3 rm "s3://myproject-terraform-state/production/apps/api/terraform.tfstate"
```

---

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| Instances launch then ABANDON | user-data failed before `CONTINUE` | `/var/log/user-data.log`; SNS alert email |
| Target group stays `unhealthy` | Container not responding on `health_check_path:app_port` | `docker compose logs` in `/home/ubuntu/api` |
| `curl` to instance IP times out | `app_port_allowed_cidrs` doesn't include your source IP | `terragrunt.hcl` input, or `aws ec2 describe-security-groups` |
| First apply can't pull from ECR | Instance role lacks permission, or ECR repo missing | `app/iam.tf` grants `ecr:*Pull*`; check ECR repo exists |
| SSM param not readable | `app_name` mismatch → instance reads wrong SSM path | Verify `/<project>/<env>/<app_name>/...` vs. user-data |

---

## See Also

- [architecture-overview.md](architecture-overview.md)
- [autoscaling-behavior.md](autoscaling-behavior.md)
- [updating-with-cicd.md](updating-with-cicd.md)
- [instance-naming.md](instance-naming.md)
