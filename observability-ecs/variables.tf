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
  description = "Private subnet CIDRs (Fargate tasks, internal ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs (public ALB)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway instead of one per AZ (cheaper, less resilient — fine for a personal project)"
  type        = bool
  default     = true
}

# --- Retention ---

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

# --- Internal ingress ---

variable "internal_ingress_cidr_blocks" {
  description = <<-EOT
    CIDR blocks allowed to reach the internal ALB (the backend service's
    ingest path). Defaults to empty — the internal ALB is completely
    unreachable until you set this to your actual backend network's CIDR
    (a peered VPC's range, a specific subnet, etc.). There is deliberately
    no default that "just works", since this is the entire trust boundary
    for that path — see the README's Security notes.
  EOT
  type        = list(string)
  default     = []
}
