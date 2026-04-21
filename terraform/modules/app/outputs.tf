# =============================================================================
# App Module: Outputs
# =============================================================================

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = module.asg.autoscaling_group_name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN."
  value       = module.asg.autoscaling_group_arn
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = module.asg.launch_template_id
}

output "target_group_arn" {
  description = "Target group ARN."
  value       = aws_lb_target_group.app.arn
}

output "iam_role_arn" {
  description = "EC2 IAM role ARN."
  value       = aws_iam_role.ec2.arn
}

output "security_group_id" {
  description = "EC2 security group ID."
  value       = aws_security_group.ec2.id
}

output "ssm_parameter_prefix" {
  description = "SSM parameter prefix used for this app."
  value       = local.ssm_parameter_prefix
}

output "app_compose_dir" {
  description = "On-instance directory containing docker-compose.yml and .env for this app."
  value       = "/home/ubuntu/${var.app_name}"
}

output "user_data_alerts_topic_arn" {
  description = "SNS topic ARN that receives user-data script failure alerts."
  value       = aws_sns_topic.user_data_alerts.arn
}
