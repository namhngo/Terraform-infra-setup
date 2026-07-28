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

# AUTO_APPROVE=1 skips the interactive confirmation, for CI or an unattended
# rebuild. Off by default so `make destroy` still asks first.
ifeq ($(AUTO_APPROVE),1)
  APPROVE := -auto-approve -input=false
endif

.PHONY: help init plan apply destroy fmt validate lint clean output

help:
	@echo "Usage:"
	@echo "  make init         Initialise both stacks"
	@echo "  make plan         Plan both stacks"
	@echo "  make apply        Apply platform, then workloads"
	@echo "  make destroy      Destroy workloads, then platform (order matters)"
	@echo "  make output       Show the endpoint and credential-retrieval commands"
	@echo ""
	@echo "Checks:"
	@echo "  make fmt          Rewrite both stacks to canonical format"
	@echo "  make validate     Validate both stacks"
	@echo "  make lint         Run tflint over both stacks"
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
apply:
	@echo "==> apply $(PLATFORM)"
	cd $(PLATFORM) && terraform apply $(APPROVE)
	@echo "==> apply $(WORKLOADS)"
	cd $(WORKLOADS) && terraform apply $(APPROVE)
	@$(MAKE) --no-print-directory output

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
