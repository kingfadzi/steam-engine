#!/bin/bash
#
# Download/prepare binaries for Steam Engine WSL image
#
# This script:
# 1. Builds steampipe bundle (or copies existing)
# 2. Clones and builds gateway JAR from source
#
# Usage:
#   ./binaries.sh [--force]
#
# Environment variables (or set in profiles/base.args):
#   GATEWAY_REPO       - Git repo URL (default: git@github.com:kingfadzi/gateway.git)
#   GATEWAY_REF        - Branch/tag/commit (default: main)
#   GATEWAY_BUILD_OPTS - Maven options (default: -DskipTests -q)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
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

    if [ -f "$args_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            # Remove Windows carriage returns
            line="${line//$'\r'/}"

            # Extract key=value
            local key="${line%%=*}"
            local value="${line#*=}"

            # Only set if not already in environment
            if [ -z "${!key:-}" ]; then
                export "$key=$value"
            fi
        done < "$args_file"
    fi
}

# Defaults (can be overridden by environment or base.args)
load_config

GATEWAY_REPO="${GATEWAY_REPO:-git@github.com:kingfadzi/gateway.git}"
GATEWAY_REF="${GATEWAY_REF:-main}"
GATEWAY_BUILD_OPTS="${GATEWAY_BUILD_OPTS:--DskipTests -q}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }

# Ensure directories exist
mkdir -p "$BINARIES_DIR"
mkdir -p "$WORK_DIR"

# Build/copy steampipe bundle
prepare_steampipe_bundle() {
    log_info "Preparing steampipe bundle..."

    local bundle="$BINARIES_DIR/steampipe-bundle.tgz"

    if [ -f "$bundle" ] && [ "$FORCE" = false ]; then
        echo "  Already exists: steampipe-bundle.tgz (use --force to rebuild)"
        return
    fi

    # Check if bundle already built in parent repo
    local existing
    existing=$(find "$REPO_DIR/build" -name "steampipe-bundle-*.tgz" 2>/dev/null | head -1)

    if [ -n "$existing" ]; then
        echo "  Copying from: $existing"
        cp "$existing" "$bundle"
    else
        # Build the bundle
        echo "  Building bundle..."
        cd "$REPO_DIR"

        # Download artifacts if needed
        if [ ! -d "$REPO_DIR/artifacts" ] || [ -z "$(ls -A "$REPO_DIR/artifacts" 2>/dev/null)" ]; then
            echo "  Downloading artifacts..."
            ./scripts/download.sh
        fi

        # Build bundle
        ./build_steampipe_bundle.sh

        # Copy to binaries
        existing=$(find "$REPO_DIR/build" -name "steampipe-bundle-*.tgz" | head -1)
        cp "$existing" "$bundle"
    fi

    local size
    size=$(du -h "$bundle" | cut -f1)
    echo "  Ready: steampipe-bundle.tgz ($size)"
}

# Clone and build gateway JAR
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

    # Clean previous build
    rm -rf "$gateway_dir"

    # Clone repository
    echo "  Cloning repository..."
    git clone --depth 1 --branch "$GATEWAY_REF" "$GATEWAY_REPO" "$gateway_dir" 2>&1 | sed 's/^/    /'

    # Build with Maven
    echo "  Building JAR..."
    cd "$gateway_dir"

    if [ -f "./mvnw" ]; then
        chmod +x ./mvnw
        # shellcheck disable=SC2086
        ./mvnw clean package $GATEWAY_BUILD_OPTS 2>&1 | tail -5 | sed 's/^/    /'
    else
        # shellcheck disable=SC2086
        mvn clean package $GATEWAY_BUILD_OPTS 2>&1 | tail -5 | sed 's/^/    /'
    fi

    # Find and copy JAR (look for any Spring Boot JAR, excluding sources/javadoc/original)
    local built_jar
    built_jar=$(find "$gateway_dir/target" -maxdepth 1 -name "*.jar" \
        -not -name "*-sources.jar" \
        -not -name "*-javadoc.jar" \
        -not -name "*.original" \
        2>/dev/null | head -1)

    if [ -z "$built_jar" ]; then
        echo "  ERROR: No JAR file found in target/"
        exit 1
    fi

    cp "$built_jar" "$jar"

    local size
    size=$(du -h "$jar" | cut -f1)
    echo "  Ready: gateway.jar ($size)"
}

# Main
main() {
    echo ""
    echo "============================================"
    echo "  Steam Engine Binaries"
    echo "============================================"
    echo ""
    echo "Gateway:"
    echo "  GATEWAY_REPO=$GATEWAY_REPO"
    echo "  GATEWAY_REF=$GATEWAY_REF"
    echo "  GATEWAY_BUILD_OPTS=$GATEWAY_BUILD_OPTS"
    echo ""

    prepare_steampipe_bundle
    echo ""
    prepare_gateway_jar

    echo ""
    log_info "All binaries ready in: $BINARIES_DIR"
    ls -lh "$BINARIES_DIR"
}

main
