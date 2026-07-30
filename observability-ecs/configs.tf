# Renders the Loki and Tempo config templates with the actual bucket
# name/region/retention, writing them into the docker/ build context so their
# Dockerfiles can COPY a config that already has real values — no
# templating step inside the image build itself.
#
# Alloy, Prometheus, and Grafana's configs need no per-environment values, so
# they're static files under configs/ and their Dockerfiles COPY directly
# from there — no local_file resource needed for those three.

resource "local_file" "loki_config" {
  filename = "${path.module}/docker/loki/loki.yml"
  content = templatefile("${path.module}/configs/loki/loki.yml.tpl", {
    bucket_name     = aws_s3_bucket.loki.id
    region          = var.aws_region
    retention_hours = var.loki_retention_days * 24
  })
}

resource "local_file" "tempo_config" {
  filename = "${path.module}/docker/tempo/tempo.yml"
  content = templatefile("${path.module}/configs/tempo/tempo.yml.tpl", {
    bucket_name     = aws_s3_bucket.tempo.id
    region          = var.aws_region
    retention_hours = var.tempo_retention_days * 24
  })
}
