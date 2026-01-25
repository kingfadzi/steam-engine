#!/bin/bash
#
# Build Steam Engine WSL image
#
# Usage:
#   ./build.sh <profile>
#   ./build.sh --docker-test
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
#   ./build.sh vpn --debug          # Test exported filesystem (WSL simulation)
#   ./build.sh --docker-test        # Standalone Docker test (no WSL)
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
DOCKER_TEST=false
DEBUG_MODE=false
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
    echo "       $0 --docker-test [--no-cache]"
    echo ""
    echo "Profiles:"
    echo "  vpn  - Public DNS (laptop/VPN)"
    echo "  lan  - Corporate DNS (VDI/LAN)"
    echo ""
    echo "Options:"
    echo "  --validate      Run smoke tests before export (recommended)"
    echo "  --no-cache      Force rebuild without cache"
    echo "  --rebuild-base  Force rebuild of wsl-base image"
    echo "  --debug         Test exported filesystem (simulates WSL import)"
    echo "  --docker-test   Build standalone test image (no WSL dependencies)"
    exit 1
}

# Parse arguments
# Handle --docker-test as first argument
if [ "$PROFILE" = "--docker-test" ]; then
    DOCKER_TEST=true
    PROFILE=""
    shift || true
    for arg in "$@"; do
        case $arg in
            --no-cache)
                NO_CACHE="--no-cache"
                ;;
        esac
    done
elif [ -z "$PROFILE" ]; then
    usage
else
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
            --debug)
                DEBUG_MODE=true
                ;;
            --docker-test)
                DOCKER_TEST=true
                ;;
        esac
    done
fi

# Validate profile (skip for docker-test mode)
if [ "$DOCKER_TEST" = false ]; then
    if [ ! -f "$SCRIPT_DIR/profiles/${PROFILE}.args" ]; then
        log_error "Profile not found: profiles/${PROFILE}.args"
        echo "Available profiles:"
        ls -1 "$SCRIPT_DIR/profiles/"*.args | xargs -n1 basename | sed 's/.args$//'
        exit 1
    fi
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
    local skip_args=""

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

# Copy secrets example to Windows location
setup_secrets() {
    local win_secrets_dir="${WIN_MOUNT:-/mnt/c/devhome/projects/steamengine}/secrets"
    local example_file="$SCRIPT_DIR/config/steampipe/steampipe.env.example"

    # Only run on Windows
    if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && -z "${WINDIR:-}" ]]; then
        return
    fi

    if [[ ! -d "$win_secrets_dir" ]]; then
        log_info "Creating secrets directory..."
        mkdir -p "$win_secrets_dir"
    fi

    if [[ ! -f "$win_secrets_dir/steampipe.env" ]]; then
        log_info "Copying steampipe.env.example to secrets directory..."
        cp "$example_file" "$win_secrets_dir/steampipe.env.example"
        echo "  Edit: $(cygpath -w "$win_secrets_dir/steampipe.env.example")"
        echo "  Then rename to steampipe.env"
    fi
}

# ============================================
# Docker Test Build (no WSL dependencies)
# ============================================
docker_test_build() {
    echo ""
    echo "============================================"
    echo "  Steam Engine Docker Test Build"
    echo "============================================"
    echo "  Mode: Standalone Docker (no WSL)"
    echo "  Image: steam-engine:test"
    echo "============================================"
    echo ""

    check_binaries

    log_info "Building test Docker image..."
    cd "$SCRIPT_DIR"

    docker build $NO_CACHE -f Dockerfile.test -t steam-engine:test .

    echo "  Built: steam-engine:test"

    log_info "Running validation..."
    docker compose -f docker-compose.test.yml --profile validate run --rm validate

    echo ""
    log_info "Docker test build complete!"
    echo ""
    echo "Usage:"
    echo "  docker compose -f docker-compose.test.yml up        # Start all services"
    echo "  docker compose -f docker-compose.test.yml up -d     # Start in background"
    echo "  curl http://localhost:8080/actuator/health          # Check gateway"
    echo "  pg_isready -h localhost -p 9193                     # Check steampipe"
}

