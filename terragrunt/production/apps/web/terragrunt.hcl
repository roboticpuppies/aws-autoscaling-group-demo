# =============================================================================
# Unit: production / apps / web
# -----------------------------------------------------------------------------
# One-app instance of the `app` module. Duplicate this directory to stand up
# another app — change `app_name` and whatever app-specific inputs differ, and
# you're done. No Terraform file duplication.
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
    vpc_id            = "vpc-00000000000000000"
    vpc_cidr          = "10.0.0.0/16"
    public_subnet_ids = ["subnet-0000000000000000a", "subnet-0000000000000000b", "subnet-0000000000000000c"]
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
    vpc_id            = dependency.shared_infra.outputs.vpc_id
    vpc_cidr          = dependency.shared_infra.outputs.vpc_cidr
    public_subnet_ids = dependency.shared_infra.outputs.public_subnet_ids

    # -------------------------------------------------------------------------
    # Security / Networking
    # -------------------------------------------------------------------------
    ssh_allowed_cidrs      = []
    app_port               = 8080
    app_port_allowed_cidrs = ["0.0.0.0/0"]
    health_check_path      = "/health"

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
