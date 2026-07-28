# Terraform Infra Setup

Personal Terraform infrastructure projects. Each folder is an independent
project — its own state, its own README, its own CI, its own lifecycle — with
nothing shared at this level, so any of them can be split into a standalone
repository without changes.

| Project | Description |
|---|---|
| [`notifications/`](./notifications) | SQS + Lambda + SES async notification system |
| [`observability/`](./observability) | Grafana LGTM stack on EKS |

Start from the README inside whichever project you're working on.
