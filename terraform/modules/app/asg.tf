# =============================================================================
# Per-App: Auto Scaling Group
# =============================================================================

module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.2.0"

  name = "${local.app_prefix}-asg"

  # Launch template
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    region              = data.aws_region.current.region
    ssm_prefix          = local.ssm_parameter_prefix
    app_port            = var.app_port
    app_name            = var.app_name
    asg_name            = "${local.app_prefix}-asg"
    account_id          = data.aws_caller_identity.current.account_id
    sns_topic_arn       = aws_sns_topic.user_data_alerts.arn
    lifecycle_hook_name = local.launch_lifecycle_hook_name
  }))

  security_groups = [aws_security_group.ec2.id]

  # IAM instance profile (created externally in iam.tf)
  create_iam_instance_profile = false
  iam_instance_profile_arn    = aws_iam_instance_profile.ec2.arn

  # Enforce IMDSv2
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # ASG configuration
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  vpc_zone_identifier = var.public_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # Attach to the per-app target group
  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = aws_lb_target_group.app.arn
      traffic_source_type       = "elbv2"
    }
  }

  # Hold new instances in Pending:Wait (not yet attached to the target group)
  # until user-data calls complete-lifecycle-action. If the heartbeat expires,
  # the instance is ABANDONed (terminated) instead of joining in a broken state.
  initial_lifecycle_hooks = [
    {
      name                 = local.launch_lifecycle_hook_name
      default_result       = "ABANDON"
      heartbeat_timeout    = var.launch_lifecycle_heartbeat
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    }
  ]

  # Instance refresh for rolling updates
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      instance_warmup        = var.health_check_grace_period
    }
  }

  # ASG metrics
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  tags = local.common_tags
}
