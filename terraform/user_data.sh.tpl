#!/bin/bash
set -xeuo pipefail

PROJECT_NAME="${project_name}"
PROJECT_ROOT="/opt/${project_name}"
REPO_URL="${git_repo_url}"
REPO_BRANCH="${git_branch}"
DEFAULT_DOMAIN="${domain_name}"
FALLBACK_DOMAIN="${fallback_domain}"
DEFAULT_EMAIL="${admin_email}"
DEFAULT_MODE="${deployment_mode}"
AUTO_DEPLOY="${auto_deploy}"
COGNITO_REGION="${cognito_region}"
COGNITO_USER_POOL_ID="${cognito_user_pool_id}"
COGNITO_APP_CLIENT_ID="${cognito_app_client_id}"

# System packages
sudo dnf update -y
sudo dnf install -y docker git jq unzip
sudo dnf install -y docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker ec2-user || true

if [ ! -f /usr/local/bin/docker-compose ] && [ -f /usr/libexec/docker/cli-plugins/docker-compose ]; then
  sudo ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
fi

sudo mkdir -p "$PROJECT_ROOT"
sudo chown ec2-user:ec2-user "$PROJECT_ROOT"

if [ ! -d "$PROJECT_ROOT/.git" ]; then
  sudo -u ec2-user git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$PROJECT_ROOT"
else
  sudo -u ec2-user bash -c "cd '$PROJECT_ROOT' && git fetch --depth 1 origin '$REPO_BRANCH' && git checkout '$REPO_BRANCH' && git pull --ff-only origin '$REPO_BRANCH'"
fi

sudo mkdir -p /etc/spheres-of-influence
cat <<ENVFILE | sudo tee /etc/spheres-of-influence/cognito.env >/dev/null
# Managed by Terraform user-data. Do not edit manually.
COGNITO_REGION=$COGNITO_REGION
COGNITO_USER_POOL_ID=$COGNITO_USER_POOL_ID
COGNITO_APP_CLIENT_ID=$COGNITO_APP_CLIENT_ID
VITE_COGNITO_REGION=$COGNITO_REGION
VITE_COGNITO_USER_POOL_ID=$COGNITO_USER_POOL_ID
VITE_COGNITO_APP_CLIENT_ID=$COGNITO_APP_CLIENT_ID
ENVFILE
sudo chmod 644 /etc/spheres-of-influence/cognito.env

cat <<'SCRIPT' | sudo tee /usr/local/bin/deploy-spheres.sh >/dev/null
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="/opt/${project_name}"
DEFAULT_DOMAIN="${domain_name}"
FALLBACK_DOMAIN="${fallback_domain}"
DEFAULT_EMAIL="${admin_email}"
DEFAULT_MODE="${deployment_mode}"

DOMAIN="$DEFAULT_DOMAIN"
EMAIL="$DEFAULT_EMAIL"
MODE="$DEFAULT_MODE"

if [ -z "$DOMAIN" ]; then
  DOMAIN="$FALLBACK_DOMAIN"
fi

if [ $# -ge 1 ]; then
  DOMAIN="$1"
fi
if [ $# -ge 2 ]; then
  EMAIL="$2"
fi
if [ $# -ge 3 ]; then
  MODE="$3"
fi

cd "$PROJECT_ROOT"
./cleanupDocker.sh || true
./quick-deploy.sh "$DOMAIN" "$EMAIL" "$MODE"
SCRIPT

sudo chmod +x /usr/local/bin/deploy-spheres.sh
sudo chown root:root /usr/local/bin/deploy-spheres.sh

if [ ! -f /etc/profile.d/spheres-of-influence.sh ]; then
  cat <<'MOTD' | sudo tee /etc/profile.d/spheres-of-influence.sh >/dev/null
#!/bin/bash
cat <<'EOF'
============================================================
Spheres of Influence deployment host
------------------------------------------------------------
Run the following to deploy or update the stack:
  sudo /usr/local/bin/deploy-spheres.sh ${domain_display} ${admin_email} ${deployment_mode}

The project code lives in /opt/${project_name}
============================================================
EOF
MOTD
  sudo chmod +x /etc/profile.d/spheres-of-influence.sh
fi

%{ if length(trimspace(additional_commands)) > 0 }
# Additional user-supplied bootstrap commands
${additional_commands}
%{ endif }

if [ "$AUTO_DEPLOY" = "true" ] && [ -n "$DEFAULT_DOMAIN" ]; then
  /usr/local/bin/deploy-spheres.sh "$DEFAULT_DOMAIN" "$DEFAULT_EMAIL" "$DEFAULT_MODE" >> /var/log/spheres-of-influence-bootstrap.log 2>&1 || true
fi
