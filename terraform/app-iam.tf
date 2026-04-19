# =============================================================================
# Per-App: IAM Role, Policies, and Instance Profile
# =============================================================================

resource "aws_iam_role" "ec2" {
  name = "${local.app_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# SSM Parameter Store read access
resource "aws_iam_role_policy" "ssm_read" {
  name = "ssm-parameter-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_parameter_prefix}/*"
    }]
  })
}

# EC2 self-tagging for instance naming
resource "aws_iam_role_policy" "ec2_self_tag" {
  name = "ec2-self-tag"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateTags",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

# ECR pull access
resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

# ASG lifecycle hook completion — instances must signal CONTINUE/ABANDON on
# launch so they can transition out of Pending:Wait and be attached to the
# target group.
resource "aws_iam_role_policy" "asg_lifecycle" {
  name = "asg-complete-lifecycle-action"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "autoscaling:CompleteLifecycleAction"
      Resource = module.asg.autoscaling_group_arn
    }]
  })
}

# SNS publish access for user-data error alerts
resource "aws_iam_role_policy" "sns_publish_alerts" {
  name = "sns-publish-user-data-alerts"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.user_data_alerts.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.app_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = local.common_tags
}
