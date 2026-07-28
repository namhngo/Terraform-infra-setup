# Both Ingresses share a single ALB via group.name, which avoids paying for two.
# Routing is path-based rather than host-based so it works with or without a
# custom domain: the OTLP paths go to Alloy, everything else falls through to
# Grafana. group.order controls rule evaluation (lower first), so Alloy's specific
# paths are matched before Grafana's catch-all.
#
# Authentication for the /v1/ ingest paths is enforced by the WAF ACL attached
# below, not by Alloy — see the platform stack's waf.tf.

locals {
  # Shared across both Ingresses; they must agree or the controller will
  # reconcile the shared ALB back and forth between two configurations.
  alb_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/group.name"  = local.platform.project_name

      # The HTTP listener is kept when TLS is on purely so the ALB has something
      # to redirect from.
      "alb.ingress.kubernetes.io/listen-ports" = local.enable_tls ? jsonencode([
        { HTTP = 80 }, { HTTPS = 443 }
      ]) : jsonencode([{ HTTP = 80 }])
    },
    local.enable_tls ? {
      "alb.ingress.kubernetes.io/certificate-arn" = local.platform.acm_certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    } : {}
  )
}

resource "kubernetes_ingress_v1" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name

    annotations = merge(local.alb_annotations, {
      "alb.ingress.kubernetes.io/group.order"      = "10"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/-/ready"
      "alb.ingress.kubernetes.io/healthcheck-port" = "12345"

      # The ACL binds at the ALB level, so it only needs referencing once across
      # the whole ingress group.
      "alb.ingress.kubernetes.io/wafv2-acl-arn" = local.platform.waf_web_acl_arn
    })
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        dynamic "path" {
          for_each = ["/v1/traces", "/v1/logs", "/v1/metrics"]

          content {
            path      = path.value
            path_type = "Prefix"
            backend {
              service {
                name = kubernetes_service.alloy.metadata[0].name
                port { number = 4318 }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.lb_controller]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name

    annotations = merge(local.alb_annotations, {
      "alb.ingress.kubernetes.io/group.order"      = "20"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
      "alb.ingress.kubernetes.io/healthcheck-port" = "3000"
    })
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.grafana.metadata[0].name
              port { number = 3000 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.lb_controller]
}
