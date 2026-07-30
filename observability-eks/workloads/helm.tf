# Loki and Tempo run from their upstream Grafana charts rather than hand-rolled
# Deployments. These two are the storage backends whose on-disk config is fiddly
# and version-sensitive (schema config, S3 wiring, retention, metrics generator),
# which is exactly what the charts encapsulate. Alloy, Grafana and Prometheus
# stay as plain kubernetes_* resources in workloads.tf — they're simple, and
# charting them would only churn service names/ports and force ingress rewiring
# for no functional gain.
#
# Both charts are pinned. Both reuse the IRSA ServiceAccounts created in
# kubernetes.tf (serviceAccount.create = false) so S3 access flows through the
# same roles the platform stack defined. Both render a Service named exactly
# `loki` (:3100) and `tempo` (:3200 / :4317), so the Alloy config and Grafana
# datasources that address them by name need no changes.

# --- Loki (grafana/loki, SingleBinary mode) ---
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.55.0"
  namespace  = local.namespace

  values = [yamlencode({
    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = 1 }
      storage = {
        type        = "s3"
        bucketNames = { chunks = local.platform.loki_bucket, ruler = local.platform.loki_bucket, admin = local.platform.loki_bucket }
        s3          = { region = local.platform.aws_region }
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "s3"
          schema       = "v13"
          index        = { prefix = "index_", period = "24h" }
        }]
      }
      limits_config    = { retention_period = "${local.platform.loki_retention_hours}h" }
      pattern_ingester = { enabled = false }
      ruler            = { enable_api = false }
    }

    deploymentMode = "SingleBinary"
    singleBinary = {
      replicas = 1
      # A small writable volume is required even with data in S3: Loki's
      # compactor and WAL need a working directory at /var/loki, and the chart
      # runs with a read-only root filesystem otherwise (mkdir /var/loki fails).
      persistence = {
        enabled      = true
        size         = "10Gi"
        storageClass = kubernetes_storage_class.gp3.metadata[0].name
      }
    }

    # Use the IRSA ServiceAccount from kubernetes.tf.
    serviceAccount = { create = false, name = kubernetes_service_account.loki.metadata[0].name }

    # Everything below is scaled to zero / disabled — single-binary only.
    gateway      = { enabled = false }
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    read         = { replicas = 0 }
    write        = { replicas = 0 }
    backend      = { replicas = 0 }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
  })]

  depends_on = [kubernetes_service_account.loki]
}

# --- Tempo (grafana/tempo, single-binary) ---
# NOTE: this single-binary chart is marked deprecated upstream (they steer you to
# tempo-distributed, which is many-component overkill for one binary). It still
# tracks current Tempo app versions and is the right size here; revisit if this
# stack ever needs the distributed topology.
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.24.4"
  namespace  = local.namespace

  values = [yamlencode({
    replicas       = 1
    serviceAccount = { create = false, name = kubernetes_service_account.tempo.metadata[0].name }
    persistence    = { enabled = false }

    tempo = {
      reportingEnabled = false
      retention        = "${local.platform.tempo_retention_hours}h"

      storage = {
        trace = {
          backend = "s3"
          s3 = {
            bucket   = local.platform.tempo_bucket
            endpoint = "s3.${local.platform.aws_region}.amazonaws.com"
            region   = local.platform.aws_region
          }
        }
      }

      receivers = {
        otlp = { protocols = { grpc = { endpoint = "0.0.0.0:4317" } } }
      }

      # RED metrics (span-metrics + service-graphs) shipped to Prometheus, same
      # as the hand-rolled config did.
      metricsGenerator = {
        enabled        = true
        remoteWriteUrl = "http://prometheus:9090/api/v1/write"
        processor      = { span_metrics = {}, service_graphs = {} }
      }
    }
  })]

  depends_on = [kubernetes_service_account.tempo]
}
