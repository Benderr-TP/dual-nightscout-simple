# Data Science Web App Stack Template

This repository provides a complete AWS infrastructure template for deploying data science web applications with automated CI/CD via GitHub Actions.

## 🚀 Quick Start

1. **Use this template**: Click "Use this template" to create your own repository
2. **Configure your app**: Update `index.html` or add your own web application files
3. **Set up AWS OIDC**: Follow the [AWS OIDC Setup Guide](config/github-secrets-template.md)
4. **Configure GitHub**: Add required secrets and variables from [GitHub Configuration](config/github-secrets-template.md)
5. **Deploy**: Push to main branch or trigger workflow manually

## 🏗️ What You Get

- **EC2 Instance**: Auto-configured with your application
- **CloudFront CDN**: TLS-enabled global distribution
- **Route53 DNS**: Automatic domain setup
- **GitHub Actions**: Zero-config CI/CD pipeline
- **Monitoring**: CloudWatch logs and health endpoints

## 📁 Project Structure

```
├── config/
│   ├── template-config.yaml          # Local configuration template
│   └── github-secrets-template.md    # GitHub setup instructions
├── infra/
│   ├── ec2-stack.yaml                # EC2 CloudFormation template
│   ├── cloudfront-stack.yaml         # CloudFront CloudFormation template
│   └── dev-params.json               # Development parameters
├── tools/
│   ├── serve.py                      # Python web server
│   └── entrypoint.sh                 # Container entrypoint
├── .github/workflows/
│   └── deploy.yml                    # CI/CD pipeline
├── index.html                        # Your web application
└── requirements.txt                  # Python dependencies
```

## 🔧 Configuration

### For Local Development

1. Copy the configuration template:
   ```bash
   cp config/template-config.yaml config/local-config.yaml
   ```

2. Update `config/local-config.yaml` with your values

3. Create `.env` file for local variables:
   ```bash
   APP_NAME=my-data-app
   AWS_REGION=us-east-1
   DOMAIN_NAME=my-app.example.com
   # ... other variables
   ```

### For GitHub Actions

Follow the complete setup guide in [config/github-secrets-template.md](config/github-secrets-template.md).

## 🛠️ Development Commands

```bash
# Run locally
python3 tools/serve.py

# Deploy infrastructure manually
make ec2-stack-deploy
make cf-stack-deploy ORIGIN_DOMAIN=<ec2-dns>

# Manage DNS
make dns-upsert HOSTED_ZONE_ID=<zone-id>
make dns-delete HOSTED_ZONE_ID=<zone-id>

# Access deployed instance
make ssm-session
```

## 🎯 Use Cases

### Data Science Dashboards
- Replace `index.html` with your Streamlit, Dash, or custom dashboard
- Add dependencies to `requirements.txt`
- Use the data volume (`/mnt/data`) for datasets

### API Services
- Replace `tools/serve.py` with Flask, FastAPI, or Django
- Configure health endpoints at `/healthz`
- Scale with CloudFront caching

### Static Sites with Dynamic Data
- Keep the static server but add data processing
- Use scheduled tasks for data updates
- Leverage S3 for large datasets

## 🔒 Security Best Practices

- **Restrict SSH access**: Set `SSH_CIDR` to your IP range instead of `0.0.0.0/0`
- **Use IAM roles**: Never commit AWS credentials
- **Enable HTTPS**: CloudFront automatically redirects HTTP to HTTPS
- **Monitor logs**: Check CloudWatch for application and access logs
- **Regular updates**: Enable OS updates in the configuration

## 🚨 Troubleshooting

### Deployment Issues
```bash
# Check stack status
aws cloudformation describe-stacks --stack-name my-app-ec2

# View deployment logs
aws cloudformation describe-stack-events --stack-name my-app-ec2

# SSH into instance
make ssm-session
```

### Application Issues
```bash
# Check service status
sudo systemctl status webapp

# View application logs
sudo tail -f /var/log/webapp/app.log

# Restart service
sudo systemctl restart webapp
```

### DNS Issues
```bash
# Verify DNS propagation
dig my-app.example.com

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

## 📚 Advanced Configuration

### Custom Application Setup
- Modify `infra/ec2-stack.yaml` UserData section for custom installation steps
- Add environment variables to the systemd service configuration
- Use the data volume for persistent storage

### Scaling Options
- Upgrade instance type via `INSTANCE_TYPE` variable
- Add Application Load Balancer for multiple instances
- Implement auto-scaling groups for high availability

### Monitoring and Logging
- Enable CloudWatch detailed monitoring
- Set up log aggregation (Sumo Logic support included)
- Configure alerts for health check failures

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your own AWS environment
5. Submit a pull request

## 📄 License

This template is provided under the MIT License. See LICENSE file for details.

---

**💡 Pro Tip**: Start with the default configuration and gradually customize based on your specific needs. The template is designed to work out-of-the-box for most data science applications.