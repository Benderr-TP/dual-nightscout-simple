# GitHub Repository Configuration Template

Copy these settings to your GitHub repository for automated deployment.

## Required GitHub Secrets

Navigate to your repository → Settings → Secrets and Variables → Actions

### Secrets (encrypted values)
- `AWS_ROLE_TO_ASSUME`: ARN of IAM role for GitHub Actions OIDC authentication
  - Example: `arn:aws:iam::123456789012:role/GHActionsDeployRole`

## Required GitHub Variables

Navigate to your repository → Settings → Secrets and Variables → Actions → Variables tab

### Infrastructure Variables
- `AWS_REGION`: AWS region for deployment (e.g., `us-east-1`)
- `VPC_ID`: VPC ID to deploy into (e.g., `vpc-12345678`)
- `SUBNET_ID`: Public subnet ID (e.g., `subnet-87654321`)
- `KEY_NAME`: EC2 key pair name for SSH access (e.g., `my-keypair`)
- `HOSTED_ZONE_ID`: Route53 hosted zone ID (e.g., `Z1234567890ABC`)

### Application Variables
- `APP_NAME`: Application name for stack naming (e.g., `my-data-app`)
- `DOMAIN_NAME`: Public domain for your app (e.g., `my-app.example.com`)
- `GIT_REPO_URL`: Your git repository URL (e.g., `https://github.com/your-org/your-repo.git`)

### Optional Variables
- `EC2_STACK_NAME`: Override EC2 stack name (defaults to `{APP_NAME}-ec2`)
- `CF_STACK_NAME`: Override CloudFront stack name (defaults to `{APP_NAME}-cf`)
- `INSTANCE_TYPE`: EC2 instance type (defaults to `t3.micro`)
- `SSH_CIDR`: CIDR for SSH access (defaults to `0.0.0.0/0` - restrict for security)
- `APP_PORT`: Application port (defaults to `8000`)
- `GIT_REF`: Git branch/tag to deploy (defaults to `main`)
- `INSTALL_REQUIREMENTS`: Install Python requirements (defaults to `true`)
- `USE_VENV`: Use Python virtual environment (defaults to `false`)
- `PIP_PACKAGES`: Additional pip packages to install (space-separated)

## AWS OIDC Setup Required

Before using GitHub Actions, you must set up AWS OIDC authentication:

1. Create OIDC provider in AWS (if not exists):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
     --client-id-list sts.amazonaws.com
   ```

2. Create IAM role with trust policy (replace ORG/REPO):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
           }
         }
       }
     ]
   }
   ```

3. Attach permissions policy to the role:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "cloudformation:*",
           "ec2:*",
           "route53:*",
           "acm:*",
           "cloudfront:*",
           "iam:CreateRole",
           "iam:AttachRolePolicy",
           "iam:CreateInstanceProfile",
           "iam:AddRoleToInstanceProfile",
           "iam:PassRole",
           "iam:GetRole",
           "iam:GetInstanceProfile",
           "iam:ListInstanceProfilesForRole",
           "iam:TagRole",
           "iam:TagInstanceProfile"
         ],
         "Resource": "*"
       }
     ]
   }
   ```