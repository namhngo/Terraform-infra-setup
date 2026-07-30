# Terraform Infra Setup

Personal Terraform infrastructure projects. Each folder is an independent
project — its own state, its own README, its own CI, its own lifecycle — with
nothing shared at this level, so any of them can be split into a standalone
repository without changes.

| Project | Description |
|---|---|
| [`notifications/`](./notifications) | SQS + Lambda + SES async notification system |
| [`observability-eks/`](./observability-eks) | Grafana LGTM stack on EKS (learning project — full Kubernetes) |
| [`observability-ecs/`](./observability-ecs) | Grafana LGTM stack on ECS Fargate (no Kubernetes — dual-ALB ingress pattern) |

Start from the README inside whichever project you're working on.
