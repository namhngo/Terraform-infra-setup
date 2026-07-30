# Deliberately small. Anything shared with the platform stack is read from its
# outputs (see remote-state.tf) so the two cannot drift apart. These are the two
# values needed before that remote state can be located, plus settings that only
# affect in-cluster resources.

variable "aws_region" {
  description = "AWS region the platform stack was deployed into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Resource name prefix; must match the platform stack"
  type        = string
  default     = "obs-project"
}

variable "prometheus_storage_gb" {
  description = "Size of the Prometheus PVC in GiB"
  type        = number
  default     = 50
}
