# Both Ingresses share a single ALB via group.name — avoids paying for two
# ALBs. Since there's no custom domain, routing is path-based rather than
# host-based: OTLP paths go to Alloy, everything else falls through to
# Grafana. group.order controls rule evaluation order (lower = evaluated
# first) so Alloy's specific paths are checked before Grafana's catch-all.

resource "kubernetes_ingress_v1" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/group.name"       = var.project_name
      "alb.ingress.kubernetes.io/group.order"      = "10"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/-/ready"
      "alb.ingress.kubernetes.io/healthcheck-port" = "12345"
      "alb.ingress.kubernetes.io/wafv2-acl-arn"    = aws_wafv2_web_acl.observability.arn
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/v1/traces"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.alloy.metadata[0].name
              port { number = 4318 }
            }
          }
        }
        path {
          path      = "/v1/logs"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.alloy.metadata[0].name
              port { number = 4318 }
            }
          }
        }
        path {
          path      = "/v1/metrics"
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

  depends_on = [helm_release.lb_controller]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/group.name"       = var.project_name
      "alb.ingress.kubernetes.io/group.order"      = "20"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
      "alb.ingress.kubernetes.io/healthcheck-port" = "3000"
    }
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
