#!/bin/bash
#
# Start Steampipe service natively (no Docker)
#
# Usage:
#   ./run-native.sh              # Start in background
#   ./run-native.sh --foreground # Start in foreground
#
set -e

FOREGROUND=false
if [ "$1" = "--foreground" ] || [ "$1" = "-f" ]; then
  FOREGROUND=true
fi

echo "==> Starting Steampipe service..."

# Check steampipe is installed
if ! command -v steampipe &>/dev/null; then
  if [ -x "$HOME/.local/bin/steampipe" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  else
    echo "ERROR: steampipe not found. Run scripts/install-native.sh first."
    exit 1
  fi
fi

# Start service
if [ "$FOREGROUND" = true ]; then
  echo "Starting in foreground mode (Ctrl+C to stop)..."
  steampipe service start --database-listen=network --database-port=9193 --foreground
else
  steampipe service start --database-listen=network --database-port=9193

  echo ""
  echo "Steampipe service started on port 9193"
  echo ""
  echo "Connect with:"
  echo "  psql -h localhost -p 9193 -U steampipe -d steampipe"
  echo ""
  echo "Stop with:"
  echo "  scripts/stop-native.sh"
  echo "  # or: steampipe service stop"
fi
