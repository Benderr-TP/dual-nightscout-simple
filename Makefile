# Simple container build/push and AWS App Runner helper

APP_NAME ?= dual-nightscout-simple
IMAGE_TAG ?= latest
AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID ?= 000000000000
ECR_REPO ?= $(APP_NAME)
ECR_URI := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO)
PORT ?= 8000


.PHONY: docker-build docker-run docker-tag docker-push ecr-login ecr-create apprunner-up apprunner-url \
	ec2-stack-deploy ec2-stack-delete ec2-stack-outputs dns-upsert dns-delete \
	cf-stack-deploy cf-stack-delete cf-stack-outputs ssm-session

docker-build:
	DOCKER_BUILDKIT=1 docker build -t $(APP_NAME):$(IMAGE_TAG) .

docker-run:
	docker run --rm -it -p $(PORT):$(PORT) -e PORT=$(PORT) -e HOST=0.0.0.0 $(APP_NAME):$(IMAGE_TAG)

ecr-login:
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

ecr-create:
	aws ecr describe-repositories --repository-names $(ECR_REPO) --region $(AWS_REGION) >/dev/null 2>&1 || \
		aws ecr create-repository --repository-name $(ECR_REPO) --region $(AWS_REGION) >/dev/null

docker-tag:
	docker tag $(APP_NAME):$(IMAGE_TAG) $(ECR_URI):$(IMAGE_TAG)

docker-push: ecr-login ecr-create docker-tag
	docker push $(ECR_URI):$(IMAGE_TAG)

# Create an App Runner service from the ECR image.
# Requires: aws cli, permissions to create service/roles.
apprunner-up:
	aws apprunner create-service \
	  --service-name $(APP_NAME) \
	  --region $(AWS_REGION) \
	  --source-configuration ImageRepository={ImageIdentifier=$(ECR_URI):$(IMAGE_TAG),ImageRepositoryType=ECR,ImageConfiguration={Port=$(PORT),RuntimeEnvironmentVariables=[{Name=PORT,Value=$(PORT)},{Name=HOST,Value=0.0.0.0}]}} \
	  --instance-configuration Cpu=0.5vCPU,Memory=1GB \
	  --query 'Service.ServiceUrl' --output text

apprunner-url:
	aws apprunner list-services --region $(AWS_REGION) \
	  --query 'ServiceSummaryList[?ServiceName==`$(APP_NAME)`].ServiceUrl' --output text

# -------------------------
# EC2 CFN + Route53 helpers
# -------------------------

STACK_NAME ?= devops-testapp
CFN_TEMPLATE ?= infra/ec2-stack.yaml

# Required: export these or pass on the make command line
VPC_ID ?=
SUBNET_ID ?=
KEY_NAME ?=

# Optional parameter overrides (space-separated, e.g., GitRef=main InstallRequirements=true)
CFN_EXTRA_PARAMS ?=

# Compose CloudFormation parameters
CFN_PARAMS := VpcId=$(VPC_ID) SubnetId=$(SUBNET_ID) KeyName=$(KEY_NAME) $(CFN_EXTRA_PARAMS)

ec2-stack-deploy:
	@test -n "$(VPC_ID)" || (echo "VPC_ID is required" && exit 1)
	@test -n "$(SUBNET_ID)" || (echo "SUBNET_ID is required" && exit 1)
	@test -n "$(KEY_NAME)" || (echo "KEY_NAME is required" && exit 1)
	aws cloudformation deploy \
	  --template-file $(CFN_TEMPLATE) \
	  --stack-name $(STACK_NAME) \
	  --region $(AWS_REGION) \
	  --parameter-overrides $(CFN_PARAMS)

ec2-stack-delete:
	aws cloudformation delete-stack --stack-name $(STACK_NAME) --region $(AWS_REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK_NAME) --region $(AWS_REGION)

ec2-stack-outputs:
	aws cloudformation describe-stacks --stack-name $(STACK_NAME) --region $(AWS_REGION) \
	  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table

# DNS helpers (Route53 A record for the instance public IP)
HOSTED_ZONE_ID ?=
RECORD_NAME ?= testapp-devops.tidepool.org
RECORD_TTL ?= 60

_PUBLIC_IP        = $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --region $(AWS_REGION) --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text 2>/dev/null)

dns-upsert:
	@test -n "$(HOSTED_ZONE_ID)" || (echo "HOSTED_ZONE_ID is required" && exit 1)
	@test -n "$(RECORD_NAME)" || (echo "RECORD_NAME is required" && exit 1)
	@test -n "$(_PUBLIC_IP)" || (echo "Could not resolve PublicIp from stack $(STACK_NAME)" && exit 1)
	@echo "Updating A $(RECORD_NAME) -> $(_PUBLIC_IP)"
	@cat > /tmp/r53-change.json <<EOF
{
  "Comment": "Upsert A record for $(RECORD_NAME)",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$(RECORD_NAME)",
        "Type": "A",
        "TTL": $(RECORD_TTL),
        "ResourceRecords": [{"Value": "$(_PUBLIC_IP)"}]
      }
    }
  ]
}
EOF
	aws route53 change-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --change-batch file:///tmp/r53-change.json
	@rm -f /tmp/r53-change.json

dns-delete:
	@test -n "$(HOSTED_ZONE_ID)" || (echo "HOSTED_ZONE_ID is required" && exit 1)
	@echo "Deleting A $(RECORD_NAME)"
	@cat > /tmp/r53-delete.json <<EOF
{
  "Comment": "Delete A record for $(RECORD_NAME)",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "$(RECORD_NAME)",
        "Type": "A",
        "TTL": $(RECORD_TTL),
        "ResourceRecords": [{"Value": "0.0.0.0"}]
      }
    }
  ]
}
EOF
	# We need the current IP to delete properly; fetch and patch the JSON
	@CURR_IP=$$(aws route53 list-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --query "ResourceRecordSets[?Name=='$(RECORD_NAME).' && Type=='A'].ResourceRecords[0].Value" --output text 2>/dev/null); \
	if [ -n "$$CURR_IP" ] && [ "$$CURR_IP" != "None" ]; then \
	  sed -i.bak "s/0.0.0.0/$$CURR_IP/" /tmp/r53-delete.json; \
	  aws route53 change-resource-record-sets --hosted-zone-id $(HOSTED_ZONE_ID) --change-batch file:///tmp/r53-delete.json; \
	else \
	  echo "Record not found or empty; nothing to delete"; \
	fi
	@rm -f /tmp/r53-delete.json /tmp/r53-delete.json.bak

# -------------------------
# CloudFront TLS stack
# -------------------------

CF_STACK_NAME ?= $(APP_NAME)-cf
CF_TEMPLATE ?= infra/cloudfront-stack.yaml
DOMAIN_NAME ?= testapp-devops.tidepool.org
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
