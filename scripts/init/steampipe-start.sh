#!/bin/bash
#
# Steampipe service start - extract and exec immediately
# Combines setup and start to minimize scan window
#
set -e

BUNDLE="/opt/steampipe/steampipe-bundle.tgz"
RUNTIME_DIR="/run/steampipe"
PERSIST_DIR="/opt/steampipe"
SECRETS_DIR="/opt/wsl-secrets"

# Source secrets
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi

# Check prerequisites
[ -f "$BUNDLE" ] || { echo "ERROR: Bundle not found: $BUNDLE"; exit 1; }
[ -f "$SECRETS_DIR/steampipe.env" ] || { echo "ERROR: Secrets not configured"; exit 1; }
[ -d "$RUNTIME_DIR" ] || { echo "ERROR: RuntimeDirectory missing"; exit 1; }

# Extract and exec in one go
echo "Extracting and starting steampipe..."
tar -xzf "$BUNDLE" -C "$RUNTIME_DIR"

# Setup data symlink
PG_DIR="$RUNTIME_DIR/db/14.19.0/postgres"
rm -rf "$PG_DIR/data" 2>/dev/null || true
mkdir -p "$PERSIST_DIR/data"
ln -sf "$PERSIST_DIR/data" "$PG_DIR/data"

# Copy config
mkdir -p "$RUNTIME_DIR/config"
cp -r "$PERSIST_DIR/config/"* "$RUNTIME_DIR/config/" 2>/dev/null || true

# Permissions
chown -R steampipe:steampipe "$RUNTIME_DIR" "$PERSIST_DIR/data"
chmod +x "$RUNTIME_DIR/steampipe/steampipe"
chmod +x "$RUNTIME_DIR/db/14.19.0/postgres/bin/"* 2>/dev/null || true

# Environment
export STEAMPIPE_INSTALL_DIR="$RUNTIME_DIR"
export STEAMPIPE_MOD_LOCATION="$RUNTIME_DIR"
export HOME="${HOME:-/opt/steampipe}"

# Exec immediately - no delay for scanner
exec "$RUNTIME_DIR/steampipe/steampipe" service start --foreground
