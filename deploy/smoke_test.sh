#!/bin/sh
#
# Smoke Test Script for steam-engine
#

set -e

echo "Running smoke test..."

# Test steampipe query
echo "Testing Steampipe query..."
RESULT=$(docker compose exec -T steampipe steampipe query "select 1 as health_check" --output json 2>/dev/null)

if echo "$RESULT" | grep -q "health_check"; then
    echo "Smoke test PASSED"
    echo "$RESULT"
    exit 0
else
    echo "ERROR: Smoke test FAILED"
    echo "$RESULT"
    exit 1
fi
