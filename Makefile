# Simple EC2 deployment for python apps.

# Environment setup
-include .env
export

APP_NAME ?= my-data-app
AWS_REGION ?= us-east-1
PORT ?= 8000
ENV ?= dev

# -------------------------
# EC2 CFN + Route53 helpers
# -------------------------

STACK_NAME ?= $(APP_NAME)-$(ENV)
CFN_TEMPLATE ?= infra/ec2-stack.yaml
PARAMS_FILE ?= infra/$(ENV)-params.json

# Optional parameter overrides (space-separated, e.g., GitRef=main InstallRequirements=true)
CFN_EXTRA_PARAMS ?= 

ec2-stack-deploy:
	@test -f "$(PARAMS_FILE)" || (echo "Parameter file $(PARAMS_FILE) not found" && exit 1)
	aws cloudformation deploy \
	  --template-file $(CFN_TEMPLATE) \
	  --stack-name $(STACK_NAME) \
	  --region $(AWS_REGION) \
	  --parameter-overrides $(CFN_EXTRA_PARAMS) \
	  --parameters file://$(PARAMS_FILE)


ec2-stack-delete:
	aws cloudformation delete-stack --stack-name $(STACK_NAME) --region $(AWS_REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_NAME) --region $(AWS_REGION)

ec2-stack-outputs:
	aws cloudformation describe-stacks --stack-name $(STACK_NAME) --region $(AWS_REGION) \
	  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table

# DNS helpers (Route53 A record for the instance public IP)
HOSTED_ZONE_ID ?=
RECORD_NAME ?= $(DOMAIN_NAME)
RECORD_TTL ?= 60

_PUBLIC_IP        = $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --region $(AWS_REGION) --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text 2>/dev/null)

dns-upsert:
	@test -n "$(HOSTED_ZONE_ID)" || (echo "HOSTED_ZONE_ID is required" && exit 1)
	@test -n "$(RECORD_NAME)" || (echo "RECORD_NAME is required" && exit 1)
	@test -n "$(_PUBLIC_IP)" || (echo "Could not resolve PublicIp from stack $(STACK_NAME)" && exit 1)
	@echo "Updating A $(RECORD_NAME) -> $(_PUBLIC_IP)"
	@echo '{"Comment":"Upsert A record for $(RECORD_NAME)","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$(RECORD_NAME)","Type":"A","TTL":$(RECORD_TTL),"ResourceRecords":[{"Value":"$(_PUBLIC_IP)"}]}}]}' > /tmp/r53-change.json
	aws route53 change-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --change-batch file:///tmp/r53-change.json
	@rm -f /tmp/r53-change.json

dns-delete:
	@test -n "$(HOSTED_ZONE_ID)" || (echo "HOSTED_ZONE_ID is required" && exit 1)
	@echo "Deleting A $(RECORD_NAME)"
	@CURR_IP=$$(aws route53 list-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --query "ResourceRecordSets[?Name=='$(RECORD_NAME).' && Type=='A'].ResourceRecords[0].Value" --output text 2>/dev/null); \
	if [ -n "$$CURR_IP" ] && [ "$$CURR_IP" != "None" ]; then \
	  echo "{\"Comment\":\"Delete A record for $(RECORD_NAME)\",\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"$(RECORD_NAME)\",\"Type\":\"A\",\"TTL\":$(RECORD_TTL),\"ResourceRecords\":[{\"Value\":\"$$CURR_IP\"}]}}]}" > /tmp/r53-delete.json; \
	  aws route53 change-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --change-batch file:///tmp/r53-delete.json; \
	  rm -f /tmp/r53-delete.json; \
	else \
	  echo "Record not found or empty; nothing to delete"; \
	fi

# -------------------------
# CloudFront TLS stack
# -------------------------

CF_STACK_NAME ?= $(APP_NAME)-cf
CF_TEMPLATE ?= infra/cloudfront-stack.yaml
DOMAIN_NAME ?= my-app.example.com
HOSTED_ZONE_ID ?=
ORIGIN_DOMAIN ?=
ORIGIN_PORT ?= 8000
PRICE_CLASS ?= PriceClass_100

cf-stack-deploy:
	@test -n "$(HOSTED_ZONE_ID)" || (echo "HOSTED_ZONE_ID is required" && exit 1)
	@test -n "$(ORIGIN_DOMAIN)" || (echo "ORIGIN_DOMAIN is required (e.g., EC2 public DNS or ALB DNS)" && exit 1)
	aws cloudformation deploy \
	  --template-file $(CF_TEMPLATE) \
	  --stack-name $(CF_STACK_NAME) \
	  --region us-east-1 \
	  --parameter-overrides DomainName=$(DOMAIN_NAME) HostedZoneId=$(HOSTED_ZONE_ID) OriginDomainName=$(ORIGIN_DOMAIN) OriginPort=$(ORIGIN_PORT) PriceClass=$(PRICE_CLASS)

cf-stack-outputs:
	aws cloudformation describe-stacks --stack-name $(CF_STACK_NAME) --region us-east-1 \
	  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table

cf-stack-delete:
	aws cloudformation delete-stack --stack-name $(CF_STACK_NAME) --region us-east-1
	aws cloudformation wait stack-delete-complete --stack-name $(CF_STACK_NAME) --region us-east-1

# Tag and push a release (requires git remote auth)
.PHONY: release-tag
VERSION ?= v0.1.0
release-tag:
	git tag -a $(VERSION) -m "$(VERSION)"
	git push origin $(VERSION)

# Start a Session Manager shell to the EC2 instance created by the stack
ssm-session:
	@IID=$$(aws cloudformation describe-stacks --stack-name $(STACK_NAME) --region $(AWS_REGION) --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text); \
	if [ -z "$$IID" ] || [ "$$IID" = "None" ]; then echo "InstanceId not found. Did you deploy the EC2 stack?" && exit 1; fi; \
	echo "Starting SSM session to $$IID in $(AWS_REGION)..."; \
	aws ssm start-session --target $$IID --region $(AWS_REGION)
