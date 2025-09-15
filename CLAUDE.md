# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a template for deploying data science web applications on AWS infrastructure. It provides a complete stack including EC2 instances, CloudFront distributions with TLS support, and automated CI/CD via GitHub Actions with AWS OIDC authentication. The template is designed to be easily customizable for various data science use cases.

## Build and Deployment Commands

### Local Development
```bash
# Run the static web server locally (default port 8000)
python3 tools/serve.py

# Run with custom port/host
python3 tools/serve.py --port 3000 --host localhost
```

### Infrastructure Deployment (AWS)
```bash
# Deploy EC2 stack
make ec2-stack-deploy ENV=dev

# Deploy CloudFront TLS stack (requires ORIGIN_DOMAIN from EC2 stack)
make cf-stack-deploy ORIGIN_DOMAIN=<ec2-public-dns>

# View stack outputs
make ec2-stack-outputs
make cf-stack-outputs

# Delete stacks
make ec2-stack-delete
make cf-stack-delete

# SSM into EC2 instance
make ssm-session STACK_NAME=my-data-app-ec2 AWS_REGION=us-east-1
```

### DNS Management
```bash
# Update Route53 A record with EC2 public IP
make dns-upsert HOSTED_ZONE_ID=<zone-id> RECORD_NAME=my-app.example.com

# Delete DNS record
make dns-delete HOSTED_ZONE_ID=<zone-id> RECORD_NAME=my-app.example.com
```

### Release Management
```bash
# Create and push a release tag
make release-tag VERSION=v0.1.0
```

## Architecture

- **EC2 Stack** (`infra/ec2-stack.yaml`): Deploys an EC2 instance with:
  - Launch template with user data that clones the repo and runs `tools/serve.py`
  - Security groups for SSH and app port access
  - SSM role for Session Manager access
  - Optional secondary data volume
  - Automatic git repository cloning and Python setup

- **CloudFront Stack** (`infra/cloudfront-stack.yaml`): Creates a CloudFront distribution with:
  - ACM certificate for TLS
  - Route53 alias record
  - Origin pointing to EC2 instance
  - Must be deployed in us-east-1 region

- **GitHub Actions** (`.github/workflows/deploy.yml`):
  - Uses OIDC authentication (no long-lived AWS keys)
  - Deploys EC2 stack first, extracts public DNS
  - Then deploys CloudFront stack using EC2 as origin
  - Triggered on pushes to main or manual dispatch

- **Web Application**: Template landing page (`index.html`) that can be replaced with any data science application (Streamlit, Dash, Flask, etc.)

## Key Parameters and Environment Variables

Required GitHub repository configuration:
- Secret: `AWS_ROLE_TO_ASSUME` - IAM role ARN for OIDC
- Variables: `AWS_REGION`, `VPC_ID`, `SUBNET_ID`, `KEY_NAME`, `HOSTED_ZONE_ID`, `DOMAIN_NAME`

Stack parameters configured in `infra/dev-params.json` for local deployments.