# =============================================================================
# Environment-scoped variables (production)
# -----------------------------------------------------------------------------
# Units under production/ load this file via
#   read_terragrunt_config(find_in_parent_folders("env.hcl"))
# and merge its `inputs` map into their own.
# =============================================================================

locals {
  environment = "production"
}

inputs = {
  environment = local.environment

  # VPC defaults shared across every unit in this environment.
  # Unit-level inputs can override.
  #
  # NOTE: `azs` must match the region set in `terragrunt/root.hcl`
  # (local.aws_region). If you change the region there, update this list too.
  vpc_cidr            = "10.0.0.0/16"
  azs                 = ["ap-southeast-3a", "ap-southeast-3b", "ap-southeast-3c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
