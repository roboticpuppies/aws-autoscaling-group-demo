# AWS Autoscaling Group Demo

AWS infrastructure for running containerized apps on EC2 with autoscaling. No ECS, no EKS — just Docker on EC2, managed by the ops team using tools they already know.

## What's in here

| Directory | What it does |
|-----------|--------------|
| `packer/` | Builds the pre-baked Ubuntu 24.04 AMI (Docker, AWS CLI, node_exporter) |
| `terraform/modules/` | Two reusable modules: `shared-infra` (VPC + ALB) and `app` (ASG + target group + IAM + SSM) |
| `terragrunt/` | Per-environment wiring. One `.hcl` file per app — no Terraform duplication |
| `docs/` | Operator runbooks (see below) |

## How it works

- Instances pull their Docker image tag and env vars from **SSM Parameter Store** at boot
- A shared **ALB** routes traffic to apps via listener rules (path or host based)
- Deploying a new version = update SSM + trigger instance refresh. No Terraform needed
- Adding a new app = copy one Terragrunt unit file. No Terraform code changes

## Docs

- [Architecture Overview](docs/architecture-overview.md) — design decisions and component map
- [Adding a New App](docs/adding-a-new-app.md) — operator runbook for onboarding a new application
- [Updating with CI/CD](docs/updating-with-cicd.md) — how to deploy a new image tag or env vars without Terraform
- [Autoscaling Behavior](docs/autoscaling-behavior.md) — how the ASG and instance refresh work
- [Instance Naming](docs/instance-naming.md) — automatic Name tag format for launched instances

## Stack

- **IaC**: Terraform v1.14.8 + Terragrunt v1.0.1
- **AMI**: Packer (Ubuntu 24.04 LTS)
- **Region**: ap-southeast-3 (Jakarta)
- **Secrets**: AWS SSM Parameter Store (SecureString)
- **Registry**: Amazon ECR
