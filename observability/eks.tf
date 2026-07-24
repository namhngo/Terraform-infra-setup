# VPC — public subnets for the ALB, private subnets for EKS worker nodes.
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

  # Required tags for the AWS Load Balancer Controller to auto-discover
  # subnets when provisioning ALBs from Ingress resources (added in step 9).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = var.project_name
  }
}

# EKS cluster + managed node group.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public access simplifies kubectl access for a personal-account learning
  # project. Restrict cluster_endpoint_public_access_cidrs for tighter security.
  cluster_endpoint_public_access = true

  # Grants the IAM identity running `terraform apply` cluster-admin via an
  # EKS Access Entry. Without this, the module (v20+) does NOT auto-grant
  # access to the creator — you'd get "must be logged in" errors from kubectl.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
    }
  }

  # Required for IRSA (IAM Roles for Service Accounts) used in iam.tf
  enable_irsa = true

  tags = {
    Project = var.project_name
  }
}
