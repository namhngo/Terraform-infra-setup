# Platform stack — every AWS resource the observability stack needs, and nothing
# that lives inside the cluster. It therefore configures only the aws provider.
#
# That is the whole point of the split. When the kubernetes and helm providers
# were configured from module.eks outputs in this same root module, the provider
# had to be initialised from a resource in its own state, which is what made both
# apply and destroy fragile: Terraform could tear the cluster down while still
# holding Kubernetes resources that needed it, and a destroy could leave the
# provider pointing at a cluster that no longer existed. The in-cluster resources
# now live in ../workloads, which reads this stack's outputs.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Stack     = "observability/platform"
    }
  }
}
