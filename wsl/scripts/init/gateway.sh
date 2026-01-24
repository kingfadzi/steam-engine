#!/bin/bash
#
# Gateway initialization script
# Run before gateway service starts
#
set -e

echo "Initializing Gateway..."

# Check for required environment variables
check_env() {
    local var="$1"
    local required="${2:-false}"

    if [ -z "${!var:-}" ]; then
        if [ "$required" = "true" ]; then
            echo "ERROR: Required variable $var not set"
            return 1
        else
            echo "  $var: not set (optional)"
            return 0
        fi
    fi
    echo "  $var: set"
    return 0
}

echo "Checking DW connection..."

MISSING=false

check_env "DW_HOST" "true" || MISSING=true
check_env "DW_PORT" "false"
check_env "DW_DATABASE" "true" || MISSING=true
check_env "DW_USER" "true" || MISSING=true
check_env "DW_PASSWORD" "true" || MISSING=true

if [ "$MISSING" = "true" ]; then
    echo ""
    echo "ERROR: Missing required DW configuration!"
    echo "Set environment variables in /opt/wsl-secrets/gateway.env:"
    echo "  DW_HOST=your-dw-host.com"
    echo "  DW_PORT=5432"
    echo "  DW_DATABASE=lct_data"
    echo "  DW_USER=gateway"
    echo "  DW_PASSWORD=xxx"
    exit 1
fi

# Wait for steampipe to be ready
echo "Waiting for Steampipe..."
RETRIES=30
until pg_isready -h localhost -p 9193 -U steampipe -q; do
    RETRIES=$((RETRIES - 1))
    if [ $RETRIES -eq 0 ]; then
        echo "ERROR: Steampipe not ready after 60 seconds"
        exit 1
    fi
    sleep 2
done
echo "  Steampipe ready"

# Test DW connection
echo "Testing DW connection..."
if PGPASSWORD="$DW_PASSWORD" pg_isready -h "$DW_HOST" -p "${DW_PORT:-5432}" -U "$DW_USER" -d "$DW_DATABASE" -q; then
    echo "  DW connection OK"
else
    echo "WARNING: Could not verify DW connection (may still work)"
fi

echo "Gateway initialization complete."
