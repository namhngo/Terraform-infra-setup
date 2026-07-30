# One security group per ALB, plus one per service. Each SG allows exactly
# what talks to it — no wildcard VPC-CIDR rules — so the network layer
# enforces the same "who can reach whom" story as the target-group wiring.

# --- Public ALB: internet-facing, browser/web-app traffic ---
resource "aws_security_group" "alb_public" {
  name_prefix = "${var.project_name}-alb-public-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from the internet (redirects to HTTPS if domain_name is set, otherwise this is the only listener)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Internal ALB: VPC-only, restricted to the backend service's network ---
# This is the entire trust boundary for that ingest path — see README
# "Security notes". No CIDRs configured means nothing can reach it.
resource "aws_security_group" "alb_internal" {
  name_prefix = "${var.project_name}-alb-internal-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "OTLP from the allowlisted backend network"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = var.internal_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Alloy: receives from both ALBs ---
resource "aws_security_group" "alloy" {
  name_prefix = "${var.project_name}-alloy-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "OTLP from the public ALB"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }

  ingress {
    description     = "OTLP from the internal ALB"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_internal.id]
  }

  ingress {
    description     = "ALB health checks (/-/ready on the admin port, not the OTLP traffic port)"
    from_port       = 12345
    to_port         = 12345
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id, aws_security_group.alb_internal.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Loki: receives from Alloy (writes) and Grafana (queries) ---
resource "aws_security_group" "loki" {
  name_prefix = "${var.project_name}-loki-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Log writes from Alloy"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id]
  }

  ingress {
    description     = "Queries from Grafana"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Tempo: receives from Alloy (gRPC writes) and Grafana (HTTP queries) ---
resource "aws_security_group" "tempo" {
  name_prefix = "${var.project_name}-tempo-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Trace writes from Alloy (gRPC)"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id]
  }

  ingress {
    description     = "Queries from Grafana (HTTP)"
    from_port       = 3200
    to_port         = 3200
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Prometheus: receives from Alloy, Tempo (span metrics), and Grafana ---
resource "aws_security_group" "prometheus" {
  name_prefix = "${var.project_name}-prometheus-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Metrics writes from Alloy"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id]
  }

  ingress {
    description     = "Span-metrics remote_write from Tempo"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.tempo.id]
  }

  ingress {
    description     = "Queries from Grafana"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Grafana: receives from the public ALB only (dashboards have their own login) ---
resource "aws_security_group" "grafana" {
  name_prefix = "${var.project_name}-grafana-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Dashboard UI from the public ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_public.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
