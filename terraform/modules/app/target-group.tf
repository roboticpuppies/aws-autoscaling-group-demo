# =============================================================================
# Per-App: Target Group
# -----------------------------------------------------------------------------
# The ASG attaches to this target group via `traffic_source_attachments` in
# asg.tf. With no ALB listener forwarding to it, the target group exists purely
# as the health-check surface the ASG reads from (health_check_type = "ELB") —
# that is what drives self-healing when an instance stops responding.
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
