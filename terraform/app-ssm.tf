# =============================================================================
# Per-App: SSM Parameter Store
# =============================================================================

resource "aws_ssm_parameter" "docker_image_repo" {
  name  = "${local.ssm_parameter_prefix}/docker-image-repo"
  type  = "String"
  value = var.docker_image_repo

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "docker_image_tag" {
  name  = "${local.ssm_parameter_prefix}/docker-image-tag"
  type  = "String"
  value = var.docker_image_tag

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "app_env_vars" {
  for_each = nonsensitive(toset(keys(var.app_env_vars)))

  name  = "${local.ssm_parameter_prefix}/env/${each.key}"
  type  = "SecureString"
  value = var.app_env_vars[each.key]

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}
