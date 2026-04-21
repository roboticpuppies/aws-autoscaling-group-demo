# =============================================================================
# Unit: production / apps / web
# -----------------------------------------------------------------------------
# One-app instance of the `app` module. Duplicate this directory to stand up
# another app — change `app_name`, `listener_rule_priority`, and whatever
# app-specific inputs differ, and you're done. No Terraform file duplication.
#
# Listener-rule priority discipline:
#   Each app in a given environment MUST pick a unique `listener_rule_priority`
#   between 1 and 50000. Lower numbers are evaluated first. Conventionally we
#   reserve:
#     100   default catch-all app
#     200+  apps with specific path patterns (admin, api, ...)
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/terraform/modules/app"
}

# Wire shared-infra outputs into this unit's inputs.
dependency "shared_infra" {
  config_path = "${get_repo_root()}/terragrunt/production/shared-infra"

  # Sensible placeholders so `terragrunt plan` works before shared-infra is
  # applied (e.g., for validation in CI).
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    vpc_id                = "vpc-00000000000000000"
    vpc_cidr              = "10.0.0.0/16"
    public_subnet_ids     = ["subnet-0000000000000000a", "subnet-0000000000000000b", "subnet-0000000000000000c"]
    alb_listener_http_arn = "arn:aws:elasticloadbalancing:ap-southeast-3:000000000000:listener/app/mock/mock/mock"
    alb_security_group_id = "sg-00000000000000000"
  }
}

inputs = merge(
  local.env.inputs,
  {
    # -------------------------------------------------------------------------
    # Identity
    # -------------------------------------------------------------------------
    app_name = "web"

    # -------------------------------------------------------------------------
    # Wiring from shared-infra
    # -------------------------------------------------------------------------
    vpc_id                = dependency.shared_infra.outputs.vpc_id
    vpc_cidr              = dependency.shared_infra.outputs.vpc_cidr
    public_subnet_ids     = dependency.shared_infra.outputs.public_subnet_ids
    alb_listener_arn      = dependency.shared_infra.outputs.alb_listener_http_arn
    alb_security_group_id = dependency.shared_infra.outputs.alb_security_group_id

    # -------------------------------------------------------------------------
    # ALB listener rule (unique per app in the environment)
    # -------------------------------------------------------------------------
    listener_rule_priority      = 100
    listener_rule_path_patterns = ["/*"]

    # -------------------------------------------------------------------------
    # Security / Networking
    # -------------------------------------------------------------------------
    ssh_allowed_cidrs = []
    app_port          = 8080
    health_check_path = "/health"

    # -------------------------------------------------------------------------
    # EC2 / ASG
    # -------------------------------------------------------------------------
    # TODO: replace with the AMI ID built by Packer for this app.
    ami_id                    = "ami-0123456789abcdef0"
    instance_type             = "t3.medium"
    key_name                  = ""
    asg_min_size              = 1
    asg_max_size              = 3
    asg_desired_capacity      = 2
    health_check_grace_period = 300

    # -------------------------------------------------------------------------
    # SSM / Application Config
    # -------------------------------------------------------------------------
    # Seeded on first apply. CI/CD owns the values thereafter — the module's
    # `lifecycle { ignore_changes = [value] }` keeps Terraform from reverting
    # in-flight deploys.
    docker_image_repo = "123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/web"
    docker_image_tag  = "latest"

    app_env_vars = {
      # Add container env vars here; they become SecureString SSM parameters.
      # Example:
      # NODE_ENV = "production"
    }

    # -------------------------------------------------------------------------
    # Alerting
    # -------------------------------------------------------------------------
    alert_email = ""
  }
)
