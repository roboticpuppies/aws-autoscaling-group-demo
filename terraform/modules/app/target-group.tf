# =============================================================================
# Per-App: Target Group and ALB Listener Rule
# -----------------------------------------------------------------------------
# The target group lives here; the listener rule attaches to the shared ALB's
# HTTP listener (ARN comes in via var.alb_listener_arn). Listener rule priority
# is caller-controlled — each app must pick a unique value.
# =============================================================================

resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = tostring(var.app_port)
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${local.app_prefix}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "app" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = var.listener_rule_path_patterns
    }
  }

  tags = local.common_tags
}
