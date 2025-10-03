# Game: Spheres of Influence

Spheres of Influence is a multiplayer territory-control game featuring a procedurally evolving tile map, real-time ticks, and resource harvesting. The backend is written in Go, the frontend is React + Vite, and the deployment pipeline uses AWS Cognito for authentication, Terraform for infrastructure-as-code, and ECS Fargate for container orchestration.

## Features

- **Square-tiled world** with discrete ticks driving simulation updates.
- **Cognito-secured gameplay** with JWT validation in the Go API and Amplify-powered login on the frontend.
- **Real-time websocket updates** broadcasting game state to connected players every tick.
- **Resource mechanics** including core-based spreading influence and automated resource routing toward player cores.
- **Infrastructure-as-code** Terraform stack provisioning VPC, Cognito, DNS, and either a Docker-ready EC2 host or the original ECS/Fargate services.
- **Docker-first workflow** with individual service Dockerfiles and a compose file for local development.

## Repository layout

```
backend/   Go API & game simulation logic
frontend/  React client (Vite + TypeScript)
terraform/ Terraform configuration for AWS deployment
```

## Local development

### Prerequisites

- Go 1.22+
- Node.js 20+
- npm 10+
- Docker Desktop (for container workflows)

### Backend

```bash
cd backend
cp .env.example .env # optional, configure env vars if needed
GO_RUN=$(go run ./cmd/server)
```

Environment variables of note:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | API listen port |
| `GAME_WIDTH` | `64` | Board width |
| `GAME_HEIGHT` | `64` | Board height |
| `GAME_RESOURCE_TILES` | `220` | Number of seeded resource tiles |
| `GAME_TICK_MS` | `1000` | Tick interval in milliseconds |
| `COGNITO_REGION` | – | AWS region of Cognito user pool |
| `COGNITO_USER_POOL_ID` | – | Cognito user pool ID |
| `COGNITO_APP_CLIENT_ID` | – | Cognito app client ID |
| `ALLOW_INSECURE_AUTH` | `false` | Set to `true` to bypass Cognito (local debug) |

When `ALLOW_INSECURE_AUTH=true`, provide an `X-Debug-Player` header on REST calls or a `playerId` query parameter on the websocket connection.

### Frontend

```bash
cd frontend
npm install
npm run dev
```

Create a `.env.local` with at minimum:

```
VITE_BACKEND_URL=http://localhost:8080
VITE_COGNITO_REGION=us-east-1
VITE_COGNITO_USER_POOL_ID=<pool id>
VITE_COGNITO_APP_CLIENT_ID=<client id>
# Optional developer shortcut when Cognito is disabled
VITE_DEBUG_PLAYER_ID=dev-player-1
```

### Docker Compose

Build and run both services locally:

```bash
docker-compose up --build
```

This exposes the backend at `http://localhost:8080` and the frontend at `http://localhost:5173` (served by Nginx inside the container).

### Automated deployment scripts

The project mirrors the deployment workflow from the Space Trading Sim repo. Three scripts at the repo root orchestrate the full lifecycle:

- `cleanupDocker.sh` – stops/removes all containers and prunes Docker data.
- `setup-ssl.sh <domain> [email]` – provisions Let's Encrypt certificates using the compose `certbot` profile.
- `quick-deploy.sh <domain> <email> <mode>` – rebuilds images/assets and starts the stack with SSL and reverse proxy wiring. Modes: `development` (default) or `production`. When running on the Terraform-provisioned EC2 host the script also loads Cognito IDs from `/etc/spheres-of-influence/cognito.env`, which is generated automatically during instance bootstrap.

Example one-liner (mirroring the original workflow):

```bash
date ; cd && sudo rm -rf Game-SpheresOfInfluence ; sudo ./cleanupDocker.sh ; git clone https://github.com/johnlacomba/Game-SpheresOfInfluence.git && cd Game-SpheresOfInfluence/ && cp cleanupDocker.sh ~/cleanupDocker.sh && sudo ./setup-ssl.sh game.example.com admin@game.example.com && sudo ./quick-deploy.sh game.example.com admin@game.example.com production ; date
```

## Terraform deployment (AWS)

