#!/bin/sh
#
# Start Script for steam-engine
# Builds and starts Docker containers
#

set -e

echo "Starting steam-engine..."

# Verify artifacts exist for offline build
echo "Checking for required artifacts..."
REQUIRED_ARTIFACTS="artifacts/steampipe_linux_amd64.tar.gz artifacts/steampipe-db.tar.gz artifacts/steampipe-internal.tar.gz artifacts/steampipe-plugins.tar.gz"
MISSING=""
for artifact in $REQUIRED_ARTIFACTS; do
    if [ ! -f "$artifact" ]; then
        MISSING="$MISSING $artifact"
    fi
done

if [ -n "$MISSING" ]; then
    echo "ERROR: Missing artifacts:$MISSING"
    echo ""
    echo "To fix: Run scripts/download.sh on a connected machine, then copy artifacts/ to this server:"
    echo "  scp -r artifacts/ user@this-server:\$(pwd)/artifacts/"
    exit 1
fi
echo "All artifacts present"

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
