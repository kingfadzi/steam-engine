#!/bin/bash
#
# Steampipe service start with first-time initialization
#
set -e

# Create postgres socket directory in /tmp
# /run/postgresql is created by systemd ExecStartPre (as root)
# /tmp/postgresql is used for the actual service (configured via conf.d)
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

# Steampipe's postgresql.conf already includes 'include_dir = postgresql.conf.d'
# We just need to put our socket config there. The conf.d dir is created by
# steampipe's writePGConf() before postgres starts.
#
# On first install, our pre-created files get deleted. But after first failed
# start, the conf.d exists and we can add our config for subsequent starts.

CONF_D="$DATA_DIR/postgresql.conf.d"
SOCKET_CONF="$CONF_D/01-socket-dir.conf"

# If conf.d exists (from previous steampipe run), add our socket config
if [ -d "$CONF_D" ] && [ ! -f "$SOCKET_CONF" ]; then
    echo "Configuring postgres socket directory..."
    echo "unix_socket_directories = '/tmp/postgresql'" > "$SOCKET_CONF"
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
export STEAMPIPE_UPDATE_CHECK=false
export HOME="$HOME_DIR"

# Start steampipe
exec "$INSTALL_DIR/steampipe/steampipe" service start --foreground
