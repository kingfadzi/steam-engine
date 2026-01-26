#!/bin/bash
#
# Steampipe service start script
# Steampipe and embedded postgres are pre-built in the image
#
set -e

HOME_DIR="/home/fadzi"
INSTALL_DIR="$HOME_DIR/.steampipe"
CONF_D="$INSTALL_DIR/db/14.19.0/data/postgresql.conf.d"
SOCKET_CONF="$CONF_D/socket.conf"

# Environment
export STEAMPIPE_INSTALL_DIR="$INSTALL_DIR"
export STEAMPIPE_UPDATE_CHECK=false
export HOME="$HOME_DIR"

# If socket.conf doesn't exist, need to initialize first
if [ ! -f "$SOCKET_CONF" ]; then
    echo "First run: initializing database..."
    # Create socket dir for initial startup
    sudo mkdir -p /run/postgresql
    sudo chown fadzi:fadzi /run/postgresql

    # Start steampipe to initialize database
    steampipe service start
    steampipe service stop

    # Now add socket config for /tmp
    echo "unix_socket_directories = '/tmp'" > "$SOCKET_CONF"
    echo "Socket configured to use /tmp"
fi

# Start steampipe
exec steampipe service start --foreground
