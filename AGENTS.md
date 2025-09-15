# Repository Guidelines

## Project Structure & Module Organization
- Root serves a static single-page app: `index.html`.
- Place new static assets under `assets/` (e.g., `assets/css/`, `assets/js/`, `assets/img/`).
- Utility scripts live in `tools/` (e.g., `tools/serve.py` to run a local server).
- Keep simple: prefer a single HTML file with minimal JS; only split into modules if complexity grows.

## Build, Test, and Development Commands
- Local dev server (no build step):
  - `python3 tools/serve.py --port 8000` → Serve at http://localhost:8000 (health: /healthz)
  - `python3 -m http.server 8000` → Quick alternative static server.
  - Or `npx serve` (if Node is installed) → Zero-config static server.

## Containerization & AWS Deployment
- Build image: `make docker-build` (tags as `dual-nightscout-simple:latest`).
- Run locally: `make docker-run` (binds `PORT=8000`).
- Push to ECR: set `AWS_ACCOUNT_ID` and `AWS_REGION`, then `make docker-push`.
- App Runner (simplest AWS): after push, `make apprunner-up` → returns service URL.
- Image is generic: override entry with `APP_ENTRY=<path>` to run other Python apps.
- Dependencies: if `requirements.txt` exists at repo root, it is installed at build.

## Serverless Deployment (No Container)
- Code lives in `lambda_app/handler.py` with `lambda_handler(event, context)`.
- Package: `bash tools/package_lambda.sh` → creates `build/lambda.zip` (installs `requirements.txt` if present).
- Deploy: `FUNCTION_NAME=my-app AWS_REGION=us-east-1 bash tools/deploy_lambda.sh`.
- Result: a public Function URL is created; printout contains the URL.
- Schedule runs: create an EventBridge rule (cron) targeting the Lambda to run batch analyses.

## EC2 Launch Template (Git pull on boot)
- Template: `infra/ec2-stack.yaml` creates a Launch Template, SG, and one EC2 instance.
- On boot: sets hostname to `testapp-devops.tidepool.org`, clones this repo, installs optional Python deps, mounts a 101 GiB data volume, and runs `tools/serve.py` as a systemd service on port `8000`.
- Web logs: written to `/var/log/testapp/app.log`. If Sumo is enabled, logs are collected via `/opt/SumoCollector/sources.json`.
- Deploy:
  - `aws cloudformation deploy --template-file infra/ec2-stack.yaml --stack-name devops-testapp \
     --parameter-overrides VpcId=vpc-xxxx SubnetId=subnet-xxxx KeyName=your-key`
- Access: open `http://<public-dns>:8000/` or point DNS `testapp-devops.tidepool.org` to the instance public IP.
 - Debug: Session Manager is enabled. Start a shell with `make ssm-session` or `aws ssm start-session --target <InstanceId>`.

### Useful Parameters (override as needed)
- `GitRef=main` to checkout a branch/tag; `GitRepoURL=<repo>` to change repo.
- `InstallOSUpdates=true|false` to control OS updates at boot.
- `InstallRequirements=true RequirementsPath=requirements.txt` to pip install after clone.
- `AdditionalPipPackages="pandas numpy"` to install extra Python packages.
- `UseVenv=true` to create `/opt/app/venv` and run via that Python.
- Data volume: `DataVolumeSizeGiB=101`, `DataVolumeMountPoint=/mnt/data`, `DataVolumeFsType=xfs`.
- Sumo Logic (optional): `SumoEnabled=true SumoInstallScriptUrl=<url> SumoCollectorToken=<token> SumoDeployment=us2 SumoCollectorName=my-collector`.
- Tagging: `CloudFrontDistributionId=<id>` stored on the instance as a tag.

Example with extras:
- `aws cloudformation deploy --template-file infra/ec2-stack.yaml --stack-name devops-testapp \
   --parameter-overrides VpcId=vpc-xxxx SubnetId=subnet-xxxx KeyName=your-key \
   GitRef=main InstallRequirements=true AdditionalPipPackages="pandas==2.2.2 numpy" \
   UseVenv=true DataVolumeSizeGiB=101 SumoEnabled=false`

### Makefile shortcuts
- Deploy stack: `make ec2-stack-deploy VPC_ID=vpc-xxx SUBNET_ID=subnet-xxx KEY_NAME=my-key CFN_EXTRA_PARAMS="GitRef=main InstallRequirements=true"`
- Show outputs: `make ec2-stack-outputs`
- Delete stack: `make ec2-stack-delete`
- Route53 A record: `make dns-upsert HOSTED_ZONE_ID=Z123 RECORD_NAME=testapp-devops.tidepool.org`
- Remove Route53 record: `make dns-delete HOSTED_ZONE_ID=Z123 RECORD_NAME=testapp-devops.tidepool.org`
- SSM shell: `make ssm-session`

## TLS via CloudFront
- Template: `infra/cloudfront-stack.yaml` creates an ACM cert (us-east-1), a CloudFront distribution with your domain, and a Route53 A alias record.
- Parameters:
  - `DomainName` (e.g., `testapp-devops.tidepool.org`), `HostedZoneId`, `OriginDomainName` (EC2 public DNS or ALB DNS), `OriginPort` (default 8000).
- Deploy with Makefile:
  - `make cf-stack-deploy HOSTED_ZONE_ID=Z123 ORIGIN_DOMAIN=<ec2-public-dns> DOMAIN_NAME=testapp-devops.tidepool.org`
- After deploy: browse `https://testapp-devops.tidepool.org` (CloudFront caches GET/HEAD, redirects to HTTPS).
- Open `index.html` directly in a browser for quick checks.

## CI/CD (GitHub Actions)
- Workflow: `.github/workflows/deploy.yml` deploys EC2 then CloudFront on push to `main`.
- Setup:
  - Create an AWS IAM role for GitHub OIDC and add its ARN as secret `AWS_ROLE_TO_ASSUME`.
  - Set repo Variables: `AWS_REGION`, `VPC_ID`, `SUBNET_ID`, `KEY_NAME`, `HOSTED_ZONE_ID`, `DOMAIN_NAME`.
- Run: push to `main` or trigger manually from the Actions tab.

## Releases
- Tag and push: `make release-tag VERSION=v0.1.0` (requires git remote auth).
- Changelog: see `CHANGELOG.md`.

## Coding Style & Naming Conventions
- HTML/CSS/JS with 2-space indentation; UTF-8; LF line endings.
- HTML: semantic tags (`header`, `main`, `section`); lowercase attributes; double quotes for attributes.
- CSS: BEM-style class names (`.block__element--modifier`); group variables at top.
- JS (if added): ES6+, `const`/`let`, strict mode; functions in `camelCase`; constants in `UPPER_SNAKE_CASE`.
- Keep inline scripts/styles minimal; prefer `assets/js/*.js` and `assets/css/*.css` when code grows.

## Testing Guidelines
- No framework currently. Use a manual smoke checklist:
  - Page loads without console errors; required data renders; layout responsive.
  - Offline load works when served statically.
- If adding tests later, place them under `tests/` and use a lightweight runner (e.g., Playwright or Cypress for UI).

## Commit & Pull Request Guidelines
- Current history is informal; adopt Conventional Commits going forward:
  - Examples: `feat: add status banner`, `fix: handle missing data`.
- PRs should include: clear description, motivation, before/after screenshots (UI changes), and linked issues.
- Keep diffs focused; note any breaking changes in the PR description.

## Agent-Specific Notes
- Respect the minimal, static nature of the site; avoid build systems unless justified.
- When introducing structure, add `assets/` first; document any new folders in this file.
