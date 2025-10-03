# Terraform Configuration for Spheres of Influence

This directory contains the Terraform configuration used to provision the AWS infrastructure for the Spheres of Influence game. The layout mirrors the Space Trading Simulation stack so that deployment, documentation, and automation remain consistent across projects.

## What gets created

- **VPC + public subnets** for the deployment host and optional load balancer
- **EC2 quick-deploy host** (default) including all bootstrap tooling and Cognito configuration wiring
- **Elastic IP** associated with the host
- **AWS Cognito user pool + web client + hosted UI domain**
- **Route 53 hosted zone and DNS records** when a domain is provided
- **Optional ECS/Fargate stack** (enable via `enable_ecs`)

## Prerequisites

1. Terraform ≥ 1.6
2. AWS CLI configured with credentials that can create the listed resources
3. An existing EC2 key pair if you plan to keep `enable_ec2 = true`

## Quick start

1. Copy the example tfvars file and adjust values for your environment:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Review/edit `terraform.tfvars`. At minimum set:

   ```hcl
   aws_region            = "us-east-1"
   project_name          = "spheres-of-influence"
   environment           = "production"
   enable_ec2            = true
   ssh_key_name          = "my-keypair"
   domain_name           = "sphereofinfluence.click"
   admin_email           = "ops@sphereofinfluence.click"
   cognito_domain_prefix = "soi-demo-001" # must be globally unique
   oauth_callback_urls   = ["https://sphereofinfluence.click", "https://sphereofinfluence.click/auth/callback"]
   oauth_logout_urls     = ["https://sphereofinfluence.click"]
   ```

3. Initialise and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Capture the outputs. The EC2 host bootstrap stores Cognito identifiers in `/etc/spheres-of-influence/cognito.env`, and the quick-deploy script consumes them automatically—no manual edits required. If you prefer a local copy of the values, run the helper from the repository root:

   ```bash
   ./scripts/export-cognito-env.sh
   ```

   The generated `cognito.env` can be copied to any host at `/etc/spheres-of-influence/cognito.env` if needed for disaster recovery.

5. SSH into the host and run the provided helper (unless you set `auto_deploy_on_boot = true`):

   ```bash
   sudo /usr/local/bin/deploy-spheres.sh sphereofinfluence.click ops@sphereofinfluence.click production
   ```

The backend and frontend containers will be rebuilt, and the stack will become available at `https://sphereofinfluence.click`.

## Optional: ECS/Fargate pathway

If you want to mirror the fully managed container deployment from the Space Trading Simulation project, set:

```hcl
enable_ec2      = false
enable_ecs      = true
backend_image   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/spheres-backend:latest"
frontend_image  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/spheres-frontend:latest"
```

Terraform will provision an ALB plus ECS services, and the outputs will surface the ALB DNS name alongside the Cognito IDs.

## Cleanup

```bash
terraform destroy
```

## File overview

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration, shared locals, and tagging | 
| `variables.tf` | Input variables mirroring the Space Trading Sim stack | 
| `network.tf` | VPC, subnets, security groups, and load balancer | 
| `deployment_host.tf` | EC2 quick-deploy host, IAM roles, and bootstrap | 
| `cognito.tf` | Cognito user pool, client, and hosted UI domain | 
| `dns.tf` | Route 53 hosted zone and DNS records | 
| `ecs.tf` | Optional ECS/Fargate resources | 
| `outputs.tf` | Consolidated outputs consumed by automation scripts | 
| `user_data.sh.tpl` | Cloud-init template executed on the EC2 host | 
| `terraform.tfvars.example` | Sample configuration | 

## Troubleshooting

- **Cognito domain already taken**: Provide a new `cognito_domain_prefix` and re-apply.
- **SSH access denied**: Confirm the key pair specified in `ssh_key_name` exists in the selected region.
- **DNS not resolving**: Delegate the Route 53 nameservers listed in `route53_name_servers` at your registrar and wait for propagation.
- **ECS tasks failing**: Ensure `backend_image` and `frontend_image` reference images pushed to ECR in the selected region.
