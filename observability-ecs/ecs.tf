# ECS cluster, Cloud Map namespace for Service Connect (this is the ECS
# equivalent of Kubernetes' built-in cluster DNS — it's how "loki:3100",
# "tempo:4317", "prometheus:9090" resolve from inside Alloy/Grafana's
# containers, matching the hostnames baked into configs/), CloudWatch log
# groups, and the 5 task definitions + services themselves.

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

resource "aws_service_discovery_http_namespace" "this" {
  name = var.project_name
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]
}

locals {
  image_tags = {
    alloy      = "v1.17.0"
    loki       = "3.7.2"
    tempo      = "2.10.7"
    prometheus = "v3.12.0"
    grafana    = "13.0.2"
  }

  log_retention_days = 7
}

resource "aws_cloudwatch_log_group" "services" {
  for_each = local.image_tags

  name              = "/ecs/${var.project_name}-${each.key}"
  retention_in_days = local.log_retention_days
}

# ─────────────────────────────────────────────────────────────────────────
# Alloy — OTLP collector. Advertises itself as "alloy:12345" over Service
# Connect so Prometheus can scrape it; receives OTLP from both ALBs directly
# on 4318 (that path doesn't go through Service Connect, it's a normal ALB
# target-group registration on the task's ENI).
# ─────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "alloy" {
  family                   = "${var.project_name}-alloy"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  # No task_role_arn: Alloy needs no AWS permissions. The bearer token WAF
  # checks against is embedded from Terraform's own random_password value
  # (waf.tf) — Alloy is never asked to read it from Secrets Manager.

  container_definitions = jsonencode([{
    name  = "alloy"
    image = "${aws_ecr_repository.images["alloy"].repository_url}:${local.image_tags.alloy}"
    portMappings = [
      { name = "otlp", containerPort = 4318, protocol = "tcp" },
      { name = "admin", containerPort = 12345, protocol = "tcp" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["alloy"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "alloy"
      }
    }
  }])
}

resource "aws_ecs_service" "alloy" {
  name            = "${var.project_name}-alloy"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.alloy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.alloy.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alloy.arn
    container_name   = "alloy"
    container_port   = 4318
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn

    service {
      port_name = "admin"
      client_alias {
        port     = 12345
        dns_name = "alloy"
      }
    }
  }

  depends_on = [aws_lb_listener.public_http, aws_lb_listener.public_https]
}

# ─────────────────────────────────────────────────────────────────────────
# Loki — log storage (S3 backend via its ECS task role)
# ─────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "loki" {
  family                   = "${var.project_name}-loki"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.task["loki"].arn

  container_definitions = jsonencode([{
    name  = "loki"
    image = "${aws_ecr_repository.images["loki"].repository_url}:${local.image_tags.loki}"
    portMappings = [
      { name = "http", containerPort = 3100, protocol = "tcp" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["loki"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "loki"
      }
    }
  }])
}

resource "aws_ecs_service" "loki" {
  name            = "${var.project_name}-loki"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.loki.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn

    service {
      port_name = "http"
      client_alias {
        port     = 3100
        dns_name = "loki"
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Tempo — trace storage (S3 backend via its ECS task role)
# ─────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "tempo" {
  family                   = "${var.project_name}-tempo"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.task["tempo"].arn

  container_definitions = jsonencode([{
    name  = "tempo"
    image = "${aws_ecr_repository.images["tempo"].repository_url}:${local.image_tags.tempo}"
    portMappings = [
      { name = "otlp-grpc", containerPort = 4317, protocol = "tcp" },
      { name = "http", containerPort = 3200, protocol = "tcp" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["tempo"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "tempo"
      }
    }
  }])
}

resource "aws_ecs_service" "tempo" {
  name            = "${var.project_name}-tempo"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.tempo.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.tempo.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn

    service {
      port_name = "otlp-grpc"
      client_alias {
        port     = 4317
        dns_name = "tempo"
      }
    }

    service {
      port_name = "http"
      client_alias {
        port     = 3200
        dns_name = "tempo"
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Prometheus — metrics storage. No task role: it needs no AWS permissions.
# Ephemeral Fargate task storage instead of an external volume (there's no
# EBS-PVC-equivalent gotcha to work around here, unlike observability-eks).
# ─────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project_name}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "prometheus"
    image = "${aws_ecr_repository.images["prometheus"].repository_url}:${local.image_tags.prometheus}"
    portMappings = [
      { name = "http", containerPort = 9090, protocol = "tcp" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["prometheus"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "prometheus"
      }
    }
  }])
}

resource "aws_ecs_service" "prometheus" {
  name            = "${var.project_name}-prometheus"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.prometheus.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn

    service {
      port_name = "http"
      client_alias {
        port     = 9090
        dns_name = "prometheus"
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Grafana — dashboards. A pure Service Connect client (queries Loki/Tempo/
# Prometheus by name) — it advertises no service{} block of its own, since
# nothing inside the mesh calls Grafana; only the public ALB does, via a
# normal target-group registration on the task's ENI.
# ─────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.task["grafana"].arn

  container_definitions = jsonencode([{
    name  = "grafana"
    image = "${aws_ecr_repository.images["grafana"].repository_url}:${local.image_tags.grafana}"
    portMappings = [
      { name = "http", containerPort = 3000, protocol = "tcp" },
    ]
    environment = [
      { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
      { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
      { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
      { name = "GF_SERVER_ROOT_URL", value = local.enable_tls ? "https://${local.fqdn}" : "http://${aws_lb.public.dns_name}" },
    ]
    secrets = [
      {
        name      = "GF_SECURITY_ADMIN_PASSWORD"
        valueFrom = aws_secretsmanager_secret.grafana_admin_password.arn
      },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["grafana"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "grafana"
      }
    }
  }])
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-grafana"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.grafana.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn
  }

  depends_on = [aws_lb_listener.public_http, aws_lb_listener.public_https]
}
