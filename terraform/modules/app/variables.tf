# =============================================================================
# App Module: Inputs
# -----------------------------------------------------------------------------
# Everything needed to deploy one app (ASG, target group + listener rule, IAM,
# SSM, SNS, app SG) onto the shared VPC + ALB. Shared-infra outputs flow in via
# the *_from_shared variables.
# =============================================================================

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project. Must match the value used by shared-infra."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging). Must match shared-infra."
  type        = string
}

variable "app_name" {
  description = "Name of this application. Used to namespace per-app resources, SSM parameters, and the on-instance compose directory (/home/ubuntu/<app_name>)."
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to per-app resources. Merged on top of shared tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Wiring from shared-infra (populated by Terragrunt `dependency` blocks)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID from shared-infra."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block from shared-infra (used by the node_exporter ingress rule)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from shared-infra. Used for ASG placement."
  type        = list(string)
}

variable "alb_listener_arn" {
  description = "Shared ALB HTTP listener ARN from shared-infra. The per-app listener rule attaches here."
  type        = string
}

variable "alb_security_group_id" {
  description = "Shared ALB security group ID from shared-infra. Referenced by the EC2 SG ingress rule."
  type        = string
}

# -----------------------------------------------------------------------------
# Security / Networking
# -----------------------------------------------------------------------------

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed to SSH into instances."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Port the containerized application listens on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB health checks."
  type        = string
  default     = "/health"
}

# -----------------------------------------------------------------------------
# ALB listener rule
# -----------------------------------------------------------------------------

variable "listener_rule_priority" {
  description = "Priority of the per-app listener rule on the shared ALB. Must be unique across all apps in the environment."
  type        = number
}

variable "listener_rule_path_patterns" {
  description = "Path patterns that route to this app. Defaults to catch-all."
  type        = list(string)
  default     = ["/*"]
}

# -----------------------------------------------------------------------------
# EC2 / ASG
# -----------------------------------------------------------------------------

variable "ami_id" {
  description = "AMI ID built by Packer."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for ASG instances."
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name (leave empty to disable SSH key)."
  type        = string
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the ASG."
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the ASG."
  type        = number
  default     = 2
}

variable "health_check_grace_period" {
  description = "Seconds to wait before checking health of a new instance."
  type        = number
  default     = 300
}

variable "launch_lifecycle_heartbeat" {
  description = "Seconds the ASG launch lifecycle hook waits for user-data to signal completion before falling back to ABANDON (terminating the instance). Must comfortably exceed worst-case docker pull + container start time."
  type        = number
  default     = 600
}

# -----------------------------------------------------------------------------
# SSM / Application Config
# -----------------------------------------------------------------------------

variable "docker_image_repo" {
  description = "Docker image repository URI (e.g., 123456789.dkr.ecr.ap-southeast-3.amazonaws.com/myapp). Seeded into SSM on first apply; CI/CD owns it thereafter (ignore_changes = [value])."
  type        = string
}

variable "docker_image_tag" {
  description = "Initial Docker image tag. Seeded into SSM on first apply; CI/CD owns it thereafter (ignore_changes = [value])."
  type        = string
  default     = "latest"
}

variable "app_env_vars" {
  description = "Map of environment variables for the container (stored as SecureString in SSM). Seeded on first apply; CI/CD or out-of-band updates own the values thereafter (ignore_changes = [value])."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Alerting
# -----------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address to subscribe to the user-data error SNS topic. Leave empty to create the topic without an email subscription (subscriptions can also be added out-of-band)."
  type        = string
  default     = ""
}
