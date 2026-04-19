# =============================================================================
# Per-App: Target Group and ALB Listener Rule
# =============================================================================

resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
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
  listener_arn = module.alb.listeners["http"].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = local.common_tags
}
