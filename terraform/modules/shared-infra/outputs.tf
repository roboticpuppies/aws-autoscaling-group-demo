# =============================================================================
# Shared Infrastructure Module: Outputs
# -----------------------------------------------------------------------------
# These values are consumed by per-app units via Terragrunt `dependency` blocks.
# =============================================================================

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block (needed by per-app SGs for intra-VPC scrape rules)."
  value       = var.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "shared_name_prefix" {
  description = "Shared resource prefix (<project>-<env>), for reference."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to shared resources. Per-app resources merge their own tags on top."
  value       = local.common_tags
}
