#!/bin/sh
#
# Build Release Script for steam-engine
# Creates release.tar.gz for deployment
#

set -e

echo "Building release artifact..."

# Remove old tarball if exists
rm -f release.tar.gz

# Create a clean tarball (artifacts are pre-staged on target server)
tar --create \
    --gzip \
    --file=/tmp/release.tar.gz \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='.env' \
    --exclude='.claude' \
    --exclude='artifacts' \
    --exclude='release.tar.gz' \
    .

mv /tmp/release.tar.gz release.tar.gz

# Verify the tarball was created
if [ ! -f release.tar.gz ]; then
    echo "ERROR: Failed to create release.tar.gz"
    exit 1
fi

echo "Created release.tar.gz ($(du -h release.tar.gz | cut -f1))"
