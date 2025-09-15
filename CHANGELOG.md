# Changelog

## v0.1.0 — Initial release

Highlights
- Local server: `tools/serve.py` with `/healthz` endpoint.
- Lambda path: `lambda_app/handler.py`, plus `tools/package_lambda.sh` and `tools/deploy_lambda.sh`.
- EC2 stack: `infra/ec2-stack.yaml` (Launch Template + instance) with:
  - Git pull on boot, hostname config, optional venv + `requirements.txt` install.
  - 101 GiB secondary volume (configurable) auto-format/mount.
  - Sumo Logic optional collector + web log collection (`/var/log/webapp/app.log`).
  - IMDSv2 usage, SSM Session Manager role/profile.
- CloudFront TLS stack: `infra/cloudfront-stack.yaml` (ACM cert, distribution, Route53 A-alias).
- Makefile shortcuts: build/push image, App Runner, EC2/Route53 helpers, CloudFront deploy, SSM session.
- Documentation: `AGENTS.md` with concise local, serverless, EC2, and CloudFront steps.

Notes
- Default security groups allow app port from `0.0.0.0/0`; restrict via parameters or front with CloudFront.
- Lambda Function URL deploy script is public by default; switch to IAM/API Gateway for private endpoints.
