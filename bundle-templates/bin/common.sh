#!/bin/bash
#
# common.sh - Shared setup for steampipe bundle scripts
#
# This script is sourced by other scripts in bin/. It:
# - Determines ROOT_DIR relative to script location
# - Loads steampipe.env if present
# - Sets STEAMPIPE_INSTALL_DIR
# - Validates config directory exists
# - Exports PATH to include steampipe binary
#
# Note: Steampipe reads configs from $STEAMPIPE_INSTALL_DIR/config/
#       Edit .spc files there directly, or symlink to external location.
#

# Determine bundle root directory (parent of bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment config if present
if [ -f "$ROOT_DIR/steampipe.env" ]; then
  set -a
  source "$ROOT_DIR/steampipe.env"
  set +a
fi

# Set steampipe install directory to bundle root
export STEAMPIPE_INSTALL_DIR="$ROOT_DIR"

# Config directory is always $INSTALL_DIR/config (steampipe requirement)
CONFIG_DIR="$ROOT_DIR/config"

# Set log level (default: warn)
export STEAMPIPE_LOG_LEVEL="${STEAMPIPE_LOG_LEVEL:-warn}"

# Set database port (default: 9193)
export STEAMPIPE_DATABASE_PORT="${STEAMPIPE_DATABASE_PORT:-9193}"

# Add steampipe binary to PATH
export PATH="$ROOT_DIR/steampipe:$PATH"

# Ensure config directory exists
ensure_config_dir() {
  if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
  fi
}

# Validate config has .spc files
validate_config() {
  ensure_config_dir

  # Check if there are any .spc files
  local spc_count=$(find "$CONFIG_DIR" -name "*.spc" 2>/dev/null | wc -l)
  if [ "$spc_count" -eq 0 ]; then
    echo "WARNING: No .spc config files found in $CONFIG_DIR"
    echo "         Copy templates: cp $ROOT_DIR/config-templates/*.spc $CONFIG_DIR/"
  fi
}

# Show configuration summary
show_config() {
  echo "Configuration:"
  echo "  STEAMPIPE_INSTALL_DIR: $STEAMPIPE_INSTALL_DIR"
  echo "  Config directory: $CONFIG_DIR"
  echo "  STEAMPIPE_DATABASE_PORT: $STEAMPIPE_DATABASE_PORT"
  echo "  STEAMPIPE_LOG_LEVEL: $STEAMPIPE_LOG_LEVEL"
}
