# AWS Autoscaling Group Infrastructure Project

## Project Overview

This project builds AWS infrastructure for deploying a containerized web application on EC2 instances with Autoscaling capabilities. The team uses EC2 directly (no ECS/EKS) because the operations team is not familiar with container orchestration services.

## Key Design Decisions

- **Compute**: EC2 instances running Docker containers (no ECS/EKS)
- **AMI**: Pre-baked with Hashicorp Packer (Ubuntu 24.04 LTS x86-64)
- **IaC**: Terraform v1.14.8, AWS provider ~> 6.41
- **Secrets**: AWS SSM Parameter Store (SecureString) for environment variables
- **Registry**: Amazon ECR for Docker images
- **Region**: ap-southeast-3 (Jakarta)
- **Networking**: VPC with 3 AZs, public subnets (private subnets planned for later)
- **Load Balancing**: Shared internet-facing ALB with per-app listener rules (default 404)
- **Scaling**: Autoscaling Group (no dynamic scaling policies configured yet)
- **Consistency**: SSM Parameter Store is the single source of truth; instances read image tag and env vars at boot time
- **Multi-App Support**: ALB is shared infrastructure; per-app files (`app-*.tf`) can be duplicated for future apps. The `app_name` variable namespaces SSM parameters (`/<project>/<env>/<app_name>/...`), per-app resource names (`<project>-<env>-<app_name>-*`), and the on-instance compose directory (`/home/ubuntu/<app_name>`).
- **Container Runtime**: Each instance runs the app via `docker compose up -d` from `/home/ubuntu/<app_name>`. The user data script generates `docker-compose.yml` and `.env` from SSM at boot.

## Terraform Modules

| Module | Version |
|--------|---------|
| `terraform-aws-modules/vpc/aws` | 6.6.1 |
| `terraform-aws-modules/autoscaling/aws` | 9.2.0 |
| `terraform-aws-modules/alb/aws` | 10.5.0 |

## Project Structure

- `packer/` - Packer template and provisioning scripts for AMI
- `terraform/` - Terraform configuration (shared infra + per-app resources)
  - Files prefixed with `app-` are per-app and can be duplicated for new apps
  - `templates/user-data.sh.tftpl` - Boot script that reads SSM and runs Docker
- `docs/` - Documentation (autoscaling behavior, CI/CD updates, instance naming)

## Pre-Baked AMI Contents

- Latest Docker engine (docker-ce, docker-compose-plugin)
- AWS CLI v2
- Latest Prometheus node_exporter (systemd service)
- ZSH + OhMyZSH (plugins: history, docker, docker-compose; auto-update enabled)
- Automatic OS updates at midnight UTC+7 (17:00 UTC)

## CI/CD Deployment Flow (No Terraform Required)

1. Build and push Docker image to ECR
2. Update SSM parameter: `aws ssm put-parameter --name "<prefix>/docker-image-tag" --value "<new-tag>" --overwrite`
3. Trigger instance refresh: `aws autoscaling start-instance-refresh --auto-scaling-group-name <asg-name>`
4. SSM parameters use `lifecycle { ignore_changes = [value] }` so Terraform won't revert CI/CD changes

## Terraform Guidelines

- Do NOT run `terraform apply` without explicit user approval
- Use variables for all configurable values
- Use the Terraform and AWS MCP servers for registry lookups
