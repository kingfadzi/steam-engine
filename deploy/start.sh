#!/bin/bash
set -e

APP_DIR="${BASE_DIR:-/apps/data/steam-engine}"
cd "$APP_DIR"

echo "==> Extracting release..."
tar -xvf release.tar.gz
tar -xzvf config.tar.gz

echo "==> Loading Docker image..."
gunzip -c release.tar.gz 2>/dev/null | docker load || docker load < release.tar.gz

echo "==> Starting steam-engine..."
docker compose up -d

echo "==> Waiting for service to start..."
sleep 10

echo "==> Status:"
docker compose ps
