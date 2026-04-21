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

locals {
  # Project-wide identity. Exposed to units so they don't have to re-declare it.
  project_name = "myproject"

  # State backend configuration.
  # TODO: replace with the bucket your team owns. You can also override this
  # via the TG_STATE_BUCKET env var without editing this file.
  state_bucket = get_env("TG_STATE_BUCKET", "myproject-terraform-state")
  state_region = get_env("TG_STATE_REGION", "ap-southeast-3")

  # Default provider region. Unit-level env.hcl can override.
  aws_region = get_env("AWS_REGION", "ap-southeast-3")
}

# -----------------------------------------------------------------------------
# Remote state: S3 + native DynamoDB-free locking (S3 conditional writes in
# AWS provider v6 + Terraform 1.14 support use_lockfile-style state locking).
# Each unit gets its own key derived from its path relative to this file so
# state files never collide.
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
