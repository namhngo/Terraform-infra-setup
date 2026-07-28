# The bucket is supplied at init time rather than hardcoded, because its name
# embeds the AWS account ID. `make init` derives it; see the repo README.
#
# use_lockfile replaces the DynamoDB table that older S3 backends needed for
# state locking (Terraform >= 1.11).
terraform {
  backend "s3" {
    key          = "observability/platform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