> ⚠️ Ensure you have AWS credentials configured for the target account before running Terraform. The configuration now supports two deployment paths:
>
> - **EC2 host (default):** provisions a single Amazon Linux 2023 instance, installs Docker, clones this repository, and drops a `/usr/local/bin/deploy-spheres.sh` helper that runs the same `quick-deploy.sh` workflow you use locally.
> - **ECS/Fargate (optional):** retains the original load-balanced container services; enable it by setting `enable_ecs=true` and providing ECR image URIs.

### Key variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `enable_ec2` | `true` | Provision the EC2 host and Elastic IP |
| `enable_ecs` | `false` | Provision the Fargate/ALB stack (requires container images) |
| `ssh_key_name` | – | Existing EC2 key pair used for SSH access (required when `enable_ec2=true`) |
| `domain_name` | `sphereofinfluence.click` | Public domain to wire via Route 53 (set to empty string to skip DNS) |
| `admin_email` | `admin@sphereofinfluence.click` | Email passed to `setup-ssl.sh`/Certbot |
| `deployment_mode` | `production` | Mode forwarded to `quick-deploy.sh` |
| `git_repo_url` | GitHub repo URL | Repository cloned onto the host |
| `cognito_domain_prefix` | – | Required for Cognito hosted UI; must be globally unique |

When `enable_ecs=true`, also provide `backend_image`, `frontend_image`, and optionally adjust `desired_count`.

### Provisioning the EC2 deployment host

1. Ensure the target account has a key pair named as the value passed to `ssh_key_name`.
2. (Optional) Register or transfer the `domain_name` to Route 53 manually. Terraform will create the hosted zone and A records, but AWS still requires a human-approved registration step.
3. Populate a `terraform.tfvars` (or pass `-var` flags) similar to:

```hcl
enable_ec2       = true
enable_ecs       = false
ssh_key_name     = "my-ssh-key"
domain_name      = "sphereofinfluence.click"
admin_email      = "ops@sphereofinfluence.click"
cognito_domain_prefix = "soi-demo-001" # must be globally unique
oauth_callback_urls = [
  "https://sphereofinfluence.click", 
  "https://sphereofinfluence.click/auth/callback"
]
oauth_logout_urls = ["https://sphereofinfluence.click"]
```

4. Apply the stack:

```bash
cd terraform
terraform init
terraform apply
```

5. Back in the repository root, run `./scripts/export-cognito-env.sh` to materialise the Cognito identifiers in `cognito.env`, then copy that file to the EC2 host and place it at `/etc/spheres-of-influence/cognito.env` (for example, `scp cognito.env ec2-user@<ec2_public_ip>:/tmp && sudo mv /tmp/cognito.env /etc/spheres-of-influence/`).

6. Once the instance finishes bootstrapping, SSH in (`ssh ec2-user@<ec2_public_ip>`) and run the helper script if auto-deploy was not enabled:

```bash
sudo /usr/local/bin/deploy-spheres.sh sphereofinfluence.click ops@sphereofinfluence.click production
```

The `ec2_public_ip`, `route53_name_servers`, and Cognito IDs are all surfaced as outputs for wiring the frontend, and quick-deploy will automatically consume the copied `cognito.env`.

### Optional: restore the ECS/Fargate deployment

If you prefer the fully managed ECS path from the Space Trading Sim example, flip the flags:

```hcl
enable_ec2       = false
enable_ecs       = true
backend_image    = "123456789012.dkr.ecr.us-east-1.amazonaws.com/spheres-backend:latest"
frontend_image   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/spheres-frontend:latest"
ssh_key_name     = "my-ssh-key" # only needed if you keep enable_ec2=true
cognito_domain_prefix = "soi-demo"
```

The Route 53 records will automatically point the apex (and `www`) to the ALB when ECS is enabled, or to the EC2 Elastic IP otherwise.

> ℹ️ Domain purchase: Terraform cannot auto-purchase `SphereOfInfluence.click` because AWS Route 53 requires email/SMS verification. Register the domain manually in the console or CLI, then re-run `terraform apply` so the hosted zone records propagate.

## Testing

- `backend`: `go test ./...`
- `frontend`: `npm run build` (tsc + vite build)

CI pipelines can cache the Docker layers and Terraform state to speed up deployments.

## Next steps

- Introduce player actions (e.g., abilities, resource spending).
- Extend Terraform for CI/CD (ECR lifecycle policies, CodePipeline).
- Add distributed tick coordination (e.g., Redis or DynamoDB state persistence).
- Implement monitoring dashboards (CloudWatch, X-Ray).

Enjoy building and expanding the Spheres of Influence! 🎮
