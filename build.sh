#!/bin/bash
#
# Build Steam Engine WSL image
#
# Usage:
#   ./build.sh <profile>
#
# Profiles:
#   vpn - Public DNS (8.8.8.8) for laptop/VPN use
#   lan - Corporate DNS for VDI/LAN use
#
# Examples:
#   ./build.sh vpn
#   ./build.sh vpn --validate
#   ./build.sh lan --no-cache
#   ./build.sh vpn --rebuild-base
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# Base image configuration
WSL_BASE_REPO="${WSL_BASE_REPO:-git@github.com:kingfadzi/wsl-base.git}"
WSL_BASE_DIR="${WSL_BASE_DIR:-$HOME/.cache/wsl-base}"
# Check sibling directory first (for local development)
WSL_BASE_LOCAL="${SCRIPT_DIR}/../wsl-base"

# Defaults
PROFILE="${1:-}"
IMAGE_NAME="steam-engine"
NO_CACHE=""
VALIDATE=false
REBUILD_BASE=false
BUILD_ARGS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

usage() {
    echo "Usage: $0 <profile> [options]"
    echo ""
    echo "Profiles:"
    echo "  vpn  - Public DNS (laptop/VPN)"
    echo "  lan  - Corporate DNS (VDI/LAN)"
    echo ""
    echo "Options:"
    echo "  --validate      Run smoke tests before export (recommended)"
    echo "  --no-cache      Force rebuild without cache"
    echo "  --rebuild-base  Force rebuild of wsl-base image"
    exit 1
}

# Parse arguments
if [ -z "$PROFILE" ]; then
    usage
fi

shift
for arg in "$@"; do
    case $arg in
        --no-cache)
            NO_CACHE="--no-cache"
            ;;
        --validate)
            VALIDATE=true
            ;;
        --rebuild-base)
            REBUILD_BASE=true
            ;;
    esac
done

# Validate profile
if [ ! -f "$SCRIPT_DIR/profiles/${PROFILE}.args" ]; then
    log_error "Profile not found: profiles/${PROFILE}.args"
    echo "Available profiles:"
    ls -1 "$SCRIPT_DIR/profiles/"*.args | xargs -n1 basename | sed 's/.args$//'
    exit 1
fi

# ============================================
# Base Image Auto-Build
# ============================================
ensure_base_image() {
    local profile="$1"
    local base_image="wsl-base:$profile"

    # Check if we need to rebuild
    if [ "$REBUILD_BASE" = true ]; then
        log_info "Forcing rebuild of base image..."
    elif docker image inspect "$base_image" >/dev/null 2>&1; then
        log_info "Base image found: $base_image"
        return 0
    else
        log_warn "Base image not found: $base_image"
    fi

    # Determine where to build from
    local base_dir=""
    if [ -d "$WSL_BASE_LOCAL/.git" ]; then
        log_info "Using local wsl-base: $WSL_BASE_LOCAL"
        base_dir="$WSL_BASE_LOCAL"
    elif [ -d "$WSL_BASE_DIR/.git" ]; then
        log_info "Using cached wsl-base: $WSL_BASE_DIR"
        git -C "$WSL_BASE_DIR" pull --ff-only 2>/dev/null || true
        base_dir="$WSL_BASE_DIR"
    else
        log_info "Cloning wsl-base repository..."
        git clone --depth 1 "$WSL_BASE_REPO" "$WSL_BASE_DIR"
        base_dir="$WSL_BASE_DIR"
    fi

    # Build base image
    log_info "Building base image..."
    cd "$base_dir"
    ./binaries.sh 2>/dev/null || true
    ./build.sh "$profile" $NO_CACHE
    cd "$SCRIPT_DIR"
}

# Check binaries exist
check_binaries() {
    log_info "Checking binaries..."

    if [ ! -f "$SCRIPT_DIR/binaries/steampipe-bundle.tgz" ]; then
        log_error "Missing: binaries/steampipe-bundle.tgz"
        echo "Run: ./binaries.sh"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/binaries/gateway.jar" ]; then
        log_error "Missing: binaries/gateway.jar"
        echo "Run: ./binaries.sh"
        exit 1
    fi

    echo "  All binaries present"
}

# Load build args from profile into BUILD_ARGS array
load_build_args() {
    local skip_args="GATEWAY_REPO GATEWAY_REF GATEWAY_BUILD_OPTS"

    # Always pass PROFILE as first arg
    BUILD_ARGS+=("--build-arg" "PROFILE=$PROFILE")

    for args_file in "$SCRIPT_DIR/profiles/base.args" "$SCRIPT_DIR/profiles/${PROFILE}.args"; do
        [ -f "$args_file" ] || continue
        while IFS= read -r line; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            local key="${line%%=*}"
            [[ "$skip_args" == *"$key"* ]] && continue
            BUILD_ARGS+=("--build-arg" "$line")
        done < "$args_file"
    done
}

