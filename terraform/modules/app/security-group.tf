# =============================================================================
# Per-App: EC2 Security Group
# =============================================================================

resource "aws_security_group" "ec2" {
  name_prefix = "${local.app_prefix}-ec2-"
  description = "Security group for EC2 instances in the ${var.app_name} ASG"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.app_prefix}-ec2-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_app" {
  for_each = toset(var.app_port_allowed_cidrs)

  security_group_id = aws_security_group.ec2.id
  description       = "App port from ${each.value}"
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.ec2.id
  description       = "SSH from ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ec2_node_exporter" {
  security_group_id = aws_security_group.ec2.id
  description       = "node_exporter from VPC"
  from_port         = 9100
  to_port           = 9100
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
