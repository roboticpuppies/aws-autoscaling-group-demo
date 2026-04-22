# AWS Autoscaling Group Infrastructure Project

## Project Overview

This project builds AWS infrastructure for deploying a containerized web application on EC2 instances with Autoscaling capabilities. The team uses EC2 directly (no ECS/EKS) because the operations team is not familiar with container orchestration services.

## Key Design Decisions

- **Compute**: EC2 instances running Docker containers (no ECS/EKS)
- **AMI**: Pre-baked with Hashicorp Packer (Ubuntu 24.04 LTS x86-64)
- **IaC**: Terraform v1.14.8, AWS provider ~> 6.41, orchestrated by Terragrunt v1.0.1 (OpenTofu-backed release; native `stack`/`unit` syntax — NOT the legacy Gruntwork version)
- **Secrets**: AWS SSM Parameter Store (SecureString) for environment variables
- **Registry**: Amazon ECR for Docker images
- **Region**: ap-southeast-3 (Jakarta)
- **Networking**: VPC with 3 AZs, public subnets (private subnets planned for later)
- **Load Balancing**: Out of scope for now. Each app gets a target group that the ASG attaches to; the TG's own health check drives self-healing, but no ALB is provisioned. Clients reach instances directly on their public IPs (`app_port_allowed_cidrs` on the per-app SG, default `0.0.0.0/0`).
- **Scaling**: Autoscaling Group (no dynamic scaling policies configured yet)
- **Consistency**: SSM Parameter Store is the single source of truth; instances read image tag and env vars at boot time
- **Multi-App Support**: Two reusable Terraform modules — `shared-infra` (VPC) and `app` (ASG, target group, IAM, SSM, SNS, app SG). Adding a new app = copy one Terragrunt unit file; no Terraform file duplication. The `app_name` variable namespaces SSM parameters (`/<project>/<env>/<app_name>/...`), per-app resource names (`<project>-<env>-<app_name>-*`), and the on-instance compose directory (`/home/ubuntu/<app_name>`).
- **Container Runtime**: Each instance runs the app via `docker compose up -d` from `/home/ubuntu/<app_name>`. The user data script generates `docker-compose.yml` and `.env` from SSM at boot.

## Terraform Modules

### First-party (in `terraform/modules/`)

| Module | Purpose |
|--------|---------|
| `shared-infra` | VPC. One instance per environment. |
| `app` | ASG, target group (attached to the ASG but not fronted by an ALB), IAM role/policies, SSM parameters (image tag + SecureString env vars), SNS alert topic, app SG. One instance per application. |

### Registry modules used

| Module | Version |
|--------|---------|
| `terraform-aws-modules/vpc/aws` | 6.6.1 |
| `terraform-aws-modules/autoscaling/aws` | 9.2.0 |

## Project Structure

```
.
├── packer/                          # Packer template + provisioning scripts for the AMI
├── terraform/
│   └── modules/
│       ├── shared-infra/            # VPC
│       └── app/                     # ASG, target group, IAM, SSM, SNS, app SG
│           └── templates/
│               └── user-data.sh.tftpl
├── terragrunt/
│   ├── root.hcl                     # Remote state (S3), provider + versions generate blocks
│   └── production/
│       ├── env.hcl                  # Environment-scoped inputs (VPC CIDR, AZs, subnets)
│       ├── shared-infra/
│       │   └── terragrunt.hcl       # Deploys the shared-infra module
│       └── apps/
│           └── web/
│               └── terragrunt.hcl   # Deploys the app module for one app
└── docs/                            # Autoscaling behavior, CI/CD updates, instance naming
```

## Pre-Baked AMI Contents

- Latest Docker engine (docker-ce, docker-compose-plugin)
- AWS CLI v2
- Latest Prometheus node_exporter (systemd service)
- ZSH + OhMyZSH (plugins: history, docker, docker-compose; auto-update enabled)
- Automatic OS updates at midnight UTC+7 (17:00 UTC)

## Adding a New App

Full operator runbook in [docs/adding-a-new-app.md](docs/adding-a-new-app.md). Short version: no Terraform code needs to change. Pick an `app_name` (e.g., `admin`), then:

1. `cp -r terragrunt/production/apps/web terragrunt/production/apps/<new_app>`
2. Edit `terragrunt/production/apps/<new_app>/terragrunt.hcl`:
   - Change `app_name = "<new_app>"`
   - Update `ami_id`, `docker_image_repo`, `app_env_vars`, `app_port` / `health_check_path`, and any ASG sizing inputs as needed
3. `terragrunt run --working-dir terragrunt/production/apps/<new_app> -- plan`
4. `terragrunt run --working-dir terragrunt/production/apps/<new_app> -- apply` (after explicit user approval)

## Deploy / Destroy Workflow

Run everything from the repo root. Examples:

```bash
# One unit at a time
terragrunt run --working-dir terragrunt/production/shared-infra -- plan
terragrunt run --working-dir terragrunt/production/shared-infra -- apply

terragrunt run --working-dir terragrunt/production/apps/web -- plan
terragrunt run --working-dir terragrunt/production/apps/web -- apply

# Whole environment (Terragrunt resolves the dependency graph)
terragrunt run --all --working-dir terragrunt/production -- plan
terragrunt run --all --working-dir terragrunt/production -- apply
```

Remote state is configured in `terragrunt/root.hcl`. Each unit gets its own S3 key via `path_relative_to_include()` (e.g., `production/shared-infra/terraform.tfstate`, `production/apps/web/terraform.tfstate`). To retarget at a different state bucket or region, edit the `locals` block at the top of `root.hcl` (`state_bucket`, `state_region`). Multi-region deployments are expected to use a separate state bucket per region.

## CI/CD Deployment Flow (No Terraform/Terragrunt Required)

1. Build and push Docker image to ECR
2. Update SSM parameter: `aws ssm put-parameter --name "<prefix>/docker-image-tag" --value "<new-tag>" --overwrite`
3. Trigger instance refresh: `aws autoscaling start-instance-refresh --auto-scaling-group-name <asg-name>`
4. SSM parameters use `lifecycle { ignore_changes = [value] }` in the `app` module, so neither `terraform apply` nor `terragrunt apply` will revert CI/CD changes

## Rebuilding the AMI

Manual runbook in [docs/rebuilding-the-ami.md](docs/rebuilding-the-ami.md). Short version: `packer build` in `packer/`, copy the new AMI ID into every `terragrunt/<env>/apps/<app>/terragrunt.hcl` (`ami_id` input), `terragrunt run --all ... -- plan` then `apply` (after approval — only the launch template should change), then `aws autoscaling start-instance-refresh` per app. AMI ID is intentionally a plain input — no `data "aws_ami"` lookup — so rotation is an explicit, reviewable edit.

## Terraform / Terragrunt Guidelines

- Do NOT run `terraform apply` or `terragrunt apply` / `terragrunt run --all -- apply` without explicit user approval
- Use variables for all configurable values; keep modules provider-free (the provider block is generated by `terragrunt/root.hcl`)
- Use the Terraform and AWS MCP servers for registry lookups
