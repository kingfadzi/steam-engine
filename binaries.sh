#!/bin/bash
#
# Prepare binaries for Steam Engine WSL image
#
# This script:
# 1. Downloads artifacts if not present (requires oras, curl)
# 2. Builds steampipe bundle from artifacts
# 3. Clones and builds gateway JAR from source
#
# Usage:
#   ./binaries.sh [--force]
#
# Environment variables (or set in profiles/base.args):
#   TLS_CA_BUNDLE      - Path to CA bundle for TLS verification (corporate environments)
#   GATEWAY_REPO       - Git repo URL (default: git@github.com:kingfadzi/gateway.git)
#   GATEWAY_REF        - Branch/tag/commit (default: main)
#   GATEWAY_BUILD_OPTS - Maven options (default: -DskipTests -q)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_DIR="/tmp/steam-engine-build"

FORCE=false

# Version configuration
STEAMPIPE_VERSION=latest
POSTGRES_VERSION=14.19.0
FDW_VERSION=2.1.4
PLUGINS=(
  "theapsgroup/gitlab:0.6.0"
  "turbot/jira:1.1.0"
  "turbot/bitbucket:1.3.0"
)

# Parse args
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            ;;
    esac
done

# Load config from base.args if not set in environment
load_config() {
    local args_file="$SCRIPT_DIR/profiles/base.args"
    [ -f "$args_file" ] || return

    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        line="${line//$'\r'/}"
        local key="${line%%=*}"
        local value="${line#*=}"
        if [ -z "${!key:-}" ]; then
            export "$key=$value"
        fi
    done < "$args_file"
}

load_config

GATEWAY_REPO="${GATEWAY_REPO:-git@github.com:kingfadzi/gateway.git}"
GATEWAY_REF="${GATEWAY_REF:-main}"
GATEWAY_BUILD_OPTS="${GATEWAY_BUILD_OPTS:--DskipTests -q}"

# TLS CA Bundle (for corporate environments)
TLS_CA_BUNDLE="${TLS_CA_BUNDLE:-}"
TLS_WARNING_SHOWN=false

setup_tls() {
    if [ -n "$TLS_CA_BUNDLE" ]; then
        if [ -f "$TLS_CA_BUNDLE" ]; then
            export SSL_CERT_FILE="$TLS_CA_BUNDLE"
        else
            echo -e "\033[0;31mERROR:\033[0m TLS_CA_BUNDLE set but file not found: $TLS_CA_BUNDLE"
            exit 1
        fi
    else
        if [ "$TLS_WARNING_SHOWN" = false ]; then
            echo -e "\033[1;33mWARNING:\033[0m TLS_CA_BUNDLE not set - using system certificates"
            TLS_WARNING_SHOWN=true
        fi
    fi
}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Ensure directories exist
mkdir -p "$BINARIES_DIR" "$BUILD_DIR" "$WORK_DIR" "$ARTIFACTS_DIR"

# ============================================
# Artifact Download Functions
# ============================================

check_download_requirements() {
    if ! command -v oras &>/dev/null; then
        log_error "oras not found."
        echo ""
        echo "Install oras:"
        echo "  VERSION=1.3.0"
        echo "  curl -LO https://github.com/oras-project/oras/releases/download/v\${VERSION}/oras_\${VERSION}_linux_amd64.tar.gz"
        echo "  tar -zxf oras_\${VERSION}_linux_amd64.tar.gz"
        echo "  sudo mv oras /usr/local/bin/"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log_error "curl not found"
        exit 1
    fi
}

download_steampipe() {
    echo "  Downloading steampipe binary..."
    local url
    if [ "$STEAMPIPE_VERSION" = "latest" ]; then
        url="https://github.com/turbot/steampipe/releases/latest/download/steampipe_linux_amd64.tar.gz"
    else
        url="https://github.com/turbot/steampipe/releases/download/${STEAMPIPE_VERSION}/steampipe_linux_amd64.tar.gz"
    fi
    curl -fSL "$url" -o "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz"
}

