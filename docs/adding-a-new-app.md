# Adding a New App

Step-by-step runbook for an operator or cloud engineer onboarding a new application onto the shared autoscaling platform. No Terraform code changes are needed — adding an app is a matter of copying one Terragrunt unit file and wiring it up.

The walkthrough assumes you are adding an app called `api` to the `production` environment. Substitute your own `app_name` throughout.

---

## Prerequisites

Before you start:

- [ ] `shared-infra` has already been applied for the target environment (VPC + ALB exist). Verify with `terragrunt run --working-dir terragrunt/production/shared-infra -- output`.
- [ ] You have an **ECR repository** for the app's Docker image. Create it if it doesn't exist:
  ```bash
  aws ecr create-repository \
    --repository-name api \
    --region ap-southeast-3 \
    --image-scanning-configuration scanOnPush=true
  ```
- [ ] You have an **AMI ID** built by Packer. All apps can share the same base AMI unless the app needs extra packages baked in. Check the current AMI with:
  ```bash
  aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=ubuntu-docker-*" \
    --query 'Images | sort_by(@, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
    --region ap-southeast-3 \
    --output table
  ```
  If you need a new AMI, build it: `packer build packer/ubuntu-docker.pkr.hcl`.
- [ ] You have picked a **unique `listener_rule_priority`** for this app (see the convention below).
- [ ] You know the app's **listener path patterns** (`/*` for catch-all, `/api/*` for path-routed, etc.).
- [ ] You know the app's **container port** and **health check path**.
- [ ] You have the **env var map** the container expects at runtime (these will become SSM `SecureString` parameters).

### Listener-rule priority convention

The shared ALB's single HTTP listener evaluates rules in priority order (lowest first). Two apps cannot share a priority. We reserve:

| Priority range | Use |
|---|---|
| `100` | The default catch-all app (path `/*`) — only one per environment |
| `200–299` | Path-routed apps (e.g., `/api/*`, `/admin/*`) |
| `300+` | Host-routed apps (different hostnames on the same ALB) |

List priorities already in use:

```bash
aws elbv2 describe-rules \
  --listener-arn "$(terragrunt run --working-dir terragrunt/production/shared-infra -- output -raw alb_listener_http_arn)" \
  --query 'Rules[].[Priority, Conditions[0].Values[0]]' \
  --output table
```

---

## Step 1 — Copy the unit file

From the repo root:

```bash
cp -r terragrunt/production/apps/web terragrunt/production/apps/api
```

That's the entire "new Terraform code" step. The new unit points at the same `terraform/modules/app` module the other apps use.

---

## Step 2 — Edit the new `terragrunt.hcl`

Open `terragrunt/production/apps/api/terragrunt.hcl` and set these fields in the `inputs` block:

| Input | What to set | Notes |
|---|---|---|
| `app_name` | `"api"` | Namespaces every per-app resource, SSM path, and the on-instance compose dir. |
| `listener_rule_priority` | Unique integer, e.g., `200` | Must not collide with any other app in this environment. |
| `listener_rule_path_patterns` | e.g., `["/api/*"]` | Defaults to `["/*"]` (catch-all) — set this if the app is path-routed. |
| `app_port` | e.g., `3000` | Port the container listens on. |
| `health_check_path` | e.g., `/healthz` | HTTP path the ALB probes; must return 200 when healthy. |
| `ami_id` | The Packer-baked AMI ID | |
| `instance_type` | e.g., `t3.medium` | Size for this app's workload. |
| `key_name` | SSH key pair name | Leave `""` to disable SSH key. |
| `ssh_allowed_cidrs` | e.g., `["10.20.0.0/16"]` | Empty list = SSH closed. |
| `asg_min_size`, `asg_max_size`, `asg_desired_capacity` | Capacity targets | |
| `docker_image_repo` | Full ECR URI, e.g., `123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/api` | |
| `docker_image_tag` | Initial tag, e.g., `"v0.1.0"` or `"latest"` | CI/CD will overwrite this in SSM on every deploy. |
| `app_env_vars` | `{ NODE_ENV = "production", DATABASE_URL = "...", ... }` | Stored as SSM `SecureString`. Seeded on first apply; CI/CD or out-of-band updates own the values thereafter. |
| `alert_email` | Operator email address | Leave `""` to skip the SNS email subscription (the topic is still created). |

The defaults from `env.hcl` (`vpc_cidr`, `azs`, `public_subnet_cidrs`) and `root.hcl` (`project_name`) flow in automatically.

---

## Step 3 — Plan

From the repo root:

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- plan
```

Expected output: a **CREATE** plan for roughly:

- 1 IAM role + instance profile + 5 inline policies
- 1 launch template
- 1 ASG + launch lifecycle hook + instance refresh config
- 1 ALB target group + 1 listener rule
- 1 EC2 security group + ingress/egress rules
- 1 SNS topic (+ optional email subscription)
- ~3+ SSM parameters (`docker-image-repo`, `docker-image-tag`, one per entry in `app_env_vars`)

Review carefully:

- **Listener-rule priority** matches what you chose and isn't in use already.
- **`ami_id`** is the correct Packer AMI.
- **`docker_image_repo`** resolves to the ECR repo you created in prerequisites.
- No `destroy` or `replace` actions on anything outside this app.

---

## Step 4 — Get approval, then apply

`terragrunt apply` is subject to the same guardrail as `terraform apply` — do not run it without explicit approval from the designated reviewer.

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- apply
```

