#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$REPO_DIR/artifacts"

echo "==> Preparing artifacts for air-gapped build"
mkdir -p "$ARTIFACTS_DIR"

# 1. Download Steampipe binary
echo "==> Downloading Steampipe binary..."
curl -fSL https://github.com/turbot/steampipe/releases/latest/download/steampipe_linux_amd64.tar.gz \
  -o "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz"

# 2. Run remaining steps in container to ensure glibc compatibility
echo "==> Running artifact collection in container..."
docker run --rm \
  -v "$ARTIFACTS_DIR:/artifacts" \
  almalinux:9 \
  bash -c '
    set -e

    # Install deps
    yum -y install --allowerasing curl tar gzip shadow-utils >/dev/null 2>&1

    # Create non-root user
    useradd -m steampipe
    mkdir -p /home/steampipe/work
    cp /artifacts/steampipe_linux_amd64.tar.gz /home/steampipe/work/
    chown -R steampipe:steampipe /home/steampipe

    # Run as steampipe user
    su - steampipe -c "
      set -e
      cd ~/work

      # Extract steampipe
      tar -xzf steampipe_linux_amd64.tar.gz

      # Install plugins
      echo \"==> Installing plugins...\"
      ./steampipe plugin install theapsgroup/gitlab jira bitbucket --skip-config

      # Trigger embedded Postgres download
      echo \"==> Downloading embedded PostgreSQL...\"
      ./steampipe query \"select 1\"

      # Package artifacts
      echo \"==> Packaging db...\"
      tar -czf /tmp/steampipe-db.tar.gz -C ~/.steampipe/db .

      echo \"==> Packaging internal...\"
      tar -czf /tmp/steampipe-internal.tar.gz -C ~/.steampipe/internal .

      echo \"==> Packaging plugins...\"
      tar -czf /tmp/steampipe-plugins.tar.gz -C ~/.steampipe/plugins .
    "

    # Copy artifacts out
    cp /tmp/steampipe-db.tar.gz /artifacts/
    cp /tmp/steampipe-internal.tar.gz /artifacts/
    cp /tmp/steampipe-plugins.tar.gz /artifacts/

    echo "==> Done inside container"
  '

echo ""
echo "==> Artifacts saved to: $ARTIFACTS_DIR"
ls -lh "$ARTIFACTS_DIR"
