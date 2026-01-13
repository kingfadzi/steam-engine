#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$REPO_DIR/artifacts"

# Required artifacts
REQUIRED_FILES=(
  "steampipe_linux_amd64.tar.gz"
  "steampipe-db.tar.gz"
  "steampipe-internal.tar.gz"
  "steampipe-plugins.tar.gz"
)

# Base image (override with: BASE_IMAGE=your-image ./build.sh)
BASE_IMAGE="${BASE_IMAGE:-almalinux:9}"

echo "==> Validating artifacts..."

# Check artifacts directory exists
if [ ! -d "$ARTIFACTS_DIR" ]; then
  echo "ERROR: artifacts/ directory not found"
  echo "Run scripts/download.sh on a connected machine first"
  exit 1
fi

# Check each required file
MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$ARTIFACTS_DIR/$file" ]; then
    echo "ERROR: Missing $file"
    MISSING=1
  else
    echo "  OK: $file"
  fi
done

if [ $MISSING -eq 1 ]; then
  echo ""
  echo "ERROR: Missing artifacts. Run scripts/download.sh on a connected machine first"
  exit 1
fi

echo ""
echo "==> Building image with base: $BASE_IMAGE"
docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  -f "$REPO_DIR/Dockerfile.offline" \
  -t steam-engine-steampipe:latest \
  "$REPO_DIR"

echo ""
echo "==> Build complete: steam-engine-steampipe:latest"
