# Single root module — no stack split needed (see README's "How to read this
# diagram" for why: ECS has no equivalent to the AWS Load Balancer Controller
# owning resources Terraform can't see). One init, one apply, one destroy.
#
# Self-contained: every path below is relative to this directory, so this
# project can be lifted into its own repository without changes.

SHELL := /bin/bash
.DEFAULT_GOAL := help

AWS_REGION ?= us-east-1
PROJECT    ?= obs-project

# The 5 services built and pushed by `make build-images`. Format:
# "component=upstream-image:tag". Tags must match the image_tags local in
# ecs.tf. MUTABLE ECR tags (ecr.tf) mean re-running this after editing a
# config file under configs/ is the normal iteration loop — no version bump
# required.
SERVICES := alloy=grafana/alloy:v1.17.0 \
            loki=grafana/loki:3.7.2 \
            tempo=grafana/tempo:2.10.7 \
            prometheus=prom/prometheus:v3.12.0 \
            grafana=grafana/grafana:13.0.2

ifeq ($(AUTO_APPROVE),1)
  APPROVE := -auto-approve -input=false
endif

.PHONY: help init plan apply destroy fmt validate lint build-images redeploy output clean

help:
	@echo "Usage:"
	@echo "  make init           terraform init"
	@echo "  make plan           terraform plan"
	@echo "  make apply          terraform apply (creates the AWS resources;"
	@echo "                      services will fail to start until images exist)"
	@echo "  make build-images   Build all 5 images (config baked in) and push to ECR"
	@echo "  make redeploy       Force new ECS deployments so services pick up images"
	@echo "  make destroy        terraform destroy — one pass, no ordering needed"
	@echo "  make output         Show the public/internal endpoints and credential commands"
	@echo ""
	@echo "First-time build:"
	@echo "  make apply && make build-images && make redeploy"
	@echo ""
	@echo "Checks:"
	@echo "  make fmt            Rewrite to canonical format"
	@echo "  make validate       terraform validate"
	@echo "  make lint           tflint"
	@echo ""
	@echo "Add AUTO_APPROVE=1 to skip confirmation prompts."

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply $(APPROVE)
	@$(MAKE) --no-print-directory output

destroy:
	terraform destroy $(APPROVE)

# Builds with --platform linux/amd64 explicitly: ECS Fargate tasks run x86_64,
# and `docker buildx build --platform` reliably cross-builds for a target
# platform regardless of the host's own architecture (unlike a bare
# `docker pull --platform`, which on Apple Silicon can silently return the
# host's cached arm64 image instead — the bug observability-eks hit).
build-images:
	@ACCOUNT=$$(aws sts get-caller-identity --query Account --output text); \
	REGISTRY=$$ACCOUNT.dkr.ecr.$(AWS_REGION).amazonaws.com; \
	echo "==> logging in to $$REGISTRY"; \
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $$REGISTRY >/dev/null; \
	for entry in $(SERVICES); do \
	  comp=$${entry%%=*}; src=$${entry#*=}; tag=$${src##*:}; \
	  dest=$$REGISTRY/$(PROJECT)-$$comp:$$tag; \
	  echo "==> building $$comp ($$dest)"; \
	  docker buildx build --platform linux/amd64 \
	    -f docker/$$comp/Dockerfile -t $$dest --push . || exit 1; \
	done

# force-new-deployment makes each service re-pull its (possibly rebuilt, same
# tag) image immediately, rather than waiting for the next natural task
# replacement.
redeploy:
	@CLUSTER=$(PROJECT)-cluster; \
	for svc in alloy loki tempo prometheus grafana; do \
	  echo "==> redeploying $(PROJECT)-$$svc"; \
	  aws ecs update-service --region $(AWS_REGION) --cluster $$CLUSTER \
	    --service $(PROJECT)-$$svc --force-new-deployment >/dev/null || exit 1; \
	done

output:
	@terraform output

fmt:
	terraform fmt -recursive

validate:
	terraform init -backend=false -input=false >/dev/null
	terraform validate

lint:
	tflint

clean:
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
