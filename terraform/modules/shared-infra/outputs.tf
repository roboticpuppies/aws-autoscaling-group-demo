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

output "alb_arn" {
  description = "Shared ALB ARN."
  value       = module.alb.arn
}

output "alb_dns_name" {
  description = "Shared ALB DNS name."
  value       = module.alb.dns_name
}

output "alb_listener_http_arn" {
  description = "ARN of the shared ALB's HTTP listener. Per-app listener rules attach here."
  value       = module.alb.listeners["http"].arn
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB. Per-app EC2 SGs reference it as an ingress source."
  value       = aws_security_group.alb.id
}

output "shared_name_prefix" {
  description = "Shared resource prefix (<project>-<env>), for reference."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to shared resources. Per-app resources merge their own tags on top."
  value       = local.common_tags
}
