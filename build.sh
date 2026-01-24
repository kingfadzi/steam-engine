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
#   ./build.sh lan --no-cache
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# Defaults
PROFILE="${1:-}"
IMAGE_NAME="steam-engine"
DOCKER_ARGS=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

usage() {
    echo "Usage: $0 <profile> [--no-cache]"
    echo ""
    echo "Profiles:"
    echo "  vpn  - Public DNS (laptop/VPN)"
    echo "  lan  - Corporate DNS (VDI/LAN)"
    echo ""
    echo "Options:"
    echo "  --no-cache  Force rebuild without cache"
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
            DOCKER_ARGS="--no-cache"
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

# Load build args from profile
load_build_args() {
    local args=""

    # Args to skip (only needed for binaries.sh, not Docker)
    local skip_args="GATEWAY_REPO GATEWAY_REF GATEWAY_BUILD_OPTS"

    # Load base args
    if [ -f "$SCRIPT_DIR/profiles/base.args" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            # Remove Windows carriage returns
            line="${line//$'\r'/}"
            # Extract key
            local key="${line%%=*}"
            # Skip non-Docker args
            [[ "$skip_args" == *"$key"* ]] && continue
            args="$args --build-arg $line"
        done < "$SCRIPT_DIR/profiles/base.args"
    fi

    # Load profile-specific args
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        line="${line//$'\r'/}"
        local key="${line%%=*}"
        [[ "$skip_args" == *"$key"* ]] && continue
        args="$args --build-arg $line"
    done < "$SCRIPT_DIR/profiles/${PROFILE}.args"

    echo "$args"
}

# Build Docker image
build_image() {
    log_info "Loading profile: $PROFILE"

    local build_args
    build_args=$(load_build_args)

    log_info "Building Docker image..."

    cd "$SCRIPT_DIR"

    # shellcheck disable=SC2086
    docker build \
        $DOCKER_ARGS \
        $build_args \
        -t "$IMAGE_NAME:$PROFILE" \
        .

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

    check_binaries
    build_image
    export_image
    prompt_wsl_import

    echo ""
    log_info "Build complete!"
}

main
