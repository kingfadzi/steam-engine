#!/bin/sh
#
# Smoke Test Script for steam-engine
# Tests PostgreSQL connection from outside the container
#

set -e

echo "Running smoke test..."

# Test connection to steampipe on port 9193
echo "Testing PostgreSQL connection on port 9193..."
RESULT=$(PGPASSWORD=steampipe psql -h localhost -p 9193 -U steampipe -d steampipe -c "SELECT 1 AS health_check" -t 2>&1) || true

if echo "$RESULT" | grep -q "1"; then
    echo "Smoke test PASSED"
    exit 0
else
    echo "ERROR: Smoke test FAILED"
    echo "$RESULT"
    exit 1
fi
