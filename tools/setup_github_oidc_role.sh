#!/usr/bin/env bash
set -euo pipefail

# Create or update an IAM role trusted by GitHub OIDC for this repo.
# Usage:
#   bash tools/setup_github_oidc_role.sh --org ORG --repo REPO --role-name ROLE \
#     [--branch refs/heads/main] [--create-provider]
#
# Outputs the role ARN on success.

ORG=""
REPO=""
ROLE_NAME="GHActionsDeployRole"
BRANCH="refs/heads/main"
INCLUDE_RELEASE=false
INCLUDE_HOTFIX=false
INCLUDE_TAGS=false
CREATE_PROVIDER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --role-name) ROLE_NAME="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --include-release) INCLUDE_RELEASE=true; shift 1 ;;
    --include-hotfix) INCLUDE_HOTFIX=true; shift 1 ;;
    --include-tags) INCLUDE_TAGS=true; shift 1 ;;
    --create-provider) CREATE_PROVIDER=true; shift 1 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ORG" || -z "$REPO" ]]; then
  echo "--org and --repo are required" >&2
  exit 2
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  if [[ "$CREATE_PROVIDER" == true ]]; then
    echo "[setup] Creating OIDC provider..."
    aws iam create-open-id-connect-provider \
      --url https://token.actions.githubusercontent.com \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
  else
    echo "[setup] OIDC provider not found. Create it first or re-run with --create-provider" >&2
    exit 1
  fi
fi

SUBJECTS=("repo:${ORG}/${REPO}:ref:${BRANCH}")
if [[ "$INCLUDE_RELEASE" == true ]]; then SUBJECTS+=("repo:${ORG}/${REPO}:ref:refs/heads/release/*"); fi
if [[ "$INCLUDE_HOTFIX" == true ]]; then SUBJECTS+=("repo:${ORG}/${REPO}:ref:refs/heads/hotfix/*"); fi
if [[ "$INCLUDE_TAGS" == true ]]; then SUBJECTS+=("repo:${ORG}/${REPO}:ref:refs/tags/v*"); fi

SUBJ_JSON=$(printf '"%s",' "${SUBJECTS[@]}")
SUBJ_JSON="${SUBJ_JSON%,}"

TRUST=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "${PROVIDER_ARN}"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
        "StringLike": {"token.actions.githubusercontent.com:sub": [${SUBJ_JSON}]}
      }
    }
  ]
}
JSON
)

set +e
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
set -e

if [[ -z "${ROLE_ARN:-}" || "$ROLE_ARN" == "None" ]]; then
  echo "[setup] Creating role $ROLE_NAME ..."
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST" >/dev/null
else
  echo "[setup] Updating trust policy for $ROLE_NAME ..."
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST" >/dev/null
fi

POLICY_NAME="GHActionsDeployPolicy"
POLICY_DOC=$(cat <<'JSON'
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
      "iam:AddRoleToInstanceProfile", "iam:PassRole", "iam:GetRole", "iam:GetInstanceProfile", "iam:PutRolePolicy"
    ], "Resource": "*" }
  ]
}
JSON
)

echo "[setup] Attaching inline policy $POLICY_NAME ..."
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOC" >/dev/null

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "[setup] Done. Role ARN: $ROLE_ARN"
