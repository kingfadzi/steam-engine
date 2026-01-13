#!/bin/sh
#
# Start Script for steam-engine
# Builds and starts Docker containers
#

set -e

echo "Starting steam-engine..."

# Verify artifacts exist for offline build
echo "Checking for required artifacts..."

# Use shared artifacts location if BASE_DIR is set (deployed via pipeline)
if [ -n "$BASE_DIR" ] && [ -d "$BASE_DIR/shared/artifacts" ]; then
    ARTIFACTS_DIR="$BASE_DIR/shared/artifacts"
else
    ARTIFACTS_DIR="artifacts"
fi

REQUIRED="steampipe_linux_amd64.tar.gz steampipe-db.tar.gz steampipe-internal.tar.gz steampipe-plugins.tar.gz"
MISSING=""
for f in $REQUIRED; do
    if [ ! -f "$ARTIFACTS_DIR/$f" ]; then
        MISSING="$MISSING $f"
    fi
done

if [ -n "$MISSING" ]; then
    echo "ERROR: Missing artifacts in $ARTIFACTS_DIR:$MISSING"
    echo ""
    echo "To fix: Run scripts/download.sh on a connected machine, then copy to shared:"
    echo "  scp -r artifacts/* user@server:$BASE_DIR/shared/artifacts/"
    exit 1
fi
echo "All artifacts present in $ARTIFACTS_DIR"

# Symlink artifacts into release if using shared
if [ "$ARTIFACTS_DIR" != "artifacts" ]; then
    ln -sfn "$ARTIFACTS_DIR" artifacts
fi

# Ensure clean state before starting
echo "Cleaning up any existing containers..."
docker compose down 2>/dev/null || true

# Build and start
echo "Building Docker image..."
docker compose build

echo "Starting containers..."
docker compose up -d

echo "Waiting for service to start..."
sleep 10

echo "Containers started."
docker compose ps
