# gp3 StorageClass — EKS doesn't provide one by default post-1.23
# (in-tree gp2 provisioner is deprecated; EBS CSI driver requires an
# explicit StorageClass). The EBS CSI driver addon itself is a cluster addon in
# the platform stack, so it is already present by the time this stack runs.
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }
}

resource "kubernetes_persistent_volume_claim" "prometheus_data" {
  metadata {
    name      = "prometheus-data"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  # The gp3 StorageClass above binds WaitForFirstConsumer, so this claim stays
  # Pending until a pod mounts it. The provider otherwise blocks on Bound, and
  # the only consumer is kubernetes_deployment.prometheus, which depends on this
  # resource — a deadlock that ends in "context deadline exceeded".
  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.gp3.metadata[0].name
    resources {
      requests = {
        storage = "${var.prometheus_storage_gb}Gi"
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Alloy — OTLP collector. Deployment (not DaemonSet): it's a push-based
# receiver, not a node-level log scraper, so one replica is correct.
# ─────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "alloy" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "alloy" }
    }
    template {
      metadata {
        labels = { app = "alloy" }
      }
      spec {
        service_account_name = kubernetes_service_account.alloy.metadata[0].name

        container {
          name  = "alloy"
          image = "grafana/alloy:v1.17.0"
          args  = ["run", "--server.http.listen-addr=0.0.0.0:12345", "/etc/alloy/config.alloy"]

          port {
            container_port = 4318
            name           = "otlp-http"
          }
          port {
            container_port = 12345
            name           = "admin"
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1024Mi" }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/alloy"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/-/ready"
              port = 12345
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 12345
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.alloy_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "alloy" }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Loki — log storage (S3 backend via IRSA)
# ─────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "loki" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "loki" }
    }
    template {
      metadata {
        labels = { app = "loki" }
      }
      spec {
        service_account_name = kubernetes_service_account.loki.metadata[0].name

        container {
          name  = "loki"
          image = "grafana/loki:3.7.2"
          args  = ["-config.file=/etc/loki/loki.yml"]

          port {
            container_port = 3100
            name           = "http"
          }

          resources {
            requests = { cpu = "500m", memory = "1024Mi" }
            limits   = { cpu = "1000m", memory = "2048Mi" }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/loki"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 3100
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = 3100
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.loki_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "loki" }
    port {
      name        = "http"
      port        = 3100
      target_port = 3100
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Tempo — trace storage (S3 backend via IRSA)
# ─────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "tempo" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "tempo" }
    }
    template {
      metadata {
        labels = { app = "tempo" }
      }
      spec {
        service_account_name = kubernetes_service_account.tempo.metadata[0].name

        container {
          name  = "tempo"
          image = "grafana/tempo:2.10.7"
          args  = ["-config.file=/etc/tempo/tempo.yml"]

          port {
            container_port = 3200
            name           = "http"
          }
          port {
            container_port = 4317
            name           = "otlp-grpc"
          }

          resources {
            requests = { cpu = "500m", memory = "1024Mi" }
            limits   = { cpu = "1000m", memory = "2048Mi" }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/tempo"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 3200
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = 3200
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.tempo_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "tempo" }
    port {
      name        = "http"
      port        = 3200
      target_port = 3200
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Prometheus — metrics storage (PVC, no AWS permissions needed)
# ─────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "prometheus" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "prometheus" }
    }
    template {
      metadata {
        labels = { app = "prometheus" }
      }
      spec {
        service_account_name = kubernetes_service_account.prometheus.metadata[0].name

        # The official prom/prometheus image runs as non-root (UID/GID 65534).
        # Without fsGroup, the mounted EBS PVC is owned by root and Prometheus
        # can't write its WAL/TSDB, causing a permission-denied crash loop.
        security_context {
          fs_group = 65534
        }

        container {
          name  = "prometheus"
          image = "prom/prometheus:v3.12.0"
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--web.enable-remote-write-receiver",
            "--enable-feature=exemplar-storage",
            "--storage.tsdb.retention.time=15d",
            "--storage.tsdb.path=/prometheus",
          ]

          port {
            container_port = 9090
            name           = "http"
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1024Mi" }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }

          liveness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus_config.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "prometheus" }
    port {
      name        = "http"
      port        = 9090
      target_port = 9090
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Grafana — dashboards (Secrets Manager password via IRSA)
# ─────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "grafana" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "grafana" }
    }
    template {
      metadata {
        labels = { app = "grafana" }
      }
      spec {
        service_account_name = kubernetes_service_account.grafana.metadata[0].name

        container {
          name  = "grafana"
          image = "grafana/grafana:13.0.2"

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "GF_AUTH_ANONYMOUS_ENABLED"
            value = "false"
          }
          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }
          env {
            name  = "GF_USERS_ALLOW_SIGN_UP"
            value = "false"
          }
          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_auth.metadata[0].name
                key  = "admin-password"
              }
            }
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1024Mi" }
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards-config"
            mount_path = "/etc/grafana/provisioning/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "dashboard-json"
            mount_path = "/etc/grafana/provisioning/dashboards/json"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata[0].name
          }
        }
        volume {
          name = "dashboards-config"
          config_map {
            name = kubernetes_config_map.grafana_dashboards_config.metadata[0].name
          }
        }
        volume {
          name = "dashboard-json"
          config_map {
            name = kubernetes_config_map.grafana_dashboard_json.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "grafana" }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}
