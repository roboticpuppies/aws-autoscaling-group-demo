# =============================================================================
# Environment-scoped variables (production)
# -----------------------------------------------------------------------------
# Units under production/ load this file via
#   read_terragrunt_config(find_in_parent_folders("env.hcl"))
# and merge its `inputs` map into their own.
# =============================================================================

locals {
  environment = "production"

  # Reference-only. The provider block in root.hcl reads AWS_REGION from the
  # environment; this local exists so unit files can pin region-scoped inputs
  # (CIDRs, AZs) consistently with whatever provider region they're targeting.
  aws_region = "ap-southeast-3"
}

inputs = {
  environment = local.environment

  # VPC defaults shared across every unit in this environment.
  # Unit-level inputs can override.
  vpc_cidr            = "10.0.0.0/16"
  azs                 = ["ap-southeast-3a", "ap-southeast-3b", "ap-southeast-3c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
