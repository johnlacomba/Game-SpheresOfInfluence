#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')}
VOLUME_NAME="${PROJECT_NAME// /-}_ssl_certs"
VOLUME_NAME=${VOLUME_NAME//[^a-z0-9_-]/}

DOMAIN=${1:-localhost}
EMAIL=${2:-admin@example.com}
MODE=${3:-development}
MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')

if ! command -v docker >/dev/null; then
  echo "Docker is required." >&2
  exit 1
fi

if ! command -v docker-compose >/dev/null; then
  echo "docker-compose is required." >&2
  exit 1
fi

cd "$SCRIPT_DIR"

mkdir -p nginx/logs nginx/webroot certbot/logs ssl

if [ ! -f .env.docker ]; then
  echo ".env.docker template is missing." >&2
  exit 1
fi

cp .env.docker .env

sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
sed -i "s/^CERTBOT_EMAIL=.*/CERTBOT_EMAIL=$EMAIL/" .env
sed -i "s/^DEPLOYMENT_MODE=.*/DEPLOYMENT_MODE=$MODE/" .env

BACKEND_URL="https://$DOMAIN"
if [ "$DOMAIN" = "localhost" ]; then
  BACKEND_URL="https://localhost"
fi

sed -i "s|^VITE_BACKEND_URL=.*|VITE_BACKEND_URL=$BACKEND_URL|" .env
if [ "$DOMAIN" = "localhost" ]; then
  sed -i "s|^CORS_ALLOWED_ORIGIN=.*|CORS_ALLOWED_ORIGIN=*|" .env
else
  sed -i "s|^CORS_ALLOWED_ORIGIN=.*|CORS_ALLOWED_ORIGIN=https://$DOMAIN|" .env
fi

if [ "$MODE" = "production" ]; then
  sed -i "s/^TLS_ONLY=.*/TLS_ONLY=true/" .env
  sed -i "s/^ALLOW_INSECURE_AUTH=.*/ALLOW_INSECURE_AUTH=false/" .env
else
  sed -i "s/^TLS_ONLY=.*/TLS_ONLY=false/" .env
  sed -i "s/^ALLOW_INSECURE_AUTH=.*/ALLOW_INSECURE_AUTH=true/" .env
fi

sed "s/__DOMAIN__/$DOMAIN/g" nginx/default.conf.template > nginx/default.conf

if [ "$DOMAIN" = "localhost" ]; then
  if [ ! -f ssl/fullchain.pem ] || [ ! -f ssl/privkey.pem ]; then
    echo "🔒 Generating local self-signed certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout ssl/privkey.pem \
      -out ssl/fullchain.pem \
      -subj "/C=US/ST=State/L=Local/O=SpheresOfInfluence/CN=localhost"
  fi
  sudo docker volume create "$VOLUME_NAME" >/dev/null 2>&1 || true
  sudo docker run --rm -v "$VOLUME_NAME:/ssl" -v "$SCRIPT_DIR/ssl:/backup" alpine sh -c 'cp /backup/fullchain.pem /ssl/fullchain.pem && cp /backup/privkey.pem /ssl/privkey.pem'
else
  if [ ! -f ssl/fullchain.pem ] || [ ! -f ssl/privkey.pem ]; then
    echo "⚠️  No SSL certificates found. Run ./setup-ssl.sh $DOMAIN $EMAIL first."
    exit 1
  fi
  sudo docker volume create "$VOLUME_NAME" >/dev/null 2>&1 || true
  sudo docker run --rm -v "$VOLUME_NAME:/ssl" -v "$SCRIPT_DIR/ssl:/backup" alpine sh -c 'cp /backup/fullchain.pem /ssl/fullchain.pem && cp /backup/privkey.pem /ssl/privkey.pem'
fi

echo "🏗️  Building backend image..."
sudo docker-compose build backend >/dev/null

echo "🏗️  Building frontend assets..."
sudo docker-compose --profile build run --rm frontend-builder >/dev/null

echo "🚀 Starting services..."
sudo docker-compose up -d

echo "⏳ Waiting for services to stabilize..."
sleep 15

sudo docker-compose ps

echo "🎉 Deployment completed"
if [ "$DOMAIN" = "localhost" ]; then
  echo "Frontend: https://localhost"
  echo "Backend health: https://localhost/health"
else
  echo "Frontend: https://$DOMAIN"
  echo "Backend: https://$DOMAIN/api"
fi
