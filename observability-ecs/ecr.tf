# Private ECR repositories for all 5 services. Unlike observability-eks
# (where Loki and Tempo are Helm-chart-managed and only 3 images needed
# custom builds), ECS Fargate has no ConfigMap equivalent — every service's
# config file has to be baked into its image, so all 5 are custom-built here.
# See docker/ for the Dockerfiles and `make build-images` in the Makefile.
#
# MUTABLE tags, deliberately different from observability-eks's IMMUTABLE
# choice: those 3 repos held exact, unchanged mirrors of upstream images —
# a tag only needed to move when the upstream version did. Here, every
# image bakes in a config file from configs/ that you'll likely edit and
# rebuild under the *same* version tag while iterating (e.g. tweaking
# config.alloy without bumping v1.17.0). IMMUTABLE tags would reject that
# re-push outright.

resource "aws_ecr_repository" "images" {
  for_each = toset(["alloy", "loki", "tempo", "prometheus", "grafana"])

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Repos hold only mirrored/rebuilt public images — safe to empty on destroy.
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
