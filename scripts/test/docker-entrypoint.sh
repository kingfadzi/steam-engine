#!/bin/bash
#
# Docker test entrypoint for steam-engine
# Manages steampipe and gateway services without systemd
#
# Usage:
#   docker-entrypoint.sh [mode]
#
# Modes:
#   steampipe  - Start only steampipe
#   gateway    - Start only gateway
#   all        - Start both services (default)
#   validate   - Check services can start, then exit
#
set -e

SECRETS_DIR="${SECRETS_DIR:-/opt/wsl-secrets}"
STEAMPIPE_PORT="${STEAMPIPE_PORT:-9193}"
GATEWAY_PORT="${GATEWAY_PORT:-8080}"
MODE="${1:-all}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[entrypoint]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[entrypoint]${NC} $1"; }
log_error() { echo -e "${RED}[entrypoint]${NC} $1"; }

# Load all .env files from secrets directory
load_secrets() {
    log_info "Loading secrets from $SECRETS_DIR"

    for env_file in "$SECRETS_DIR"/*.env "$SECRETS_DIR"/*.env.test; do
        if [ -f "$env_file" ]; then
            log_info "  Loading: $(basename "$env_file")"
            set -a
            source "$env_file"
            set +a
        fi
    done
}

# Start steampipe in background
start_steampipe() {
    log_info "Starting steampipe..."

    export STEAMPIPE_INSTALL_DIR="${STEAMPIPE_INSTALL_DIR:-/opt/steampipe}"
    export STEAMPIPE_MOD_LOCATION="${STEAMPIPE_MOD_LOCATION:-/opt/steampipe}"
    export HOME=/opt/steampipe

    # Run as steampipe user
    su - steampipe -s /bin/bash -c "
        export STEAMPIPE_INSTALL_DIR='$STEAMPIPE_INSTALL_DIR'
        export STEAMPIPE_MOD_LOCATION='$STEAMPIPE_MOD_LOCATION'
        export STEAMPIPE_DATABASE_LISTEN='${STEAMPIPE_DATABASE_LISTEN:-network}'
        export STEAMPIPE_DATABASE_PORT='$STEAMPIPE_PORT'
        export STEAMPIPE_LOG_LEVEL='${STEAMPIPE_LOG_LEVEL:-WARN}'
        export JIRA_URL='${JIRA_URL:-}'
        export JIRA_PERSONAL_ACCESS_TOKEN='${JIRA_PERSONAL_ACCESS_TOKEN:-}'
        export GITLAB_URL='${GITLAB_URL:-}'
        export GITLAB_TOKEN='${GITLAB_TOKEN:-}'
        export BITBUCKET_URL='${BITBUCKET_URL:-}'
        export BITBUCKET_USERNAME='${BITBUCKET_USERNAME:-}'
        export BITBUCKET_PASSWORD='${BITBUCKET_PASSWORD:-}'
        /opt/steampipe/steampipe/steampipe service start --foreground
    " &
    STEAMPIPE_PID=$!
    echo $STEAMPIPE_PID > /tmp/steampipe.pid
}

# Wait for steampipe to be ready
wait_steampipe() {
    log_info "Waiting for steampipe on port $STEAMPIPE_PORT..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if pg_isready -h localhost -p "$STEAMPIPE_PORT" -q 2>/dev/null; then
            log_info "Steampipe is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "Steampipe failed to start within ${max_attempts}s"
    return 1
}

# Start gateway in background
start_gateway() {
    log_info "Starting gateway..."

    /usr/bin/java \
        -Xms256m \
        -Xmx512m \
        -Djava.security.egd=file:/dev/./urandom \
        -jar /opt/gateway/gateway.jar \
        --spring.config.location=file:/opt/gateway/application.yml &
    GATEWAY_PID=$!
    echo $GATEWAY_PID > /tmp/gateway.pid
}

# Wait for gateway to be ready
wait_gateway() {
    log_info "Waiting for gateway on port $GATEWAY_PORT..."
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "http://localhost:$GATEWAY_PORT/actuator/health" >/dev/null 2>&1; then
            log_info "Gateway is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "Gateway failed to start within ${max_attempts}s"
    return 1
}

# Graceful shutdown
shutdown() {
    log_info "Shutting down services..."

    if [ -f /tmp/gateway.pid ]; then
        kill "$(cat /tmp/gateway.pid)" 2>/dev/null || true
    fi

    if [ -f /tmp/steampipe.pid ]; then
        kill "$(cat /tmp/steampipe.pid)" 2>/dev/null || true
    fi

    exit 0
}

trap shutdown SIGTERM SIGINT

# Main
main() {
    log_info "Steam Engine Docker Entrypoint"
    log_info "Mode: $MODE"

    load_secrets

    case "$MODE" in
        steampipe)
            start_steampipe
            wait_steampipe
            wait
            ;;
        gateway)
            start_gateway
            wait_gateway
            wait
            ;;
        all)
            start_steampipe
            wait_steampipe || exit 1
            start_gateway
            wait_gateway || exit 1
            log_info "All services running"
            wait
            ;;
        validate)
            log_info "Running validation..."

            # Check steampipe binary (run as steampipe user)
            echo -n "  Steampipe binary... "
            if su - steampipe -s /bin/bash -c "/opt/steampipe/steampipe/steampipe --version" >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                exit 1
            fi

            # Check gateway JAR
            echo -n "  Gateway JAR... "
            if [ -f /opt/gateway/gateway.jar ]; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                exit 1
            fi

            # Check Java
            echo -n "  Java runtime... "
            if java -version >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                exit 1
            fi

            # Check configs
            echo -n "  Plugin configs... "
            if ls /opt/steampipe/config/*.spc >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                exit 1
            fi

            # Start services briefly to validate
            start_steampipe
            if wait_steampipe; then
                echo -e "  Steampipe startup... ${GREEN}OK${NC}"
            else
                echo -e "  Steampipe startup... ${RED}FAILED${NC}"
                exit 1
            fi

            # Verify database accepts queries
            echo -n "  Steampipe database query... "
            if psql -h localhost -p "$STEAMPIPE_PORT" -U steampipe -d steampipe -c "SELECT 1;" >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                exit 1
            fi

            log_info "Validation passed"
            shutdown
            ;;
        *)
            log_error "Unknown mode: $MODE"
            echo "Usage: docker-entrypoint.sh [steampipe|gateway|all|validate]"
            exit 1
            ;;
    esac
}

main
