# Workloads stack — everything that runs inside the cluster. The cluster itself
# belongs to ../platform.
#
# The kubernetes and helm providers are configured from a data source that looks
# the cluster up by name, not from a resource in this state. That is what makes
# the teardown safe: `terraform destroy` here removes the ingresses while the
# cluster and its load balancer controller are still fully running, so the
# controller completes its own ALB cleanup and clears the ingress finalizers the
# way it is designed to. Destroying the platform stack afterwards then has no
# controller-owned AWS resources left to trip over.
#
# This replaced a destroy-time local-exec provisioner that had to delete ALBs,
# target groups, ENIs, admission webhooks and security groups by hand.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Stack     = "observability/workloads"
    }
  }
}

# Looked up by name rather than read from remote state so that the provider
# blocks below do not depend on a remote state read.
data "aws_eks_cluster" "this" {
  name = "${var.project_name}-cluster"
}

locals {
  cluster_auth_args = [
    "eks", "get-token",
    "--cluster-name", data.aws_eks_cluster.this.name,
    "--region", var.aws_region,
  ]
}

# Tokens come from `aws eks get-token` at plan/apply time rather than a cached
# data source, since EKS tokens expire after ~15 minutes and a full apply of this
# stack takes longer than that.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.cluster_auth_args
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.cluster_auth_args
    }
  }
}
