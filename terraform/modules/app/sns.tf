# =============================================================================
# Per-App: SNS Topic for User-Data Error Alerts
# -----------------------------------------------------------------------------
# Instances publish to this topic when the user-data script fails so the ops
# team learns about boot-time regressions (bad image tag, missing SSM param,
# ECR auth failure, etc.) without having to pull console output by hand.
# =============================================================================

resource "aws_sns_topic" "user_data_alerts" {
  name = "${local.app_prefix}-user-data-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "user_data_alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.user_data_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
