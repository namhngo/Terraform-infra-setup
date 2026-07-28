# Wraps the stacks in this repo so the ordering between them is not something
# anyone has to remember. Apply runs platform before workloads; destroy runs
# workloads before platform, which is the direction that matters — tearing the
# cluster down before the in-cluster load balancer controller has released its
# ALB is what used to deadlock the teardown.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_NAME ?= obs-project
AWS_REGION   ?= us-east-1

BOOTSTRAP := bootstrap
PLATFORM  := observability/platform
WORKLOADS := observability/workloads
STACKS    := $(PLATFORM) $(WORKLOADS)

# Resolved lazily so that targets which do not touch AWS (help, fmt) work
# without credentials.
ACCOUNT_ID    = $(shell aws sts get-caller-identity --query Account --output text)
STATE_BUCKET  = $(PROJECT_NAME)-tfstate-$(ACCOUNT_ID)

# The state bucket name embeds the account ID, so it cannot be written into a
# backend block. It is supplied here instead.
TF_INIT = terraform init -reconfigure -backend-config="bucket=$(STATE_BUCKET)"

.PHONY: help bootstrap init plan apply destroy fmt validate clean output

help:
	@echo "Setup (once per account):"
	@echo "  make bootstrap    Create the S3 bucket that stores remote state"
	@echo ""
	@echo "Normal use:"
	@echo "  make init         Initialise both stacks against the state bucket"
	@echo "  make plan         Plan both stacks"
	@echo "  make apply        Apply platform, then workloads"
	@echo "  make destroy      Destroy workloads, then platform (order matters)"
	@echo "  make output       Show the endpoint and credential-retrieval commands"
	@echo ""
	@echo "Checks:"
	@echo "  make fmt          Rewrite all stacks to canonical format"
	@echo "  make validate     Validate all stacks"
	@echo ""
	@echo "State bucket: $(STATE_BUCKET)"

bootstrap:
	cd $(BOOTSTRAP) && terraform init && terraform apply
	@echo
	@echo "State bucket ready. Run 'make init' next."

init:
	@for stack in $(STACKS); do \
	  echo "==> init $$stack"; \
	  ( cd $$stack && $(TF_INIT) ) || exit 1; \
	done

plan:
	@for stack in $(STACKS); do \
	  echo "==> plan $$stack"; \
	  ( cd $$stack && terraform plan ) || exit 1; \
	done

# Sequential, not parallel: the workloads stack reads the platform stack's
# outputs and looks the cluster up by name, so the cluster has to exist first.
apply:
	@echo "==> apply $(PLATFORM)"
	cd $(PLATFORM) && terraform apply
	@echo "==> apply $(WORKLOADS)"
	cd $(WORKLOADS) && terraform apply
	@$(MAKE) --no-print-directory output

# Reverse order. Destroying workloads first lets the load balancer controller
# tear down its own ALB, target groups and security group rules while it is still
# running, which is the entire reason the stacks are split.
destroy:
	@echo "==> destroy $(WORKLOADS)"
	cd $(WORKLOADS) && terraform destroy
	@echo "==> destroy $(PLATFORM)"
	cd $(PLATFORM) && terraform destroy

output:
	@cd $(WORKLOADS) && terraform output

fmt:
	terraform fmt -recursive

validate:
	@for stack in $(BOOTSTRAP) $(STACKS); do \
	  echo "==> validate $$stack"; \
	  ( cd $$stack && terraform init -backend=false -input=false >/dev/null && terraform validate ) || exit 1; \
	done

clean:
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
