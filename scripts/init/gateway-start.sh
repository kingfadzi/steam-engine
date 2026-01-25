#!/bin/bash
#
# Gateway service start wrapper
# Sources environment and starts Java process
#
set -e

SECRETS_DIR="/opt/wsl-secrets"

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
