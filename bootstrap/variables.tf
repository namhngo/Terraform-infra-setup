variable "aws_region" {
  description = "AWS region to create the state bucket in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for the state bucket name; must match the value used by the other stacks"
  type        = string
  default     = "obs-project"
}

variable "state_version_retention_days" {
  description = "How long to keep superseded state file versions before expiring them"
  type        = number
  default     = 90
}
