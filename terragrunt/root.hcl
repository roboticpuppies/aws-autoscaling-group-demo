# =============================================================================
# Terragrunt Root Configuration
# -----------------------------------------------------------------------------
# This file is included by every unit via `include "root" { path = find_in_parent_folders("root.hcl") }`.
# It centralises:
#   * Remote state backend (S3)
#   * The AWS provider block (generated into each unit at init time)
#   * Terraform version / provider constraints (also generated)
#
# Targeted at Terragrunt v1.0.1 (OpenTofu-backed; `stack`/`unit` syntax native).
# =============================================================================

# =============================================================================
# >>> DEPLOYMENT CONFIGURATION — ADJUST BEFORE FIRST `terragrunt apply` <<<
# -----------------------------------------------------------------------------
# Everyone deploying this project for the first time should edit the four
# locals below. These are the only values you need to change here to retarget
# the project at a different AWS account, team, or region.
#
# Region-scoped inputs that are NOT controlled here (VPC CIDR, AZs, public
# subnet CIDRs) live in `terragrunt/<env>/env.hcl` — edit those too when
# switching regions.
# =============================================================================
locals {
  # Project identity. Ends up in the `Project` default tag and in the default
  # state-bucket name.
  project_name = "myproject"

  # Remote state S3 bucket. MUST be globally unique across all of AWS. Either
  # pre-create it yourself or let Terragrunt create it on first init.
  state_bucket = "${local.project_name}-terraform-state"

  # Region the state bucket lives in. Usually the same as `aws_region`.
  state_region = "ap-southeast-3"

  # Default provider region for every unit.
  aws_region = "ap-southeast-3"
}

# -----------------------------------------------------------------------------
# Remote state: S3 + native DynamoDB-free locking (S3 conditional writes in
# AWS provider v6 + Terraform 1.14 support use_lockfile-style state locking).
# Each unit gets its own key derived from its path relative to this file so
# state files never collide. Multi-region deployments are expected to use a
# separate state bucket per region (set `state_bucket` and `state_region`
# above when retargeting), which is why the key itself is region-agnostic.
# -----------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_bucket
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.state_region
    encrypt      = true
    use_lockfile = true
  }
}

# -----------------------------------------------------------------------------
# AWS provider block, generated into every unit.
# Keeps modules provider-free so they can be reused without edits.
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "${local.project_name}"
    }
  }
}
EOF
}

# -----------------------------------------------------------------------------
# Terraform + provider version constraints, generated into every unit so the
# modules themselves don't need to pin them twice.
# -----------------------------------------------------------------------------
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.41"
    }
  }
}
EOF
}

# -----------------------------------------------------------------------------
# Inputs exposed to every unit. Individual units and env.hcl files merge their
# own inputs on top.
# -----------------------------------------------------------------------------
inputs = {
  project_name = local.project_name
}
