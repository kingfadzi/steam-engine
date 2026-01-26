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

# Pre-create socket config so it's ready when steampipe initializes postgres
CONF_D="$DATA_DIR/postgresql.conf.d"
SOCKET_CONF="$CONF_D/01-socket-dir.conf"
mkdir -p "$CONF_D"
echo "unix_socket_directories = '/tmp/postgresql'" > "$SOCKET_CONF"

# If postgresql.conf exists, ensure it includes conf.d
if [ -f "$DATA_DIR/postgresql.conf" ]; then
    if ! grep -q "include_dir = 'postgresql.conf.d'" "$DATA_DIR/postgresql.conf" 2>/dev/null; then
        echo "include_dir = 'postgresql.conf.d'" >> "$DATA_DIR/postgresql.conf"
    fi
fi

# Recovery: if data dir exists but steampipe role missing, recreate it
# This handles cases where initdb was run manually without steampipe's setup
PSQL="$INSTALL_DIR/db/14.19.0/postgres/bin/psql"
PG_CTL="$INSTALL_DIR/db/14.19.0/postgres/bin/pg_ctl"
if [ -f "$DATA_DIR/postgresql.conf" ]; then
    # Start postgres temporarily to check/create role
    if ! $PG_CTL status -D "$DATA_DIR" > /dev/null 2>&1; then
        echo "Starting postgres temporarily for role check..."
        $PG_CTL start -D "$DATA_DIR" -w -o "-k /tmp/postgresql" > /dev/null 2>&1
        STARTED_PG=true
    fi

    # Create steampipe role if missing
    if ! $PSQL -h /tmp/postgresql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='steampipe'" 2>/dev/null | grep -q 1; then
        echo "Creating steampipe role..."
        $PSQL -h /tmp/postgresql -d postgres -c "CREATE ROLE steampipe WITH LOGIN SUPERUSER PASSWORD 'steampipe';" 2>/dev/null || true
        $PSQL -h /tmp/postgresql -d postgres -c "CREATE DATABASE steampipe OWNER steampipe;" 2>/dev/null || true
    fi

    # Stop postgres if we started it
    if [ "$STARTED_PG" = true ]; then
        $PG_CTL stop -D "$DATA_DIR" -w > /dev/null 2>&1
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
