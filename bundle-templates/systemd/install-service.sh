#!/bin/bash
#
# install-service.sh - Install steampipe as a systemd service
#
# This script:
# - Creates 'steampipe' system user
# - Creates config directory if not exists
# - Copies config templates if config dir empty
# - Sets ownership on bundle directory
# - Installs systemd service file
# - Runs systemctl daemon-reload
#
# Usage:
#   sudo ./systemd/install-service.sh
#
set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$BUNDLE_DIR/config"

echo "Installing Steampipe systemd service..."
echo ""

# Create steampipe system user
echo "==> Creating steampipe user..."
if ! id -u steampipe &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin steampipe
  echo "    Created user: steampipe"
else
  echo "    User already exists: steampipe"
fi

# Create config directory
echo "==> Setting up config directory..."
if [ ! -d "$CONFIG_DIR" ]; then
  mkdir -p "$CONFIG_DIR"
  echo "    Created: $CONFIG_DIR"
fi

# Copy config templates if config dir is empty (or only has sample files)
SPC_COUNT=$(find "$CONFIG_DIR" -name "*.spc" ! -name "*.sample" 2>/dev/null | wc -l)
if [ "$SPC_COUNT" -eq 0 ]; then
  echo "==> Copying config templates..."
  if [ -d "$BUNDLE_DIR/config-templates" ]; then
    cp "$BUNDLE_DIR/config-templates/"*.spc "$CONFIG_DIR/" 2>/dev/null || true
    echo "    Copied templates to $CONFIG_DIR"
    echo "    IMPORTANT: Edit .spc files with your credentials!"
  fi
else
  echo "    Config files already exist, skipping template copy"
fi

# Create steampipe.env if not exists
echo "==> Setting up environment..."
if [ ! -f "$BUNDLE_DIR/steampipe.env" ]; then
  cp "$BUNDLE_DIR/steampipe.env.example" "$BUNDLE_DIR/steampipe.env"
  echo "    Created steampipe.env from example"
else
  echo "    steampipe.env already exists"
fi

# Set ownership on bundle directory
echo "==> Setting bundle ownership..."
chown -R steampipe:steampipe "$BUNDLE_DIR"
echo "    Set ownership: $BUNDLE_DIR"

# Install systemd service
echo "==> Installing systemd service..."
cp "$SCRIPT_DIR/steampipe.service" /etc/systemd/system/
systemctl daemon-reload
echo "    Installed: /etc/systemd/system/steampipe.service"

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Configure credentials:"
echo "     sudo vi $CONFIG_DIR/jira.spc"
echo "     sudo vi $CONFIG_DIR/gitlab.spc"
echo "     sudo vi $CONFIG_DIR/bitbucket.spc"
echo ""
echo "  2. Review environment settings:"
echo "     sudo vi $BUNDLE_DIR/steampipe.env"
echo ""
echo "  3. Enable and start the service:"
echo "     sudo systemctl enable steampipe"
echo "     sudo systemctl start steampipe"
echo ""
echo "  4. Check status:"
echo "     sudo systemctl status steampipe"
echo "     sudo journalctl -u steampipe -f"
echo ""
echo "  5. Connect:"
echo "     psql -h localhost -p 9193 -U steampipe -d steampipe"
echo ""
