# Terraform Infra Setup

Personal Terraform infrastructure projects.

## Modules

| Folder | Description |
|---|---|
| [`notifications/`](./notifications) | SQS + Lambda + SES async notification system |
| [`observability/`](./observability) | Observability stack *(coming soon)* |

## Getting Started

Each module is a standalone Terraform configuration. Navigate into the folder and run:

```bash
cd <module>
terraform init
terraform plan
terraform apply
```