variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "obs-project"
}

# --- Retention ---
# Enforced here as S3 lifecycle rules and exported for the Loki and Tempo
# configs in the workloads stack, so both sides agree on one number.

variable "loki_retention_days" {
  description = "Days to retain Loki log chunks in S3 before expiration"
  type        = number
  default     = 90
}

variable "tempo_retention_days" {
  description = "Days to retain Tempo trace blocks in S3 before expiration"
  type        = number
  default     = 30
}

# --- Networking ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs (EKS worker nodes)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs (ALB)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway instead of one per AZ (cheaper, less resilient — fine for a personal project)"
  type        = bool
  default     = true
}

# --- EKS ---

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the EKS public API endpoint. Defaults to open, which
    is what the AWS module does too, but it means anyone on the internet can
    attempt to authenticate against your control plane. Set this to your own
    address (e.g. ["203.0.113.4/32"]) — `curl -s https://checkip.amazonaws.com`
    prints it.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Kubernetes ---
# Needed here because the IRSA trust policies in iam.tf are scoped to specific
# namespace/ServiceAccount pairs.

variable "k8s_namespace" {
  description = "Kubernetes namespace for all observability resources"
  type        = string
  default     = "monitoring"
}

# --- TLS ---

variable "domain_name" {
  description = <<-EOT
    Route53-hosted domain used to issue an ACM certificate, enabling HTTPS on the
    ALB. Leave empty to serve plaintext HTTP, in which case the Grafana admin
    password and all telemetry cross the internet unencrypted — acceptable only
    for a short-lived throwaway environment.
  EOT
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Hostname prefix within domain_name for the observability endpoint"
  type        = string
  default     = "observability"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for domain_name; required when domain_name is set"
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || var.route53_zone_id != ""
    error_message = "route53_zone_id must be set when domain_name is set, so the ACM certificate can be DNS-validated."
  }
}
