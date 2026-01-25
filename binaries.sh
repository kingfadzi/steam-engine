#!/bin/bash
#
# Prepare binaries for Steam Engine WSL image
#
# This script:
# 1. Downloads steampipe-bundle from GitHub release
# 2. Builds gateway JAR from source
#
# Usage:
#   ./binaries.sh [--force]
#
# Environment variables (or set in profiles/base.args):
#   TLS_CA_BUNDLE      - Path to CA bundle for TLS verification
#   STEAMPIPE_BUNDLE_VERSION - Bundle version (default: v20260124)
#   GATEWAY_REPO       - Git repo URL (default: git@github.com:kingfadzi/gateway.git)
#   GATEWAY_REF        - Branch/tag/commit (default: main)
#   GATEWAY_BUILD_OPTS - Maven options (default: -DskipTests -q)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"
WORK_DIR="/tmp/steam-engine-build"

FORCE=false

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

# Configuration
STEAMPIPE_BUNDLE_VERSION="${STEAMPIPE_BUNDLE_VERSION:-v20260124}"
STEAMPIPE_BUNDLE_URL="https://github.com/kingfadzi/steampipe-bundler/releases/download/${STEAMPIPE_BUNDLE_VERSION}/steampipe-bundle-${STEAMPIPE_BUNDLE_VERSION#v}.tgz"

GATEWAY_REPO="${GATEWAY_REPO:-git@github.com:kingfadzi/gateway.git}"
GATEWAY_REF="${GATEWAY_REF:-main}"
GATEWAY_BUILD_OPTS="${GATEWAY_BUILD_OPTS:--DskipTests -q}"

# TLS CA Bundle (for corporate environments)
TLS_CA_BUNDLE="${TLS_CA_BUNDLE:-}"
CURL_TLS_OPTS=()

setup_tls() {
    if [ -n "$TLS_CA_BUNDLE" ]; then
        if [ -f "$TLS_CA_BUNDLE" ]; then
            CURL_TLS_OPTS=("--cacert" "$TLS_CA_BUNDLE")
            export SSL_CERT_FILE="$TLS_CA_BUNDLE"
        else
            echo -e "\033[0;31mERROR:\033[0m TLS_CA_BUNDLE set but file not found: $TLS_CA_BUNDLE"
            exit 1
        fi
    fi
}

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }

# Ensure directories exist
mkdir -p "$BINARIES_DIR" "$WORK_DIR"

# ============================================
# Steampipe Bundle (from GitHub Release)
# ============================================

download_steampipe_bundle() {
    log_info "Downloading steampipe bundle..."
    echo "  Version: $STEAMPIPE_BUNDLE_VERSION"
    echo "  URL: $STEAMPIPE_BUNDLE_URL"

    local bundle="$BINARIES_DIR/steampipe-bundle.tgz"

    if [ -f "$bundle" ] && [ "$FORCE" = false ]; then
        echo "  Already exists: steampipe-bundle.tgz (use --force to re-download)"
        return
    fi

    setup_tls
    curl -fL# "${CURL_TLS_OPTS[@]}" "$STEAMPIPE_BUNDLE_URL" -o "$bundle"

    local size
    size=$(du -h "$bundle" | cut -f1)
    echo "  Downloaded: steampipe-bundle.tgz ($size)"
}

# ============================================
# Gateway JAR (build from source)
# ============================================

build_gateway_jar() {
    log_info "Building gateway JAR..."
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
        echo -e "\033[0;31mERROR:\033[0m No JAR file found in target/"
        exit 1
    fi

    cp "$built_jar" "$jar"

    local size
    size=$(du -h "$jar" | cut -f1)
    echo "  Built: gateway.jar ($size)"
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
    echo "Steampipe Bundle:"
    echo "  Version: $STEAMPIPE_BUNDLE_VERSION"
    echo ""
    echo "Gateway:"
    echo "  GATEWAY_REPO=$GATEWAY_REPO"
    echo "  GATEWAY_REF=$GATEWAY_REF"
    echo ""

    download_steampipe_bundle
    echo ""
    build_gateway_jar

    echo ""
    log_info "All binaries ready in: $BINARIES_DIR"
    ls -lh "$BINARIES_DIR"
}

main
