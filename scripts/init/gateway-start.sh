#!/bin/bash
#
# Gateway service start wrapper
# Sources environment and starts Java process
#
set -e

SECRETS_DIR="/opt/wsl-secrets"
WIN_SECRETS="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"

# Create symlink to Windows secrets, or create directory if Windows folder missing
if [ ! -e "$SECRETS_DIR" ]; then
    if [ -d "$WIN_SECRETS" ]; then
        ln -sf "$WIN_SECRETS" "$SECRETS_DIR"
    else
        mkdir -p "$SECRETS_DIR"
        echo "WARNING: Windows secrets dir not found: $WIN_SECRETS"
        echo "Created empty: $SECRETS_DIR"
    fi
fi

# Source environment files
if [ -f "$SECRETS_DIR/steampipe.env" ]; then
    set -a
    source "$SECRETS_DIR/steampipe.env"
    set +a
fi
if [ -f "$SECRETS_DIR/gateway.env" ]; then
    set -a
    source "$SECRETS_DIR/gateway.env"
    set +a
fi

# Start gateway
exec /usr/bin/java \
    -Xms256m \
    -Xmx512m \
    -Djava.security.egd=file:/dev/./urandom \
    -jar /opt/gateway/gateway.jar \
    --spring.config.location=file:/opt/gateway/application.yml
