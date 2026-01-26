#!/bin/bash
#
# Steampipe service start script
# Uses system-installed steampipe from RPM
#
set -e

# Create postgres socket directory in /tmp
mkdir -p /tmp/postgresql
export PGHOST=/tmp/postgresql

HOME_DIR="/home/fadzi"
INSTALL_DIR="$HOME_DIR/.steampipe"
DATA_DIR="$INSTALL_DIR/db/14.19.0/data"
CONF_D="$DATA_DIR/postgresql.conf.d"
SOCKET_CONF="$CONF_D/01-socket-dir.conf"

# Add socket config if conf.d exists (created by steampipe on first run)
if [ -d "$CONF_D" ] && [ ! -f "$SOCKET_CONF" ]; then
    echo "Configuring postgres socket directory..."
    echo "unix_socket_directories = '/tmp/postgresql'" > "$SOCKET_CONF"
fi

# Environment
export STEAMPIPE_INSTALL_DIR="$INSTALL_DIR"
export STEAMPIPE_UPDATE_CHECK=false
export HOME="$HOME_DIR"

# Start steampipe (uses /usr/bin/steampipe from RPM)
exec steampipe service start --foreground
