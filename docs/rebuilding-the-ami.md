# Rebuilding the AMI

Runbook for baking a fresh AMI with Packer and rolling it out to an existing deployment. Walkthrough uses `ap-southeast-3` + the `web` app. Swap in your own region and app list.

The AMI ID is a plain Terragrunt input (`ami_id` in each `terragrunt/<env>/apps/<app>/terragrunt.hcl`). Rotation is a manual edit + apply + instance refresh — no data-source magic, no auto-discovery.

---

## When to Rebuild

- Base Ubuntu package updates beyond what unattended-upgrades handles
- New Docker engine / Compose plugin version
- New AWS CLI v2 version
- Change to `packer/scripts/*` (node_exporter, zsh setup, auto-update cron, etc.)
- Change to `packer/ubuntu-docker.pkr.hcl` itself

Unattended-upgrades on running instances handles security patches day-to-day — rebuild when you want the patches baked in so fresh instances don't spend their first boot applying them.

---

## Prerequisites

- [ ] `packer` installed locally (`packer --version`)
- [ ] AWS credentials for the target account with EC2 `RunInstances` / `CreateImage` permissions
- [ ] Know which environment(s) and apps you're rolling to. List them:
  ```bash
  ls terragrunt/production/apps/
  ```
- [ ] Heads-up: rolling the new AMI through every app's ASG takes ~3–5 minutes per app (instance refresh, health checks, warm-up). Plan the window accordingly.

---

## Step 1 — Build

```bash
cd packer
packer init ubuntu-docker.pkr.hcl
packer build ubuntu-docker.pkr.hcl
```

Tail of the output has the AMI ID — copy it:

```
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.ubuntu: AMIs were created:
ap-southeast-3: ami-0abc1234def567890
```

If you missed it, look it up:

```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=ubuntu-docker-*" \
  --query 'Images | sort_by(@, &CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --region ap-southeast-3 \
  --output table
```

Packer builds in the region set by `var.aws_region` in `ubuntu-docker.pkr.hcl` (default `ap-southeast-3`). Override per-run with `packer build -var 'aws_region=eu-west-1' ...` if needed — the AMI ID is region-scoped.

---

## Step 2 — Update Terragrunt Units

Edit the `ami_id` input in every `terragrunt/<env>/apps/<app>/terragrunt.hcl` that should pick up the new AMI.

```hcl
inputs = {
  ...
  ami_id = "ami-0abc1234def567890"  # ← new AMI ID from Step 1
  ...
}
```

For a typical environment with multiple apps, you'll edit one file per app. `grep` helps confirm you got them all:

```bash
grep -rn '^\s*ami_id' terragrunt/production/apps/
```

Every line should show the new AMI ID when you're done.

The `shared-infra` unit does not reference `ami_id` — no edit needed there.

---

## Step 3 — Plan

```bash
terragrunt run --all --working-dir terragrunt/production -- plan
```

Expected diff per app:
- `aws_launch_template` — `image_id` changes to the new AMI ID; new launch-template version created.
- `aws_autoscaling_group` — `launch_template.version` bumps to the new version.

Expected **not** to change:
- Any shared-infra resource (VPC, ALB, listener).
- Target groups, listener rules, IAM roles, SSM params, SNS topics, security groups.

Anything else showing a diff = stop and investigate. You probably picked up an unrelated drift.

---

## Step 4 — Apply

**Get explicit approval before running this.**

```bash
terragrunt run --all --working-dir terragrunt/production -- apply
```

This updates each app's launch template to point at the new AMI. **Running instances are not replaced** — new scale-outs and instance refreshes will use the new AMI, but existing instances keep running on the old one until Step 5.

---

## Step 5 — Roll Instances

Trigger an instance refresh for each app. One ASG at a time (an app's own ASG rejects a second concurrent refresh, but kicking off several different ASGs in parallel is fine):

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name myproject-production-web-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}' \
  --region ap-southeast-3
```

Repeat for each app. Monitor:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name myproject-production-web-asg \
  --region ap-southeast-3 \
  --query 'InstanceRefreshes[0].{Status:Status,Pct:PercentageComplete}'
```

Wait for `Successful`. See [autoscaling-behavior.md](autoscaling-behavior.md#instance-refresh-rolling-updates) for the details of how instance refresh progresses.

---

## Step 6 — Verify

- App still responds on the ALB:
  ```bash
  ALB_DNS=$(terragrunt run --working-dir terragrunt/production/shared-infra -- output -raw alb_dns_name)
  curl -i "http://$ALB_DNS/"
  ```
- Instances report the new AMI:
  ```bash
  aws ec2 describe-instances \
    --filters "Name=tag:aws:autoscaling:groupName,Values=myproject-production-web-asg" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,ImageId]' \
    --output table
  ```
  Every `ImageId` should match the new AMI.

---

## Rollback

Old AMIs aren't auto-deleted — they stay in the account unless you explicitly deregister them. To roll back:

1. Put the **previous** AMI ID back in every app's `terragrunt.hcl`.
2. `terragrunt run --all --working-dir terragrunt/production -- apply`
3. `aws autoscaling start-instance-refresh ...` for each app.

Keep the previous AMI ID handy before Step 2 — `grep -rn '^\s*ami_id' terragrunt/` captures it for you.

---

## Cleanup

Old AMIs and their backing EBS snapshots cost money (EBS snapshot storage, not the AMI itself). After you're confident in the new AMI, deregister the old one:

```bash
# Find the snapshot IDs first
aws ec2 describe-images --image-ids ami-0oldoldoldoldoldold \
  --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text

aws ec2 deregister-image --image-id ami-0oldoldoldoldoldold
aws ec2 delete-snapshot --snapshot-id snap-0xxx   # one per returned snapshot
```

Keep at least one prior AMI for rollback.

---

## Gotchas

| Symptom | Likely cause | Fix |
|---|---|---|
| `packer build` fails: subnet not found | Default VPC removed in this region | Add `subnet_id = "..."` + `vpc_id = "..."` to the Packer source block |
| `packer build` fails: instance-type unavailable | `t3.medium` not in every AZ | Override: `packer build -var 'instance_type=t3a.medium' ...` |
| `terragrunt plan` shows more than just `image_id` / launch-template-version | Unrelated drift or stale state | Stop. Inspect the extra changes before applying |
| Instance refresh stuck at `InProgress` for >15min | New AMI boots but user-data fails before `CONTINUE` | Check `/var/log/user-data.log` on a failing instance; SNS alert email; see [adding-a-new-app.md](adding-a-new-app.md#step-5--verify) |
| `Failed` instance refresh | ABANDON triggered by user-data or health check | ASG stops refresh, remaining instances still on old AMI. Diagnose before retrying |
| New instances pass ALB health but app misbehaves | AMI change introduced a subtle runtime regression (Docker version, kernel, etc.) | Rollback (above). File a bug against the Packer scripts |
| Can't find the AMI after `packer build` finishes | Region mismatch between Packer and AWS CLI | `aws ec2 describe-images --region <region>` where `<region>` matches `var.aws_region` |

---

## See Also

- [architecture-overview.md](architecture-overview.md) — why AMI is pre-baked
- [autoscaling-behavior.md](autoscaling-behavior.md) — instance refresh mechanics
- [adding-a-new-app.md](adding-a-new-app.md) — looking up the current AMI ID for a new app
- [deploying-to-a-new-region.md](deploying-to-a-new-region.md) — first-time AMI build in a fresh region
