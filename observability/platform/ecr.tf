# Private ECR repositories for the images this stack builds on. Mirroring the
# upstream images here (see `make push-images`) gives a company-style private
# registry: no Docker Hub pull-rate limits, CVE scanning on push, and image
# pulls that ride the S3 gateway endpoint instead of the public internet.
#
# Only the three hand-rolled Deployments (Alloy, Prometheus, Grafana) point at
# ECR. Loki and Tempo are installed by their Helm charts, which manage their own
# image references (main image plus sidecars) and pull upstream via the NAT
# gateway — mirroring those too is possible but out of scope here.

resource "aws_ecr_repository" "images" {
  for_each = toset(["alloy", "prometheus", "grafana"])

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag (e.g. v1.17.0) always resolves to the same image

  image_scanning_configuration {
    scan_on_push = true
  }

  # Repos hold only mirrored public images — safe to empty on destroy.
  force_delete = true
}

# Keep the repo tidy: retain the 5 most recent images, expire the rest.
resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
