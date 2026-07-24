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
