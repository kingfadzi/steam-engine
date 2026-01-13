#!/bin/sh
#
# Stop Script for steam-engine
#

set -e

echo "Stopping steam-engine..."
docker compose down 2>/dev/null || true
echo "Stopped."
