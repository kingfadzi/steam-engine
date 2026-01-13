#!/bin/sh
#
# Build Release Script for steam-engine
# Creates release.tar.gz for deployment
#

set -e

echo "Building release artifact..."

# Verify artifacts exist for offline build
REQUIRED_ARTIFACTS="artifacts/steampipe_linux_amd64.tar.gz artifacts/steampipe-db.tar.gz artifacts/steampipe-internal.tar.gz artifacts/steampipe-plugins.tar.gz"
for artifact in $REQUIRED_ARTIFACTS; do
    if [ ! -f "$artifact" ]; then
        echo "ERROR: Missing artifact: $artifact"
        echo "Run scripts/download.sh first to download artifacts"
        exit 1
    fi
done
echo "All artifacts present"

# Remove old tarball if exists
rm -f release.tar.gz

# Create a clean tarball including artifacts for offline build
tar --create \
    --gzip \
    --file=/tmp/release.tar.gz \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='.env' \
    --exclude='.claude' \
    --exclude='release.tar.gz' \
    .

mv /tmp/release.tar.gz release.tar.gz

# Verify the tarball was created
if [ ! -f release.tar.gz ]; then
    echo "ERROR: Failed to create release.tar.gz"
    exit 1
fi

echo "Created release.tar.gz ($(du -h release.tar.gz | cut -f1))"
