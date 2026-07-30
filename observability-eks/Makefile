# Wraps this project's stacks so the ordering between them is not something
# anyone has to remember. Apply runs platform before workloads; destroy runs
# workloads before platform, which is the direction that matters — tearing the
# cluster down before the in-cluster load balancer controller has released its
# ALB is what used to deadlock the teardown.
#
# Self-contained: every path below is relative to this directory, so this project
# can be lifted into its own repository without changes.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PLATFORM  := platform
WORKLOADS := workloads
STACKS    := $(PLATFORM) $(WORKLOADS)

# Used by push-images. PROJECT must match var.project_name in the platform stack.
PROJECT    ?= obs-project
AWS_REGION ?= us-east-1

# The images mirrored into ECR, as "ecr-component=upstream-image:tag". The tags
# must match the image_tags local in workloads/workloads.tf.
MIRROR_IMAGES := alloy=grafana/alloy:v1.17.0 \
                 prometheus=prom/prometheus:v3.12.0 \
                 grafana=grafana/grafana:13.0.2

# AUTO_APPROVE=1 skips the interactive confirmation, for CI or an unattended
# rebuild. Off by default so `make destroy` still asks first.
ifeq ($(AUTO_APPROVE),1)
  APPROVE := -auto-approve -input=false
endif

.PHONY: help init plan apply apply-platform apply-workloads push-images destroy fmt validate lint clean output

help:
	@echo "Usage:"
	@echo "  make init             Initialise both stacks"
	@echo "  make plan             Plan both stacks"
	@echo "  make apply            Apply platform, then workloads"
	@echo "  make destroy          Destroy workloads, then platform (order matters)"
	@echo "  make output           Show the endpoint and credential-retrieval commands"
	@echo ""
	@echo "First-time setup (images must exist in ECR before workloads run):"
	@echo "  make apply-platform   Apply the platform stack (creates ECR repos)"
	@echo "  make push-images      Mirror upstream images from Docker Hub into ECR"
	@echo "  make apply-workloads  Apply the workloads stack (pods pull from ECR)"
	@echo ""
	@echo "Checks:"
	@echo "  make fmt              Rewrite both stacks to canonical format"
	@echo "  make validate         Validate both stacks"
	@echo "  make lint             Run tflint over both stacks"
	@echo ""
	@echo "Add AUTO_APPROVE=1 to skip confirmation prompts."

init:
	@for stack in $(STACKS); do \
	  echo "==> init $$stack"; \
	  ( cd $$stack && terraform init ) || exit 1; \
	done

# Only platform can be planned from scratch. The workloads plan reads platform's
# state file and looks the cluster up by name, so it needs platform applied first.
plan:
	@echo "==> plan $(PLATFORM)"
	cd $(PLATFORM) && terraform plan

# Sequential, not parallel: workloads reads platform's outputs from its state
# file and looks the cluster up by name, so the cluster has to exist first.
#
# On a FIRST-time build the ECR repos start empty, so the images must be pushed
# before workloads runs or the Alloy/Prometheus/Grafana pods ImagePullBackOff.
# Use the three-step sequence instead of `make apply`:
#   make apply-platform && make push-images && make apply-workloads
# `make apply` is for subsequent runs, once the images are already in ECR.
apply:
	@echo "==> apply $(PLATFORM)"
	cd $(PLATFORM) && terraform apply $(APPROVE)
	@echo "==> apply $(WORKLOADS)"
	cd $(WORKLOADS) && terraform apply $(APPROVE)
	@$(MAKE) --no-print-directory output

apply-platform:
	cd $(PLATFORM) && terraform apply $(APPROVE)

apply-workloads:
	cd $(WORKLOADS) && terraform apply $(APPROVE)
	@$(MAKE) --no-print-directory output

# One-time bootstrap: mirror the upstream images into the private ECR repos the
# platform stack created. Run after `make apply-platform`, before workloads.
#
# --platform linux/amd64 is required: the worker nodes are x86_64, so pulling on
# an Apple-Silicon (arm64) laptop without it would push arm64 images the nodes
# can't run. Tags are IMMUTABLE, so re-pushing an existing tag errors — that just
# means it's already mirrored.
#
# Uses skopeo instead of docker for reliable cross-platform copies (docker on
# macOS sometimes ignores --platform and pushes the wrong arch).
push-images:
	@ACCOUNT=$$(aws sts get-caller-identity --query Account --output text); \
	REGISTRY=$$ACCOUNT.dkr.ecr.$(AWS_REGION).amazonaws.com; \
	echo "==> logging in to $$REGISTRY"; \
	aws ecr get-login-password --region $(AWS_REGION) | skopeo login --username AWS --password-stdin $$REGISTRY >/dev/null 2>&1; \
	for entry in $(MIRROR_IMAGES); do \
	  comp=$${entry%%=*}; src=$${entry#*=}; tag=$${src##*:}; \
	  dest=docker://$$REGISTRY/$(PROJECT)-$$comp:$$tag; \
	  echo "==> $$src -> $$dest (linux/amd64)"; \
	  skopeo copy --override-os linux --override-arch amd64 docker://$$src $$dest || exit 1; \
	done

# Reverse order. Destroying workloads first lets the load balancer controller
# tear down its own ALB, target groups and security group rules while it is still
# running, which is the entire reason the stacks are split.
destroy:
	@echo "==> destroy $(WORKLOADS)"
	cd $(WORKLOADS) && terraform destroy $(APPROVE)
	@echo "==> destroy $(PLATFORM)"
	cd $(PLATFORM) && terraform destroy $(APPROVE)

output:
	@cd $(WORKLOADS) && terraform output

fmt:
	terraform fmt -recursive

validate:
	@for stack in $(STACKS); do \
	  echo "==> validate $$stack"; \
	  ( cd $$stack && terraform init -backend=false -input=false >/dev/null && terraform validate ) || exit 1; \
	done

lint:
	@for stack in $(STACKS); do \
	  echo "==> tflint $$stack"; \
	  ( cd $$stack && tflint ) || exit 1; \
	done

clean:
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
