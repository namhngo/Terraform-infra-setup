SHELL := /bin/bash
.DEFAULT_GOAL := help

SITE_DIR           ?= site
INVALIDATION_PATHS ?= /index.html

ifeq ($(AUTO_APPROVE),1)
  APPROVE := -auto-approve -input=false
endif

.PHONY: help init plan apply destroy output deploy-content invalidate empty-bucket fmt validate lint clean

help:
	@echo "Usage:"
	@echo "  make init                         terraform init"
	@echo "  make plan                         terraform plan"
	@echo "  make apply                        create or update AWS infrastructure"
	@echo "  make deploy-content SITE_DIR=site sync content and invalidate index.html"
	@echo "  make invalidate INVALIDATION_PATHS='/*' invalidate selected paths"
	@echo "  make output                       show Terraform outputs"
	@echo "  make empty-bucket CONFIRM=1       delete all current and versioned objects"
	@echo "  make destroy                      destroy infrastructure"
	@echo ""
	@echo "Checks:"
	@echo "  make fmt                          rewrite Terraform to canonical format"
	@echo "  make validate                     terraform validate"
	@echo "  make lint                         tflint"
	@echo ""
	@echo "First-time workflow:"
	@echo "  make apply && make deploy-content"
	@echo ""
	@echo "Set AUTO_APPROVE=1 to skip Terraform confirmation prompts."

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply $(APPROVE)
	@$(MAKE) --no-print-directory output

destroy:
	terraform destroy $(APPROVE)

output:
	terraform output

deploy-content:
	@test -f "$(SITE_DIR)/index.html" || { echo "Missing $(SITE_DIR)/index.html" >&2; exit 1; }
	@set -euo pipefail; \
	  BUCKET=$$(terraform output -raw bucket_name); \
	  REGION=$$(terraform output -raw aws_region); \
	  echo "==> syncing assets to s3://$$BUCKET"; \
	  aws s3 sync "$(SITE_DIR)" "s3://$$BUCKET" \
	    --region "$$REGION" \
	    --delete \
	    --exclude "index.html" \
	    --cache-control "public,max-age=31536000,immutable"; \
	  echo "==> uploading index.html with no-cache headers"; \
	  aws s3 cp "$(SITE_DIR)/index.html" "s3://$$BUCKET/index.html" \
	    --region "$$REGION" \
	    --cache-control "no-cache,no-store,must-revalidate" \
	    --content-type "text/html; charset=utf-8"; \
	  $(MAKE) --no-print-directory invalidate INVALIDATION_PATHS=/index.html

invalidate:
	@set -euo pipefail; \
	  DISTRIBUTION_ID=$$(terraform output -raw cloudfront_distribution_id); \
	  read -r -a PATHS <<< "$(INVALIDATION_PATHS)"; \
	  echo "==> invalidating $$DISTRIBUTION_ID: $${PATHS[*]}"; \
	  aws cloudfront create-invalidation \
	    --distribution-id "$$DISTRIBUTION_ID" \
	    --paths "$${PATHS[@]}"

# Versioning means `aws s3 rm --recursive` is not enough: old object versions
# and delete markers would keep the bucket non-empty during destroy.
empty-bucket:
	@if [ "$(CONFIRM)" != "1" ]; then \
	  echo "Refusing to empty the bucket. Re-run with CONFIRM=1." >&2; \
	  exit 1; \
	fi
	@set -euo pipefail; \
	  BUCKET=$$(terraform output -raw bucket_name); \
	  REGION=$$(terraform output -raw aws_region); \
	  command -v jq >/dev/null || { echo "empty-bucket requires jq" >&2; exit 1; }; \
	  while true; do \
	    OBJECTS=$$(aws s3api list-object-versions --bucket "$$BUCKET" --region "$$REGION" --output json | \
	      jq -c '{Objects: ([(.Versions // []), (.DeleteMarkers // [])] | add | map({Key: .Key, VersionId: .VersionId})), Quiet: true}'); \
	    COUNT=$$(printf '%s' "$$OBJECTS" | jq '.Objects | length'); \
	    [ "$$COUNT" -eq 0 ] && break; \
	    echo "==> deleting $$COUNT object versions from $$BUCKET"; \
	    aws s3api delete-objects --bucket "$$BUCKET" --region "$$REGION" --delete "$$OBJECTS" >/dev/null; \
	  done

fmt:
	terraform fmt -recursive

validate:
	terraform init -backend=false -input=false >/dev/null
	terraform validate

lint:
	tflint

clean:
	rm -rf .terraform
