# VPC — public subnets for the ALBs (both of them: the internal one still
# needs its ENIs to sit in subnets Terraform manages, even though it has no
# internet route), private subnets for the Fargate tasks.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
}

# Free gateway endpoint — keeps S3 traffic (Loki/Tempo bucket writes, ECR
# image layer pulls) off the NAT, trimming its data-processing charges.
# Same conclusion as observability-eks: removing the NAT entirely would need
# paid interface endpoints for ECR-API and Secrets Manager that cost more
# than the NAT itself, so it stays — this endpoint is the free part of that
# trade, not a replacement for it.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = { Name = "${var.project_name}-s3" }
}
