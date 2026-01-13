#!/bin/bash
set -e

APP_DIR="${BASE_DIR:-/apps/data/steam-engine}"
cd "$APP_DIR"

echo "==> Stopping steam-engine..."
if docker compose ps -q 2>/dev/null | grep -q .; then
    docker compose down
    echo "==> Stopped"
else
    echo "==> Not running"
fi
