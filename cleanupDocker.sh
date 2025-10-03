#!/bin/bash
set -e

CONTAINERS=$(sudo docker ps -aq)

if [ -n "$CONTAINERS" ]; then
  echo "🛑 Stopping running containers..."
  sudo docker stop $CONTAINERS >/dev/null 2>&1 || true

  echo "🧹 Removing containers..."
  sudo docker rm $CONTAINERS >/dev/null 2>&1 || true
else
  echo "ℹ️  No containers to stop or remove."
fi

echo "🗑️  Pruning unused Docker data..."
sudo docker system prune --all --volumes --force

echo "✅ Docker environment cleaned."
