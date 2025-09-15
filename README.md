# Dual Nightscout Simple — CI Setup

This repo ships an end‑to‑end deploy via GitHub Actions using AWS OIDC (no long‑lived AWS keys). Below is a minimal, copy‑pasteable setup to enable the workflow in `.github/workflows/deploy.yml`.

## 1) Create (or reuse) the GitHub OIDC provider
Most AWS accounts already have this. If not:

- Console: IAM → Identity providers → Add provider → OpenID Connect
  - Provider URL: `https://token.actions.githubusercontent.com`
  - Audience: `sts.amazonaws.com`
- CLI (equivalent): `aws iam create-open-id-connect-provider ...`

## 2) Create an IAM Role for GitHub Actions (assumed via OIDC)
Trust policy (replace ORG/REPO; supports git-flow branches and tags):

```
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
          "token.actions.githubusercontent.com:sub": [
            "repo:ORG/REPO:ref:refs/heads/main",
            "repo:ORG/REPO:ref:refs/heads/release/*",
            "repo:ORG/REPO:ref:refs/heads/hotfix/*",
            "repo:ORG/REPO:ref:refs/tags/v*"
          ]
        }
      }
    }
  ]
}
```

Permissions policy (minimal for the provided stacks; scope tighter as needed):

```
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": [
      "cloudformation:*",
      "ec2:*",
      "route53:*",
      "acm:*",
      "cloudfront:*",
      "iam:CreateRole", "iam:AttachRolePolicy", "iam:CreateInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:PassRole", "iam:GetRole", "iam:GetInstanceProfile"
    ], "Resource": "*" }
  ]
}
```

- Create the role, attach the trust policy above, then attach the permissions policy (as an inline or managed policy). Copy the role ARN.

CLI automation (script)
- Create/update the OIDC role with git-flow and tags allowed:
```
bash tools/setup_github_oidc_role.sh --org ORG --repo REPO \
  --role-name GHActionsDeployRole --branch refs/heads/main \
  --include-release --include-hotfix --include-tags
```
- If your account has no OIDC provider yet, append `--create-provider` (requires IAM permissions to create the provider).

Releases and git-flow
- Tag a release: `make release-tag VERSION=v0.1.0` (from main or release/* after merging).
- A separate workflow `.github/workflows/release.yml` creates a GitHub Release on tag push `v*` using `CHANGELOG.md`.

## 3) Configure GitHub repository
- Secret: `AWS_ROLE_TO_ASSUME` = the role ARN from step 2.
- Variables: set values used by the workflow
  - `AWS_REGION`, `VPC_ID`, `SUBNET_ID`, `KEY_NAME`, `HOSTED_ZONE_ID`, `DOMAIN_NAME`.

## 4) Run the pipeline
- Push to `main` or trigger the workflow from the Actions tab. It will:
  1) Deploy EC2 stack (`infra/ec2-stack.yaml`).
  2) Read the instance PublicDnsName.
  3) Deploy CloudFront TLS stack (`infra/cloudfront-stack.yaml`) with your domain.

Notes
- You can widen the trust policy to multiple branches by adding patterns like `repo:ORG/REPO:ref:refs/heads/*`.
- For stricter permissions, create a dedicated CloudFormation execution role and limit `cloudformation:*` to use that role via `--role-arn`.
- The EC2 stack creates an SSM profile; you can SSM into the instance if needed.
```
make ssm-session STACK_NAME=devops-testapp AWS_REGION=us-east-1
```
