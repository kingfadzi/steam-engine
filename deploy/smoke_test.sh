#!/bin/sh
#
# Smoke Test Script for steam-engine
# Tests PostgreSQL connection from outside the container
#

echo "Running smoke test..."

# Retry loop - wait up to 60 seconds for service to be ready
MAX_ATTEMPTS=12
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Testing PostgreSQL connection on port 9193..."
    RESULT=$(PGPASSWORD=steampipe psql -h localhost -p 9193 -U steampipe -d steampipe -c "SELECT 1 AS health_check" -t 2>&1) || true

    if echo "$RESULT" | grep -q "1"; then
        echo "Smoke test PASSED"
        exit 0
    fi

    echo "Not ready yet, waiting 5 seconds..."
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
done

echo "ERROR: Smoke test FAILED after $MAX_ATTEMPTS attempts"
echo "$RESULT"
exit 1
