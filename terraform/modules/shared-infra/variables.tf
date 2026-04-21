# =============================================================================
# Shared Infrastructure Module: Inputs
# -----------------------------------------------------------------------------
# This module provisions infrastructure that is shared across every app deployed
# into a given project/environment:
#   - VPC (3 AZs, public subnets)
#   - ALB (internet-facing, default 404 listener)
#   - ALB security group
#
# Per-app resources (ASG, target group, IAM, SSM, SNS, app SG) live in the
# `app` module.
# =============================================================================

variable "project_name" {
  description = "Name of the project, used as the prefix for all shared resources."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones for the VPC."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to apply to all shared resources."
  type        = map(string)
  default     = {}
}
