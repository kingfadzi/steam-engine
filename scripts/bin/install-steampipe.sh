#!/bin/bash
# Install steampipe bundle from Windows filesystem
# Run once after WSL import: install-steampipe.sh

set -e

BUNDLE_PATH="${1:-/mnt/c/devhome/projects/steamengine/binaries/steampipe-bundle.tgz}"
INSTALL_DIR="/opt/steampipe"

echo "=== Steampipe Bundle Installer ==="

# Check if already installed
if [ -x "$INSTALL_DIR/steampipe/steampipe" ] && [ -x "$INSTALL_DIR/db/14.19.0/postgres/bin/postgres" ]; then
    echo "Steampipe already installed."
    /opt/steampipe/steampipe/steampipe --version
    exit 0
fi

# Check bundle exists
if [ ! -f "$BUNDLE_PATH" ]; then
    echo "ERROR: Bundle not found: $BUNDLE_PATH"
    echo ""
    echo "Usage: install-steampipe.sh [path-to-bundle]"
    echo "Default: /mnt/c/devhome/projects/steamengine/binaries/steampipe-bundle.tgz"
    exit 1
fi

echo "Installing from: $BUNDLE_PATH"

# Extract bundle
sudo tar -xzf "$BUNDLE_PATH" -C "$INSTALL_DIR"
sudo chown -R steampipe:steampipe "$INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR/steampipe/steampipe"

# Verify installation
echo ""
echo "Verifying installation..."
if [ -x "$INSTALL_DIR/steampipe/steampipe" ]; then
    echo "  Steampipe binary: OK"
    "$INSTALL_DIR/steampipe/steampipe" --version
else
    echo "  Steampipe binary: MISSING"
    exit 1
fi

if [ -x "$INSTALL_DIR/db/14.19.0/postgres/bin/postgres" ]; then
    echo "  Postgres binary: OK"
else
    echo "  Postgres binary: MISSING"
    exit 1
fi

echo ""
echo "Starting services..."
sudo systemctl start steampipe gateway

echo ""
echo "Installation complete!"
sudo systemctl status steampipe gateway --no-pager
