# Public ALB. Internet-facing, in public subnets. Two target groups sharing
# one ALB via path-based listener rules — the default action (catch-all "/")
# goes to Grafana, and a rule sends /v1/* to Alloy. WAF (waf.tf) attaches to
# this ALB only.

resource "aws_lb" "public" {
  name               = "${var.project_name}-public"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_public.id]
}

resource "aws_lb_target_group" "alloy" {
  name        = "${var.project_name}-alloy"
  port        = 4318
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    # Alloy's readiness endpoint is served on its admin port (12345), not the
    # OTLP traffic port (4318) — the health check overrides the port
    # independently of the target group's registered traffic port.
    path     = "/-/ready"
    port     = "12345"
    protocol = "HTTP"
    matcher  = "200"
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-grafana"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path    = "/api/health"
    matcher = "200"
  }
}

# --- Listeners ---
# With a domain: HTTPS is the real listener, HTTP just redirects to it.
# Without one: HTTP is the only listener there is.

resource "aws_lb_listener" "public_https" {
  count = local.enable_tls ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.public[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_lb_listener" "public_http_redirect" {
  count = local.enable_tls ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "public_http" {
  count = local.enable_tls ? 0 : 1

  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

locals {
  # Whichever listener actually carries application traffic (HTTPS if TLS is
  # on, plain HTTP otherwise) — the listener rule below attaches to this one.
  public_listener_arn = local.enable_tls ? aws_lb_listener.public_https[0].arn : aws_lb_listener.public_http[0].arn
}

resource "aws_lb_listener_rule" "alloy_ingest" {
  listener_arn = local.public_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alloy.arn
  }

  condition {
    path_pattern {
      values = ["/v1/*"]
    }
  }
}