# Build Docker image
build_image() {
    log_info "Loading profile: $PROFILE"
    load_build_args

    log_info "Building Docker image..."
    cd "$SCRIPT_DIR"

    docker build $NO_CACHE -t "$IMAGE_NAME:$PROFILE" "${BUILD_ARGS[@]}" .

    echo "  Built: $IMAGE_NAME:$PROFILE"
}

# Export to tarball
export_image() {
    log_info "Exporting to WSL tarball..."

    local container_id
    local tarball="$SCRIPT_DIR/${IMAGE_NAME}-${PROFILE}.tar"

    # Create container from image
    container_id=$(docker create "$IMAGE_NAME:$PROFILE")

    # Export filesystem
    docker export "$container_id" -o "$tarball"

    # Cleanup container
    docker rm "$container_id" > /dev/null

    local size
    size=$(du -h "$tarball" | cut -f1)
    echo "  Exported: $tarball ($size)"
}

# Validate image with smoke tests
validate_image() {
    log_info "Running validation tests..."

    local container_id
    local test_failed=0

    # Run container in background with sleep to keep it alive
    container_id=$(docker run -d "$IMAGE_NAME:$PROFILE" sleep infinity)

    # Test 1: Steampipe binary exists and runs (must run as steampipe user)
    echo -n "  Steampipe binary... "
    if docker exec -u steampipe "$container_id" /opt/steampipe/steampipe/steampipe --version > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 2: Gateway JAR exists
    echo -n "  Gateway JAR... "
    if docker exec "$container_id" test -f /opt/gateway/gateway.jar; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 3: Plugin configs exist
    echo -n "  Plugin configs... "
    if docker exec "$container_id" bash -c "ls /opt/steampipe/config/*.spc > /dev/null 2>&1"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 4: Gateway config exists
    echo -n "  Gateway config... "
    if docker exec "$container_id" test -f /opt/gateway/application.yml; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 5: Steampipe user exists
    echo -n "  Steampipe user... "
    if docker exec "$container_id" id steampipe > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 6: Permissions on /opt/steampipe
    echo -n "  Permissions... "
    if docker exec "$container_id" bash -c "[ \$(stat -c '%U' /opt/steampipe) = 'steampipe' ]"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 7: Systemd services configured
    echo -n "  Systemd services... "
    if docker exec "$container_id" bash -c "test -f /etc/systemd/system/steampipe.service && test -f /etc/systemd/system/gateway.service"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Test 8: Java available (inherited from base)
    echo -n "  Java runtime... "
    if docker exec "$container_id" java -version > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        test_failed=1
    fi

    # Cleanup
    docker stop "$container_id" > /dev/null 2>&1
    docker rm "$container_id" > /dev/null 2>&1

    if [ $test_failed -eq 1 ]; then
        log_error "Validation failed! Not exporting image."
        exit 1
    fi

    log_info "All validation tests passed"
}

# Prompt for WSL import (Windows only)
prompt_wsl_import() {
    # Check if running in Git Bash / MSYS
    if [ -z "${MSYSTEM:-}" ]; then
        return
    fi

    log_info "WSL Import"
    echo ""
    echo "To import into WSL, run in PowerShell:"
    echo ""
    echo "  wsl --unregister $IMAGE_NAME  # if exists"
    echo "  wsl --import $IMAGE_NAME C:\\wsl\\$IMAGE_NAME ${IMAGE_NAME}-${PROFILE}.tar"
    echo ""
    echo "Then start with:"
    echo "  wsl -d $IMAGE_NAME"
    echo ""

    read -p "Import now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local tarball
        tarball=$(wslpath -w "$SCRIPT_DIR/${IMAGE_NAME}-${PROFILE}.tar")

        # Check if distro exists
        if wsl.exe -l -q 2>/dev/null | grep -q "^${IMAGE_NAME}$"; then
            log_warn "Distro '$IMAGE_NAME' exists. Unregistering..."
            wsl.exe --unregister "$IMAGE_NAME"
        fi

        log_info "Importing WSL distro..."
        wsl.exe --import "$IMAGE_NAME" "C:\\wsl\\$IMAGE_NAME" "$tarball"

        log_info "Done! Start with: wsl -d $IMAGE_NAME"
    fi
}

# Main
main() {
    echo ""
    echo "============================================"
    echo "  Steam Engine WSL Builder"
    echo "============================================"
    echo "  Profile: $PROFILE"
    echo "  Image:   $IMAGE_NAME:$PROFILE"
    echo "============================================"
    echo ""

    ensure_base_image "$PROFILE"
    check_binaries
    build_image

    if [ "$VALIDATE" = true ]; then
        validate_image
    fi

    export_image
    prompt_wsl_import

    echo ""
    log_info "Build complete!"
}

main
