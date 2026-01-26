#!/bin/bash
#
# Steampipe service start with first-time initialization
#
set -e

# Create postgres socket directory in /tmp (avoids /run permission issues)
mkdir -p /tmp/postgresql
export PGHOST=/tmp/postgresql

HOME_DIR="/home/fadzi"
INSTALL_DIR="$HOME_DIR/.steampipe"
DATA_DIR="$INSTALL_DIR/db/14.19.0/data"
STAGE_DIR="$HOME_DIR/.local/share/steam-engine"
BUNDLE="$STAGE_DIR/steampipe-bundle.tgz"
SECRETS="$HOME_DIR/.secrets/steampipe.env"

# First-time setup: extract bundle if not done
if [ ! -x "$INSTALL_DIR/steampipe/steampipe" ]; then
    echo "First-time setup: extracting steampipe bundle..."
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$BUNDLE" -C "$INSTALL_DIR" --exclude='fdw'
    chmod +x "$INSTALL_DIR/steampipe/steampipe"

    # Copy config files
    if [ -d "$STAGE_DIR" ]; then
        echo "Copying steampipe config files..."
        mkdir -p "$INSTALL_DIR/config"
        cp "$STAGE_DIR"/*.spc "$INSTALL_DIR/config/" 2>/dev/null || true
    fi
fi

# Initialize database if needed
if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
    echo "Initializing postgres database..."
    mkdir -p "$DATA_DIR"
    "$INSTALL_DIR/db/14.19.0/postgres/bin/initdb" -D "$DATA_DIR"
fi

# Ensure postgres uses /tmp for socket (avoids /run permission issues)
if ! grep -q "unix_socket_directories = '/tmp/postgresql'" "$DATA_DIR/postgresql.conf" 2>/dev/null; then
    echo "Configuring postgres socket directory..."
    sed -i "s|^#*unix_socket_directories.*|unix_socket_directories = '/tmp/postgresql'|" "$DATA_DIR/postgresql.conf"
    # If sed didn't match, append it
    if ! grep -q "unix_socket_directories = '/tmp/postgresql'" "$DATA_DIR/postgresql.conf"; then
        echo "unix_socket_directories = '/tmp/postgresql'" >> "$DATA_DIR/postgresql.conf"
    fi
fi

# Check secrets
if [ ! -f "$SECRETS" ]; then
    echo "ERROR: Secrets not configured: $SECRETS"
    echo ""
    echo "Create secrets file:"
    echo "  cp $STAGE_DIR/steampipe.env.example /mnt/c/.../secrets/steampipe.env"
    echo "  # Edit with your credentials"
    echo "  wsl --shutdown && wsl -d steam-engine"
    exit 1
fi

# Source secrets
set -a
source "$SECRETS"
set +a

# Environment
export STEAMPIPE_INSTALL_DIR="$INSTALL_DIR"
export HOME="$HOME_DIR"

# Start steampipe
exec "$INSTALL_DIR/steampipe/steampipe" service start --foreground
