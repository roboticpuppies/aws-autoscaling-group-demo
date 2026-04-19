module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs            = var.azs
  public_subnets = var.public_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  tags = local.common_tags
}
