#!/bin/bash
#
# Stop Steampipe service (native mode)
#
set -e

echo "==> Stopping Steampipe service..."

# Check steampipe is installed
if ! command -v steampipe &>/dev/null; then
  if [ -x "$HOME/.local/bin/steampipe" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if command -v steampipe &>/dev/null; then
  steampipe service stop 2>/dev/null || echo "Service was not running"
  echo "Stopped."
else
  echo "steampipe not found in PATH"
  exit 1
fi
