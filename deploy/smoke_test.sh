#!/bin/bash
set -e

APP_DIR="${BASE_DIR:-/apps/data/steam-engine}"
cd "$APP_DIR"

echo "==> Running smoke test..."

# Check container is running
if ! docker compose ps -q 2>/dev/null | grep -q .; then
    echo "ERROR: Container not running"
    exit 1
fi

# Test steampipe query
echo "==> Testing Steampipe query..."
RESULT=$(docker compose exec -T steampipe steampipe query "select 1 as health_check" --output json 2>/dev/null)

if echo "$RESULT" | grep -q "health_check"; then
    echo "==> Smoke test PASSED"
    echo "$RESULT"
    exit 0
else
    echo "ERROR: Smoke test FAILED"
    echo "$RESULT"
    exit 1
fi
