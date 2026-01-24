#!/bin/bash
#
# Download artifacts for Steam Engine (air-gapped deployment)
#
# This script downloads all required artifacts using oras (OCI Registry As Storage)
# and curl. No steampipe execution required - pure downloads only.
#
# Prerequisites:
#   - oras CLI: https://oras.land/docs/installation/
#   - curl
#
# Usage:
#   ./scripts/download.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$REPO_DIR/artifacts"
WORK_DIR="$(mktemp -d)"

# Version configuration (inline)
STEAMPIPE_VERSION=latest
POSTGRES_VERSION=14.19.0
FDW_VERSION=2.1.4
PLUGINS=(
  "theapsgroup/gitlab:0.6.0"
  "turbot/jira:1.1.0"
  "turbot/bitbucket:1.3.0"
)

# Cleanup on exit
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Check for required tools
check_requirements() {
  if ! command -v oras &>/dev/null; then
    echo "ERROR: oras not found."
    echo ""
    echo "Install oras with:"
    echo "  VERSION=1.3.0"
    echo "  curl -LO https://github.com/oras-project/oras/releases/download/v\${VERSION}/oras_\${VERSION}_linux_amd64.tar.gz"
    echo "  tar -zxf oras_\${VERSION}_linux_amd64.tar.gz"
    echo "  sudo mv oras /usr/local/bin/  # or ~/.local/bin/"
    echo ""
    exit 1
  fi

  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found"
    exit 1
  fi
}

# Download steampipe binary
download_steampipe() {
  echo "==> Downloading steampipe binary..."
  local url
  if [ "$STEAMPIPE_VERSION" = "latest" ]; then
    url="https://github.com/turbot/steampipe/releases/latest/download/steampipe_linux_amd64.tar.gz"
  else
    url="https://github.com/turbot/steampipe/releases/download/${STEAMPIPE_VERSION}/steampipe_linux_amd64.tar.gz"
  fi
  curl -fSL "$url" -o "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz"
  echo "    Downloaded steampipe binary"
}