The first apply takes a few minutes because:

- The ASG creates the launch template and requests its initial instances (`asg_desired_capacity`).
- Each new instance runs user-data → pulls the image from ECR → starts the container → signals `CONTINUE` to the ASG launch lifecycle hook.
- The launch lifecycle hook heartbeat is `launch_lifecycle_heartbeat` seconds (default 600) — if user-data fails, the instance is ABANDONed and replaced.

Terragrunt apply returns when the ASG resources are created; the instances themselves may still be coming up for another 1–3 minutes.

---

## Step 5 — Verify

### ASG reached desired capacity

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names myproject-production-api-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:length(Instances),Healthy:Instances[?HealthStatus==`Healthy`] | length(@)}'
```

All three numbers should match after a few minutes.

### Listener rule is attached

```bash
aws elbv2 describe-rules \
  --listener-arn "$(terragrunt run --working-dir terragrunt/production/shared-infra -- output -raw alb_listener_http_arn)" \
  --query 'Rules[?Priority==`"200"`]'
```

(Replace `200` with your `listener_rule_priority`.)

### Target group is healthy

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terragrunt run --working-dir terragrunt/production/apps/api -- output -raw target_group_arn)"
```

All targets should be `healthy`. If they're `unhealthy`, the container isn't responding on `health_check_path:app_port`.

### End-to-end smoke test

```bash
ALB_DNS=$(terragrunt run --working-dir terragrunt/production/shared-infra -- output -raw alb_dns_name)
curl -i "http://$ALB_DNS/api/healthz"   # use your actual path + health path
```

Expect `HTTP/1.1 200 OK` from the app (not the ALB's default `404 Not Found`, which would indicate the listener rule didn't match).

### User-data log (if something broke)

SSH to one instance and check:

```bash
sudo tail -n 200 /var/log/user-data.log
```

The script logs every step and publishes any hard errors to the SNS topic before exiting.

---

## Step 6 — Wire the app into CI/CD

From this point on, deploying new versions of the app does **not** require Terraform or Terragrunt. The pipeline for this app needs three things:

1. Build and push the Docker image to ECR.
2. Update the SSM parameter `/myproject/production/api/docker-image-tag`.
3. Trigger an instance refresh on `myproject-production-api-asg`.

Copy the Jenkins pipeline template from [updating-with-cicd.md](updating-with-cicd.md) and substitute:

- `SSM_PREFIX = /myproject/production/api`
- `ASG_NAME  = myproject-production-api-asg`
- `ECR_REPO  = api`

The `lifecycle { ignore_changes = [value] }` rule in the `app` module keeps `terragrunt apply` from reverting whatever CI/CD wrote to SSM.

---

## Updating env vars later

Two ways:

1. **Out-of-band (fastest, recommended for rotations):**
   ```bash
   aws ssm put-parameter \
     --name "/myproject/production/api/env/DATABASE_URL" \
     --value "postgresql://newhost:5432/db" \
     --type SecureString --overwrite
   aws autoscaling start-instance-refresh \
     --auto-scaling-group-name myproject-production-api-asg
   ```

2. **Through Terraform (for adding a brand-new env var key):** edit `app_env_vars` in the unit `terragrunt.hcl`, then plan + apply. New keys will be seeded; existing keys are untouched because of `ignore_changes = [value]`. Trigger an instance refresh afterwards for instances to pick up the change.

---

## Removing an app

```bash
terragrunt run --working-dir terragrunt/production/apps/api -- destroy
rm -rf terragrunt/production/apps/api
```

Confirm the destroy plan first — it should delete only the per-app resources (ASG, target group, listener rule, IAM role, SSM params, SNS topic, EC2 SG). Shared-infra is untouched.

After destroy, the ECR repo and the S3 state object remain; clean those up if the app is gone for good:

```bash
aws ecr delete-repository --repository-name api --force
aws s3 rm "s3://$TG_STATE_BUCKET/production/apps/api/terraform.tfstate"
```

---

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| `terragrunt apply` fails with "rule priority already in use" | Another app has the same `listener_rule_priority` | `aws elbv2 describe-rules` (see Prerequisites) |
| Instances launch then ABANDON | user-data script failed before calling `CONTINUE` | `/var/log/user-data.log` on the instance; SNS alert email |
| Target group stays `unhealthy` | Container not responding on `health_check_path:app_port` | `docker compose logs` in `/home/ubuntu/api` on the instance |
| ALB returns 404 to test traffic | Path pattern on the listener rule doesn't match the request | `aws elbv2 describe-rules` and compare `Conditions` to your request |
| First apply can't pull from ECR | Instance role lacks permission, or ECR repo doesn't exist in this account/region | `app/iam.tf` grants `ecr:*Pull*` on `*` within this account; check ECR repo existence |
| SSM parameter not readable | `app_name` mismatch → instance looking at wrong SSM path | Verify `/<project>/<env>/<app_name>/...` vs. what the instance reads in user-data |

---

## See also

- [architecture-overview.md](architecture-overview.md) — overall system design
- [autoscaling-behavior.md](autoscaling-behavior.md) — scale-out / scale-in / instance refresh mechanics
- [updating-with-cicd.md](updating-with-cicd.md) — per-app deployment pipeline details
- [instance-naming.md](instance-naming.md) — how instances tag themselves
