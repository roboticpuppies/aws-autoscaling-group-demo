locals {
  # Shared infra prefix (VPC, ALB, shared SGs)
  name = "${var.project_name}-${var.environment}"

  # Per-app prefix (target group, ASG, EC2 SG, IAM role) — keeps resources unique
  # when multiple apps share the same project/environment.
  app_prefix = "${var.project_name}-${var.environment}-${var.app_name}"

  # SSM parameters live under a per-app path so multiple apps can coexist.
  ssm_parameter_prefix = "/${var.project_name}/${var.environment}/${var.app_name}"

  # Name of the ASG launch lifecycle hook that holds new instances in
  # Pending:Wait until user-data signals completion. Must be unique per ASG.
  launch_lifecycle_hook_name = "launch-init"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    App         = var.app_name
    ManagedBy   = "terraform"
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
