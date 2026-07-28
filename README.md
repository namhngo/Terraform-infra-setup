# Terraform Infra Setup

Personal Terraform infrastructure projects.

## Stacks

| Folder | Description |
|---|---|
| [`bootstrap/`](./bootstrap) | S3 bucket holding remote state for every other stack |
| [`notifications/`](./notifications) | SQS + Lambda + SES async notification system |
| [`observability/`](./observability) | Grafana LGTM stack on EKS — split into `platform/` and `workloads/` |

## Getting Started

State lives in S3, so the bucket has to exist before anything else can
initialise. It is created once per AWS account:

```bash
make bootstrap
```

The observability stack is two Terraform stacks that must be applied and
destroyed in opposite orders. The Makefile handles that:

```bash
make init      # initialise both stacks against the state bucket
make plan
make apply     # platform, then workloads
make destroy   # workloads, then platform
```

Run `make help` for the full list of targets. See
[`observability/README.md`](./observability/README.md) for why the ordering
matters.

`notifications/` is independent and still a standalone configuration:

```bash
cd notifications && terraform init && terraform apply
```
