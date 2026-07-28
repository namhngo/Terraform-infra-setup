terraform {
  backend "s3" {
    key          = "observability/workloads.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
