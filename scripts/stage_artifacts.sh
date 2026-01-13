#!/bin/sh
#
# Stage artifacts to target server for offline deployment
# Run this from a connected machine after running download.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/../artifacts"

# Default target from .gitlab-ci.yml
DEFAULT_HOST="mars"
DEFAULT_PATH="/apps/data/steam-engine"
DEFAULT_USER="fadzi"

TARGET_HOST="${1:-$DEFAULT_HOST}"
TARGET_PATH="${2:-$DEFAULT_PATH}"
TARGET_USER="${3:-$DEFAULT_USER}"

echo "Staging artifacts to $TARGET_USER@$TARGET_HOST:$TARGET_PATH/artifacts/"

# Check artifacts exist locally
REQUIRED="steampipe_linux_amd64.tar.gz steampipe-db.tar.gz steampipe-internal.tar.gz steampipe-plugins.tar.gz"
for f in $REQUIRED; do
    if [ ! -f "$ARTIFACTS_DIR/$f" ]; then
        echo "ERROR: Missing local artifact: $ARTIFACTS_DIR/$f"
        echo "Run scripts/download.sh first"
        exit 1
    fi
done

# Create target directory (use shared for persistence across releases)
ssh "$TARGET_USER@$TARGET_HOST" "mkdir -p $TARGET_PATH/shared/artifacts"

# Copy artifacts
scp "$ARTIFACTS_DIR"/*.tar.gz "$TARGET_USER@$TARGET_HOST:$TARGET_PATH/shared/artifacts/"

# Verify
echo ""
echo "Verifying artifacts on target..."
ssh "$TARGET_USER@$TARGET_HOST" "ls -lh $TARGET_PATH/shared/artifacts/"

echo ""
echo "Done. Artifacts staged successfully."
