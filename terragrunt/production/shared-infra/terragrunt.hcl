# =============================================================================
# Unit: production / shared-infra
# -----------------------------------------------------------------------------
# Deploys the shared VPC. App units depend on this unit and consume its
# outputs (vpc_id, vpc_cidr, public_subnet_ids) via `dependency` blocks.
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/terraform/modules/shared-infra"
}

inputs = merge(
  local.env.inputs,
  {
    # Inherited from env.hcl: environment, vpc_cidr, azs, public_subnet_cidrs.
    # No overrides needed here for a minimal single-environment setup.
  }
)
