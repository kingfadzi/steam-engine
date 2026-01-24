#!/bin/bash
#
# Prepare binaries for Steam Engine WSL image
#
# This script:
# 1. Downloads artifacts if not present (requires network)
# 2. Builds steampipe bundle from artifacts
# 3. Clones and builds gateway JAR from source
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
REPO_DIR="$SCRIPT_DIR"
BINARIES_DIR="$SCRIPT_DIR/binaries"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_DIR="/tmp/steam-engine-build"

FORCE=false

# Version configuration (for steampipe bundle)
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
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Ensure directories exist
mkdir -p "$BINARIES_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$WORK_DIR"

# Download artifacts if needed
download_artifacts() {
    if [ -d "$ARTIFACTS_DIR" ] && [ -n "$(ls -A "$ARTIFACTS_DIR" 2>/dev/null)" ]; then
        echo "  Artifacts directory exists, skipping download"
        return
    fi

    log_info "Downloading artifacts..."
    "$SCRIPT_DIR/scripts/download.sh"
}

# Build steampipe bundle from artifacts
build_steampipe_bundle() {
    local bundle_name="steampipe-bundle-dev"
    local bundle_dir="$BUILD_DIR/$bundle_name"

    log_info "Building steampipe bundle..."

    # Validate artifacts
    local missing=0
    for artifact in steampipe_linux_amd64.tar.gz steampipe-plugins.tar.gz steampipe-db.tar.gz steampipe-internal.tar.gz; do
        if [ ! -f "$ARTIFACTS_DIR/$artifact" ]; then
            echo "  Missing: $artifact"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Artifacts missing. Run './scripts/download.sh' first."
        exit 1
    fi

    # Create bundle structure
    rm -rf "$bundle_dir"
    mkdir -p "$bundle_dir"/{bin,config,steampipe,db,plugins,internal}

    # Extract artifacts
    echo "  Extracting steampipe binary..."
    tar -xzf "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz" -C "$bundle_dir/steampipe"

    echo "  Extracting plugins..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$bundle_dir/plugins"

    echo "  Extracting database..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$bundle_dir/db"

    echo "  Extracting internal files..."
    tar -xzf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$bundle_dir/internal"

    # Set permissions
    chmod +x "$bundle_dir/steampipe/steampipe" 2>/dev/null || true

    # Create VERSION file
    cat > "$bundle_dir/VERSION" << EOF
Bundle Version: dev
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Steampipe: ${STEAMPIPE_VERSION}
PostgreSQL: ${POSTGRES_VERSION}
FDW: ${FDW_VERSION}
Plugins: ${PLUGINS[*]}
EOF

    # Create tarball
    local tarball="$BUILD_DIR/${bundle_name}.tgz"
    tar -czf "$tarball" -C "$bundle_dir" .

    echo "  Created: $tarball"
    echo "$tarball"
}

# Build/copy steampipe bundle
prepare_steampipe_bundle() {
    log_info "Preparing steampipe bundle..."

    local bundle="$BINARIES_DIR/steampipe-bundle.tgz"

    if [ -f "$bundle" ] && [ "$FORCE" = false ]; then
        echo "  Already exists: steampipe-bundle.tgz (use --force to rebuild)"
        return
    fi

    # Check if bundle already built
    local existing
    existing=$(find "$BUILD_DIR" -name "steampipe-bundle-*.tgz" 2>/dev/null | head -1)

    if [ -n "$existing" ] && [ "$FORCE" = false ]; then
        echo "  Copying from: $existing"
        cp "$existing" "$bundle"
    else
        # Download artifacts if needed
        download_artifacts

        # Build the bundle
        local built_bundle
        built_bundle=$(build_steampipe_bundle)

        # Copy to binaries
        cp "$built_bundle" "$bundle"
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
        log_error "No JAR file found in target/"
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
    echo "Steampipe:"
    echo "  STEAMPIPE_VERSION=$STEAMPIPE_VERSION"
    echo "  POSTGRES_VERSION=$POSTGRES_VERSION"
    echo "  PLUGINS=${PLUGINS[*]}"
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
