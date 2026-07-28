# Namespace for all observability resources.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.k8s_namespace
  }
}

# --- ConfigMaps ---

resource "kubernetes_config_map" "alloy_config" {
  metadata {
    name      = "alloy-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "config.alloy" = file("${path.module}/configs/alloy/config.alloy")
  }
}

resource "kubernetes_config_map" "loki_config" {
  metadata {
    name      = "loki-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "loki.yml" = templatefile("${path.module}/configs/loki/loki.yml.tpl", {
      bucket_name     = aws_s3_bucket.loki.id
      region          = var.aws_region
      retention_hours = var.loki_retention_days * 24
    })
  }
}

resource "kubernetes_config_map" "tempo_config" {
  metadata {
    name      = "tempo-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "tempo.yml" = templatefile("${path.module}/configs/tempo/tempo.yml.tpl", {
      bucket_name     = aws_s3_bucket.tempo.id
      region          = var.aws_region
      retention_hours = var.tempo_retention_days * 24
    })
  }
}

resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = file("${path.module}/configs/prometheus/prometheus.yml")
  }
}

resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "datasources.yml" = file("${path.module}/configs/grafana/datasources.yml")
  }
}

resource "kubernetes_config_map" "grafana_dashboards_config" {
  metadata {
    name      = "grafana-dashboards-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "dashboards.yml" = file("${path.module}/configs/grafana/dashboards.yml")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_json" {
  metadata {
    name      = "grafana-dashboard-json"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "overview-dashboard.json" = file("${path.module}/configs/grafana/overview-dashboard.json")
  }
}

# --- Secrets (values sourced from Secrets Manager, see secrets.tf) ---

resource "kubernetes_secret" "alloy_auth" {
  metadata {
    name      = "alloy-auth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "bearer-token" = aws_secretsmanager_secret_version.alloy_bearer_token.secret_string
  }
}

resource "kubernetes_secret" "grafana_auth" {
  metadata {
    name      = "grafana-auth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "admin-password" = aws_secretsmanager_secret_version.grafana_admin_password.secret_string
  }
}

# --- ServiceAccounts (IRSA — see iam.tf for the underlying IAM roles) ---

resource "kubernetes_service_account" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn
    }
  }
}

resource "kubernetes_service_account" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tempo.arn
    }
  }
}

resource "kubernetes_service_account" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alloy.arn
    }
  }
}

resource "kubernetes_service_account" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.grafana.arn
    }
  }
}

# Prometheus needs no AWS permissions — plain ServiceAccount, no IRSA annotation.
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}