# Debug mode - test exported filesystem to simulate WSL import
debug_wsl_image() {
    echo ""
    echo "============================================"
    echo "  Steam Engine WSL Debug Mode"
    echo "============================================"
    echo "  Testing exported filesystem (simulates WSL import)"
    echo "============================================"
    echo ""

    log_info "Testing exported filesystem (simulates WSL import)..."

    # Create container, export, re-import to simulate WSL
    local container_id
    container_id=$(docker create "$IMAGE_NAME:$PROFILE")
    docker export "$container_id" | docker import - "${IMAGE_NAME}:debug"
    docker rm "$container_id" > /dev/null

    # Run diagnostics on re-imported image
    log_info "Running diagnostics on exported filesystem..."
    echo ""

    docker run --rm "${IMAGE_NAME}:debug" /bin/bash -c '
        echo "=== Environment Variables ==="
        echo "STEAMPIPE_INSTALL_DIR=${STEAMPIPE_INSTALL_DIR:-NOT SET}"
        echo "STEAMPIPE_MOD_LOCATION=${STEAMPIPE_MOD_LOCATION:-NOT SET}"
        echo "HOME=${HOME:-NOT SET}"
        echo ""
        echo "=== /etc/environment ==="
        cat /etc/environment 2>/dev/null || echo "/etc/environment missing"

        echo ""
        echo "=== Steampipe Directory Structure ==="
        ls -la /opt/steampipe/ 2>/dev/null || echo "/opt/steampipe missing"

        echo ""
        echo "=== Postgres Binaries ==="
        ls -la /opt/steampipe/db/14.19.0/postgres/bin/ 2>/dev/null || echo "Postgres binaries missing"

        echo ""
        echo "=== User Configuration ==="
        id steampipe 2>/dev/null || echo "steampipe user missing"
        echo "Steampipe home: $(getent passwd steampipe 2>/dev/null | cut -d: -f6)"

        echo ""
        echo "=== Secrets Directory ==="
        ls -la /opt/wsl-secrets/ 2>/dev/null || echo "/opt/wsl-secrets missing"
        echo "fstab entry:"
        grep wsl-secrets /etc/fstab 2>/dev/null || echo "  No fstab entry for wsl-secrets"

        echo ""
        echo "=== Systemd Services ==="
        ls -la /etc/systemd/system/steampipe.service 2>/dev/null || echo "steampipe.service missing"
        ls -la /etc/systemd/system/gateway.service 2>/dev/null || echo "gateway.service missing"

        echo ""
        echo "=== Testing Steampipe Binary ==="
        # Source environment and test as steampipe user
        su - steampipe -s /bin/bash -c "
            source /etc/environment 2>/dev/null || true
            export STEAMPIPE_INSTALL_DIR=/opt/steampipe
            export HOME=/opt/steampipe
            /opt/steampipe/steampipe/steampipe --version
        " 2>&1 || echo "Steampipe binary test failed"

        echo ""
        echo "=== Validate Mounts Script Test ==="
        # Source environment for the validation script
        source /etc/environment 2>/dev/null || true
        export STEAMPIPE_INSTALL_DIR=/opt/steampipe
        /opt/init/validate-mounts.sh 2>&1 || echo "Validation script failed (expected - no Windows mount in Docker)"
    '

    # Cleanup debug image
    log_info "Cleaning up debug image..."
    docker rmi "${IMAGE_NAME}:debug" > /dev/null 2>&1 || true

    echo ""
    log_info "Debug mode complete!"
    echo ""
    echo "If all checks passed, the image should work in WSL."
    echo "To test in actual WSL:"
    echo "  wsl --import steam-engine-test C:\\wsl\\steam-engine-test ${IMAGE_NAME}-${PROFILE}.tar"
    echo "  wsl -d steam-engine-test"
}

# Prompt for WSL import (Windows only)
prompt_wsl_import() {
    local tarball="$SCRIPT_DIR/${IMAGE_NAME}-${PROFILE}.tar"
    local install_path="C:\\wsl\\$IMAGE_NAME"

    # Check if running on Windows (Git Bash / MSYS)
    if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && -z "${WINDIR:-}" ]]; then
        echo ""
        echo "To import on Windows:"
        echo "  wsl --import $IMAGE_NAME $install_path ${IMAGE_NAME}-${PROFILE}.tar --version 2"
        return
    fi

    echo ""
    read -p "Import to WSL as '$IMAGE_NAME'? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local tarball_win
        tarball_win=$(cygpath -w "$tarball")

        # Check if distro exists
        if wsl.exe --list --quiet 2>/dev/null | grep -q "^${IMAGE_NAME}$"; then
            echo "Distribution '$IMAGE_NAME' already exists."
            read -p "Unregister and replace? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Unregistering $IMAGE_NAME..."
                wsl.exe --unregister "$IMAGE_NAME"
            else
                echo "Aborted."
                return
            fi
        fi

        log_info "Importing to WSL..."
        echo "  Name: $IMAGE_NAME"
        echo "  Path: $install_path"

        # Create directory and import
        mkdir -p "$(cygpath "$install_path")" 2>/dev/null || true
        wsl.exe --import "$IMAGE_NAME" "$install_path" "$tarball_win" --version 2

        echo ""
        log_info "Import complete!"
        echo "To start: wsl -d $IMAGE_NAME"
    else
        echo ""
        echo "To import later:"
        echo "  wsl --import $IMAGE_NAME $install_path ${IMAGE_NAME}-${PROFILE}.tar --version 2"
    fi
}

# Main
main() {
    # Docker test mode - separate flow
    if [ "$DOCKER_TEST" = true ]; then
        docker_test_build
        return
    fi

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

    # Debug mode: test exported filesystem instead of normal export
    if [ "$DEBUG_MODE" = true ]; then
        debug_wsl_image
        return
    fi

    export_image
    setup_secrets
    prompt_wsl_import

    echo ""
    log_info "Build complete!"
}

main