# Download plugins via oras and package into expected structure
download_plugins() {
  echo "==> Downloading plugins via oras..."

  local plugins_dir="$WORK_DIR/plugins"
  mkdir -p "$plugins_dir"

  # Create versions.json structure
  local versions_json="$plugins_dir/versions.json"
  echo '{"plugins": {' > "$versions_json"
  local first=true

  for plugin_spec in "${PLUGINS[@]}"; do
    local org_name="${plugin_spec%:*}"
    local version="${plugin_spec#*:}"
    local org="${org_name%/*}"
    local name="${org_name#*/}"

    echo "    Pulling $org/$name:$version..."

    # Pull plugin via oras
    local plugin_work="$WORK_DIR/plugin-$name"
    mkdir -p "$plugin_work"
    oras pull "ghcr.io/turbot/steampipe/plugins/$org/$name:$version" -o "$plugin_work" 2>&1 | grep -v "^Skipped"

    # Create steampipe directory structure
    local plugin_dest="$plugins_dir/hub.steampipe.io/plugins/$org/$name@$version"
    mkdir -p "$plugin_dest"

    # Extract and rename the linux_amd64 binary
    local binary_gz=$(find "$plugin_work" -name "*_linux_amd64.gz" | head -1)
    if [ -n "$binary_gz" ]; then
      gunzip -c "$binary_gz" > "$plugin_dest/steampipe-plugin-$name.plugin"
      chmod +x "$plugin_dest/steampipe-plugin-$name.plugin"
    else
      echo "    WARNING: No linux_amd64 binary found for $name"
    fi

    # Copy docs if present
    if [ -d "$plugin_work/docs" ]; then
      cp -r "$plugin_work/docs" "$plugin_dest/"
    fi

    # Add to versions.json
    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$versions_json"
    fi

    # Determine the hub path format
    local hub_path="hub.steampipe.io/plugins/$org/$name@$version"
    if [ "$version" = "latest" ]; then
      hub_path="hub.steampipe.io/plugins/$org/$name@latest"
    fi

    cat >> "$versions_json" << EOF
    "$hub_path": {
      "name": "$hub_path",
      "version": "$version",
      "binary_arch": "amd64",
      "installed_from": "ghcr.io/turbot/steampipe/plugins/$org/$name:$version",
      "install_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
EOF
  done

  echo '},"struct_version": 20220411}' >> "$versions_json"

  # Package plugins tarball
  echo "    Packaging plugins..."
  tar -czf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$plugins_dir" .
  echo "    Downloaded and packaged ${#PLUGINS[@]} plugins"
}

# Download embedded postgres and FDW
download_postgres() {
  echo "==> Downloading embedded PostgreSQL $POSTGRES_VERSION..."

  local db_dir="$WORK_DIR/db/$POSTGRES_VERSION"
  mkdir -p "$db_dir"

  # Pull postgres via oras
  local pg_work="$WORK_DIR/postgres-work"
  mkdir -p "$pg_work"
  oras pull "ghcr.io/turbot/steampipe/db:$POSTGRES_VERSION" -o "$pg_work" 2>&1 | grep -v "^Skipped"

  # Copy linux_amd64 postgres
  if [ -d "$pg_work/extracted-linux-amd64" ]; then
    cp -r "$pg_work/extracted-linux-amd64" "$db_dir/postgres"
  else
    echo "ERROR: extracted-linux-amd64 not found in postgres pull"
    exit 1
  fi

  # Download FDW from GitHub releases
  echo "==> Downloading Steampipe Postgres FDW v$FDW_VERSION..."
  local fdw_base="https://github.com/turbot/steampipe-postgres-fdw/releases/download/v$FDW_VERSION"

  # Download FDW shared library
  curl -fSL "$fdw_base/steampipe_postgres_fdw.so.linux_amd64.gz" -o "$WORK_DIR/fdw.so.gz"
  gunzip -c "$WORK_DIR/fdw.so.gz" > "$db_dir/postgres/lib/postgresql/steampipe_postgres_fdw.so"
  chmod +x "$db_dir/postgres/lib/postgresql/steampipe_postgres_fdw.so"

  # Download FDW extension files
  curl -fSL "$fdw_base/steampipe_postgres_fdw--1.0.sql" \
    -o "$db_dir/postgres/share/postgresql/extension/steampipe_postgres_fdw--1.0.sql"
  curl -fSL "$fdw_base/steampipe_postgres_fdw.control" \
    -o "$db_dir/postgres/share/postgresql/extension/steampipe_postgres_fdw.control"

  # Initialize postgres data directory (empty, will be initialized on first run)
  mkdir -p "$db_dir/data"

  # Package db tarball
  echo "    Packaging database..."
  tar -czf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$WORK_DIR/db" .
  echo "    Downloaded PostgreSQL $POSTGRES_VERSION with FDW"
}

# Create internal artifacts (minimal required files)
create_internal() {
  echo "==> Creating internal artifacts..."

  local internal_dir="$WORK_DIR/internal"
  mkdir -p "$internal_dir"

  # Create minimal required files
  echo '{"versions":{}}' > "$internal_dir/available_versions.json"
  echo '{}' > "$internal_dir/update_check.json"
  echo '{}' > "$internal_dir/connection.json"
  echo "steampipe:$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)" > "$internal_dir/.passwd"

  tar -czf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$internal_dir" .
  echo "    Created internal artifacts"
}

# Main
main() {
  echo "==> Steam Engine Artifact Downloader"
  echo ""
  echo "Configuration:"
  echo "  Steampipe: $STEAMPIPE_VERSION"
  echo "  PostgreSQL: $POSTGRES_VERSION"
  echo "  FDW: $FDW_VERSION"
  echo "  Plugins: ${PLUGINS[*]}"
  echo ""

  check_requirements
  mkdir -p "$ARTIFACTS_DIR"

  download_steampipe
  download_plugins
  download_postgres
  create_internal

  echo ""
  echo "==> Artifacts saved to: $ARTIFACTS_DIR"
  ls -lh "$ARTIFACTS_DIR"
  echo ""
  echo "==> Done"
}

main "$@"
