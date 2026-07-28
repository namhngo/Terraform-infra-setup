# Namespace for all observability resources.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = local.namespace
  }
}

# --- ConfigMaps ---
# Loki and Tempo render their own config via their Helm charts (see helm.tf),
# so only Alloy, Prometheus and Grafana have hand-managed ConfigMaps here.

resource "kubernetes_config_map" "alloy_config" {
  metadata {
    name      = "alloy-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "config.alloy" = file("${path.module}/configs/alloy/config.alloy")
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

# --- Secrets ---
# Values are read from Secrets Manager at apply time (see remote-state.tf); the
# platform stack owns them.

resource "kubernetes_secret" "alloy_auth" {
  metadata {
    name      = "alloy-auth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "bearer-token" = data.aws_secretsmanager_secret_version.alloy_bearer_token.secret_string
  }
}

resource "kubernetes_secret" "grafana_auth" {
  metadata {
    name      = "grafana-auth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "admin-password" = data.aws_secretsmanager_secret_version.grafana_admin_password.secret_string
  }
}

# --- ServiceAccounts (IRSA — roles are created in the platform stack) ---

resource "kubernetes_service_account" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = local.role_arns.loki
    }
  }
}

resource "kubernetes_service_account" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = local.role_arns.tempo
    }
  }
}

resource "kubernetes_service_account" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = local.role_arns.alloy
    }
  }
}

resource "kubernetes_service_account" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = local.role_arns.grafana
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
