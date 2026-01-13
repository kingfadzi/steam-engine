#!/bin/sh
set -e

echo "==> Building Docker image..."
docker build -t steam-engine-steampipe:latest -f Dockerfile .

echo "==> Saving image to tarball..."
docker save steam-engine-steampipe:latest | gzip > release.tar.gz

echo "==> Packaging config files..."
tar -czvf config.tar.gz config/ docker-compose.yml

echo "==> Creating final release..."
# Combine image and config into single release
tar -cvf release-full.tar release.tar.gz config.tar.gz
mv release-full.tar release.tar.gz

echo "==> Release created: release.tar.gz"
ls -lh release.tar.gz