download_plugins() {
    echo "  Downloading plugins via oras..."

    local plugins_dir="$WORK_DIR/plugins"
    mkdir -p "$plugins_dir"

    local versions_json="$plugins_dir/versions.json"
    echo '{"plugins": {' > "$versions_json"
    local first=true

    for plugin_spec in "${PLUGINS[@]}"; do
        local org_name="${plugin_spec%:*}"
        local version="${plugin_spec#*:}"
        local org="${org_name%/*}"
        local name="${org_name#*/}"

        echo "    Pulling $org/$name:$version..."

        local plugin_work="$WORK_DIR/plugin-$name"
        mkdir -p "$plugin_work"
        oras pull "ghcr.io/turbot/steampipe/plugins/$org/$name:$version" -o "$plugin_work" 2>&1 | grep -v "^Skipped" || true

        local plugin_dest="$plugins_dir/hub.steampipe.io/plugins/$org/$name@$version"
        mkdir -p "$plugin_dest"

        local binary_gz=$(find "$plugin_work" -name "*_linux_amd64.gz" | head -1)
        if [ -n "$binary_gz" ]; then
            gunzip -c "$binary_gz" > "$plugin_dest/steampipe-plugin-$name.plugin"
            chmod +x "$plugin_dest/steampipe-plugin-$name.plugin"
        else
            echo "    WARNING: No linux_amd64 binary found for $name"
        fi

        [ -d "$plugin_work/docs" ] && cp -r "$plugin_work/docs" "$plugin_dest/"

        [ "$first" = true ] && first=false || echo "," >> "$versions_json"

        local hub_path="hub.steampipe.io/plugins/$org/$name@$version"
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
    tar -czf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$plugins_dir" .
}

download_postgres() {
    echo "  Downloading PostgreSQL $POSTGRES_VERSION..."

    local db_dir="$WORK_DIR/db/$POSTGRES_VERSION"
    mkdir -p "$db_dir"

    local pg_work="$WORK_DIR/postgres-work"
    mkdir -p "$pg_work"
    oras pull "ghcr.io/turbot/steampipe/db:$POSTGRES_VERSION" -o "$pg_work" 2>&1 | grep -v "^Skipped" || true

    if [ -d "$pg_work/extracted-linux-amd64" ]; then
        cp -r "$pg_work/extracted-linux-amd64" "$db_dir/postgres"
    else
        log_error "extracted-linux-amd64 not found in postgres pull"
        exit 1
    fi

    echo "  Downloading FDW v$FDW_VERSION..."
    local fdw_base="https://github.com/turbot/steampipe-postgres-fdw/releases/download/v$FDW_VERSION"

    curl -fSL "$fdw_base/steampipe_postgres_fdw.so.linux_amd64.gz" -o "$WORK_DIR/fdw.so.gz"
    gunzip -c "$WORK_DIR/fdw.so.gz" > "$db_dir/postgres/lib/postgresql/steampipe_postgres_fdw.so"
    chmod +x "$db_dir/postgres/lib/postgresql/steampipe_postgres_fdw.so"

    curl -fSL "$fdw_base/steampipe_postgres_fdw--1.0.sql" \
        -o "$db_dir/postgres/share/postgresql/extension/steampipe_postgres_fdw--1.0.sql"
    curl -fSL "$fdw_base/steampipe_postgres_fdw.control" \
        -o "$db_dir/postgres/share/postgresql/extension/steampipe_postgres_fdw.control"

    mkdir -p "$db_dir/data"
    tar -czf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$WORK_DIR/db" .
}

create_internal() {
    echo "  Creating internal artifacts..."

    local internal_dir="$WORK_DIR/internal"
    mkdir -p "$internal_dir"

    echo '{"versions":{}}' > "$internal_dir/available_versions.json"
    echo '{}' > "$internal_dir/update_check.json"
    echo '{}' > "$internal_dir/connection.json"
    echo "steampipe:$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)" > "$internal_dir/.passwd"

    tar -czf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$internal_dir" .
}

download_artifacts() {
    if [ -d "$ARTIFACTS_DIR" ] && [ -n "$(ls -A "$ARTIFACTS_DIR" 2>/dev/null)" ] && [ "$FORCE" = false ]; then
        echo "  Artifacts exist, skipping download (use --force to re-download)"
        return
    fi

    setup_tls
    check_download_requirements
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"

    download_steampipe
    download_plugins
    download_postgres
    create_internal

    rm -rf "$WORK_DIR"
}

# ============================================
# Bundle Build Functions
# ============================================

