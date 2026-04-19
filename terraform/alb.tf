# =============================================================================
# Shared Application Load Balancer
# =============================================================================

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.0"

  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  # Use externally managed security group
  create_security_group = false
  security_groups       = [aws_security_group.alb.id]

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      # Default action: return 404 for unmatched requests
      # Per-app listener rules forward traffic to their target groups
      fixed_response = {
        content_type = "text/plain"
        message_body = "No application matched this request"
        status_code  = "404"
      }
    }
  }

  tags = local.common_tags
}
