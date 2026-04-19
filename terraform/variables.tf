# =============================================================================
# General
# =============================================================================

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-3"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "app_name" {
  description = "Name of this application (used to namespace per-app resources, SSM parameters, and the on-instance compose directory). Multiple apps can share the same project/environment."
  type        = string
}

# =============================================================================
# VPC
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-southeast-3a", "ap-southeast-3b", "ap-southeast-3c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# =============================================================================
# Security
# =============================================================================

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed to SSH into instances"
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Port the containerized application listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB health checks"
  type        = string
  default     = "/health"
}

# =============================================================================
# EC2 / ASG
# =============================================================================

variable "ami_id" {
  description = "AMI ID built by Packer"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for ASG instances"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name (leave empty to disable SSH key)"
  type        = string
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

variable "health_check_grace_period" {
  description = "Seconds to wait before checking health of a new instance"
  type        = number
  default     = 300
}

variable "launch_lifecycle_heartbeat" {
  description = "Seconds the ASG launch lifecycle hook waits for user-data to signal completion before falling back to ABANDON (terminating the instance). Must comfortably exceed worst-case docker pull + container start time."
  type        = number
  default     = 600
}

# =============================================================================
# SSM / Application Config
# =============================================================================

variable "docker_image_repo" {
  description = "Docker image repository URI (e.g., 123456789.dkr.ecr.ap-southeast-3.amazonaws.com/myapp)"
  type        = string
}

variable "docker_image_tag" {
  description = "Initial Docker image tag"
  type        = string
  default     = "latest"
}

variable "app_env_vars" {
  description = "Map of environment variables for the container (stored as SecureString in SSM)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# =============================================================================
# Alerting
# =============================================================================

variable "alert_email" {
  description = "Email address to subscribe to the user-data error SNS topic. Leave empty to create the topic without an email subscription (subscriptions can also be added out-of-band)."
  type        = string
  default     = ""
}
