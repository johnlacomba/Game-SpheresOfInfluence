#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')}
VOLUME_NAME="${PROJECT_NAME// /-}_ssl_certs"
VOLUME_NAME=${VOLUME_NAME//[^a-z0-9_-]/}

DOMAIN=${1:-}
EMAIL=${2:-}

usage() {
  echo "Usage: $0 <domain> [email]" >&2
  echo "Example: $0 game.example.com admin@game.example.com" >&2
}

if [ -z "$DOMAIN" ]; then
  usage
  exit 1
fi

if [ -z "$EMAIL" ]; then
  EMAIL="admin@${DOMAIN}"
fi

cd "$SCRIPT_DIR"

mkdir -p nginx/webroot certbot/logs ssl

export DOMAIN EMAIL CERTBOT_EMAIL="$EMAIL"

TEMP_CONTAINER="spheres-temp-nginx"
cleanup() {
  if sudo docker ps -a --format '{{.Names}}' | grep -q "^${TEMP_CONTAINER}$"; then
    sudo docker rm -f "$TEMP_CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if sudo docker ps --format '{{.Names}}' | grep -q "^${TEMP_CONTAINER}$"; then
  sudo docker rm -f "$TEMP_CONTAINER" >/dev/null 2>&1 || true
fi

echo "🌐 Starting temporary nginx container to answer HTTP challenge..."
sudo docker run -d --name "$TEMP_CONTAINER" \
  -p 80:80 \
  -v "$SCRIPT_DIR/nginx/webroot:/usr/share/nginx/html" \
  nginx:1.27-alpine >/dev/null

sleep 3

echo "📜 Requesting certificates for $DOMAIN"
sudo DOMAIN="$DOMAIN" CERTBOT_EMAIL="$EMAIL" docker-compose --profile ssl-setup run --rm certbot

cleanup

sudo docker-compose --profile cert-setup run --rm cert-setup >/dev/null 2>&1 || true

if sudo docker run --rm -v "${VOLUME_NAME}:/ssl" alpine test -f /ssl/fullchain.pem && \
  sudo docker run --rm -v "${VOLUME_NAME}:/ssl" alpine test -f /ssl/privkey.pem; then
  echo "✅ Certificates stored in Docker volume ${VOLUME_NAME}"
  mkdir -p ssl
  sudo docker run --rm -v "${VOLUME_NAME}:/ssl" -v "$SCRIPT_DIR/ssl:/backup" alpine sh -c 'cp /ssl/fullchain.pem /backup/ && cp /ssl/privkey.pem /backup/'
  echo "📁 Local copies written to ssl/fullchain.pem and ssl/privkey.pem"
else
  echo "❌ Failed to verify certificates in Docker volume" >&2
  exit 1
fi

echo "🚀 SSL setup complete. You can now run quick-deploy.sh"