build_steampipe_bundle() {
    local bundle_name="steampipe-bundle-dev"
    local bundle_dir="$BUILD_DIR/$bundle_name"

    log_info "Building steampipe bundle..."

    local missing=0
    for artifact in steampipe_linux_amd64.tar.gz steampipe-plugins.tar.gz steampipe-db.tar.gz steampipe-internal.tar.gz; do
        if [ ! -f "$ARTIFACTS_DIR/$artifact" ]; then
            echo "  Missing: $artifact"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Artifacts missing."
        exit 1
    fi

    rm -rf "$bundle_dir"
    mkdir -p "$bundle_dir"/{bin,config,steampipe,db,plugins,internal}

    echo "  Extracting steampipe binary..."
    tar -xzf "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz" -C "$bundle_dir/steampipe"

    echo "  Extracting plugins..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$bundle_dir/plugins"

    echo "  Extracting database..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$bundle_dir/db"

    echo "  Extracting internal files..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$bundle_dir/internal"

    chmod +x "$bundle_dir/steampipe/steampipe" 2>/dev/null || true

    cat > "$bundle_dir/VERSION" << EOF
Bundle Version: dev
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Steampipe: ${STEAMPIPE_VERSION}
PostgreSQL: ${POSTGRES_VERSION}
FDW: ${FDW_VERSION}
Plugins: ${PLUGINS[*]}
EOF

    local tarball="$BUILD_DIR/${bundle_name}.tgz"
    tar -czf "$tarball" -C "$bundle_dir" .

    local size
    size=$(du -h "$tarball" | cut -f1)
    echo "  Created: $tarball ($size)"
}

prepare_steampipe_bundle() {
    log_info "Preparing steampipe bundle..."

    local bundle="$BINARIES_DIR/steampipe-bundle.tgz"

    if [ -f "$bundle" ] && [ "$FORCE" = false ]; then
        echo "  Already exists: steampipe-bundle.tgz (use --force to rebuild)"
        return
    fi

    download_artifacts
    build_steampipe_bundle

    cp "$BUILD_DIR/steampipe-bundle-dev.tgz" "$bundle"

    local size
    size=$(du -h "$bundle" | cut -f1)
    echo "  Ready: steampipe-bundle.tgz ($size)"
}

prepare_gateway_jar() {
    log_info "Preparing gateway JAR..."
    echo "  Repo: $GATEWAY_REPO"
    echo "  Ref:  $GATEWAY_REF"

    local jar="$BINARIES_DIR/gateway.jar"
    local gateway_dir="$WORK_DIR/gateway"

    if [ -f "$jar" ] && [ "$FORCE" = false ]; then
        echo "  Already exists: gateway.jar (use --force to rebuild)"
        return
    fi

    rm -rf "$gateway_dir"

    echo "  Cloning repository..."
    git clone --depth 1 --branch "$GATEWAY_REF" "$GATEWAY_REPO" "$gateway_dir" 2>&1 | sed 's/^/    /'

    echo "  Building JAR..."
    cd "$gateway_dir"

    if [ -f "./mvnw" ]; then
        chmod +x ./mvnw
        ./mvnw clean package $GATEWAY_BUILD_OPTS 2>&1 | tail -5 | sed 's/^/    /'
    else
        mvn clean package $GATEWAY_BUILD_OPTS 2>&1 | tail -5 | sed 's/^/    /'
    fi

    local built_jar
    built_jar=$(find "$gateway_dir/target" -maxdepth 1 -name "*.jar" \
        -not -name "*-sources.jar" \
        -not -name "*-javadoc.jar" \
        -not -name "*.original" \
        2>/dev/null | head -1)

    if [ -z "$built_jar" ]; then
        log_error "No JAR file found in target/"
        exit 1
    fi

    cp "$built_jar" "$jar"

    local size
    size=$(du -h "$jar" | cut -f1)
    echo "  Ready: gateway.jar ($size)"
}

# ============================================
# Main
# ============================================

main() {
    echo ""
    echo "============================================"
    echo "  Steam Engine Binaries"
    echo "============================================"
    echo ""
    if [ -n "$TLS_CA_BUNDLE" ]; then
        echo "TLS: $TLS_CA_BUNDLE"
    else
        echo "TLS: (system certificates)"
    fi
    echo ""
    echo "Steampipe:"
    echo "  STEAMPIPE_VERSION=$STEAMPIPE_VERSION"
    echo "  POSTGRES_VERSION=$POSTGRES_VERSION"
    echo "  PLUGINS=${PLUGINS[*]}"
    echo ""
    echo "Gateway:"
    echo "  GATEWAY_REPO=$GATEWAY_REPO"
    echo "  GATEWAY_REF=$GATEWAY_REF"
    echo ""

    prepare_steampipe_bundle
    echo ""
    prepare_gateway_jar

    echo ""
    log_info "All binaries ready in: $BINARIES_DIR"
    ls -lh "$BINARIES_DIR"
}

main
