#!/bin/bash
#
# Install Steampipe natively on RHEL/AlmaLinux/WSL
#
# This script installs steampipe and all artifacts to the local system.
# No Docker required - runs steampipe directly.
#
# Usage:
#   ./install-native.sh                    # Install to ~/.steampipe, binary to ~/.local/bin
#   sudo ./install-native.sh               # Install to ~/.steampipe, binary to /usr/local/bin
#   STEAMPIPE_INSTALL_DIR=/opt/steampipe ./install-native.sh  # Custom install dir
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_DIR/artifacts}"
STEAMPIPE_INSTALL_DIR="${STEAMPIPE_INSTALL_DIR:-$HOME/.steampipe}"

# Determine binary install location
if [ "$(id -u)" -eq 0 ]; then
  BIN_DIR="/usr/local/bin"
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi

# Required artifacts
REQUIRED_FILES=(
  "steampipe_linux_amd64.tar.gz"
  "steampipe-db.tar.gz"
  "steampipe-internal.tar.gz"
  "steampipe-plugins.tar.gz"
)

# Verify artifacts exist
verify_artifacts() {
  echo "==> Verifying artifacts..."
  local missing=0

  for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$ARTIFACTS_DIR/$file" ]; then
      echo "    MISSING: $file"
      missing=1
    else
      echo "    OK: $file"
    fi
  done

  if [ $missing -eq 1 ]; then
    echo ""
    echo "ERROR: Missing artifacts. Run scripts/download.sh first."
    exit 1
  fi
}

# Install steampipe binary
install_binary() {
  echo "==> Installing steampipe binary to $BIN_DIR..."
  tar -xzf "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz" -C "$BIN_DIR"
  chmod +x "$BIN_DIR/steampipe"

  # Add to PATH hint if installing to ~/.local/bin
  if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
      echo ""
      echo "    NOTE: Add ~/.local/bin to your PATH:"
      echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo ""
    fi
  fi
}

# Install plugins
install_plugins() {
  echo "==> Installing plugins to $STEAMPIPE_INSTALL_DIR/plugins..."
  mkdir -p "$STEAMPIPE_INSTALL_DIR/plugins"
  tar -xzf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$STEAMPIPE_INSTALL_DIR/plugins"
}

# Install embedded postgres
install_db() {
  echo "==> Installing embedded PostgreSQL to $STEAMPIPE_INSTALL_DIR/db..."
  mkdir -p "$STEAMPIPE_INSTALL_DIR/db"
  tar -xzf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$STEAMPIPE_INSTALL_DIR/db"
}

# Install internal files
install_internal() {
  echo "==> Installing internal files to $STEAMPIPE_INSTALL_DIR/internal..."
  mkdir -p "$STEAMPIPE_INSTALL_DIR/internal"
  tar -xzf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$STEAMPIPE_INSTALL_DIR/internal"
}

# Setup config directory
setup_config() {
  echo "==> Setting up config directory..."
  mkdir -p "$STEAMPIPE_INSTALL_DIR/config"

  # Copy example configs if config directory in repo exists
  if [ -d "$REPO_DIR/config" ]; then
    for spc in "$REPO_DIR/config"/*.spc; do
      if [ -f "$spc" ]; then
        local basename=$(basename "$spc")
        if [ ! -f "$STEAMPIPE_INSTALL_DIR/config/$basename" ]; then
          cp "$spc" "$STEAMPIPE_INSTALL_DIR/config/"
          echo "    Copied $basename (edit with your credentials)"
        else
          echo "    Skipped $basename (already exists)"
        fi
      fi
    done
  fi
}

# Verify installation
verify_install() {
  echo ""
  echo "==> Verifying installation..."

  # Check binary
  if command -v steampipe &>/dev/null; then
    echo "    Steampipe binary: OK ($(steampipe --version 2>/dev/null | head -1))"
  elif [ -x "$BIN_DIR/steampipe" ]; then
    echo "    Steampipe binary: OK ($BIN_DIR/steampipe)"
    echo "    NOTE: steampipe not in PATH, use full path or add $BIN_DIR to PATH"
  else
    echo "    Steampipe binary: FAILED"
    return 1
  fi

  # Check directories
  for dir in plugins db internal config; do
    if [ -d "$STEAMPIPE_INSTALL_DIR/$dir" ]; then
      echo "    $STEAMPIPE_INSTALL_DIR/$dir: OK"
    else
      echo "    $STEAMPIPE_INSTALL_DIR/$dir: MISSING"
    fi
  done
}

# Main
main() {
  echo "==> Steam Engine Native Installer"
  echo ""
  echo "Configuration:"
  echo "  Artifacts: $ARTIFACTS_DIR"
  echo "  Install dir: $STEAMPIPE_INSTALL_DIR"
  echo "  Binary dir: $BIN_DIR"
  echo ""

  verify_artifacts
  install_binary
  install_plugins
  install_db
  install_internal
  setup_config
  verify_install

  echo ""
  echo "==> Installation complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Edit config files in $STEAMPIPE_INSTALL_DIR/config/"
  echo "  2. Start the service: scripts/run-native.sh"
  echo "  3. Or run queries: steampipe query"
}

main "$@"
