#!/bin/bash
#
# run-test.sh - Test steampipe bundle deployment in AlmaLinux 9 container
#
# This script:
# 1. Builds the bundle (if not already built)
# 2. Extracts bundle into test/bundle/
# 3. Creates minimal test configs
# 4. Builds and runs AlmaLinux 9 container
# 5. Waits for steampipe to be healthy
# 6. Runs smoke tests (basic SQL queries)
# 7. Cleans up
#
# Usage:
#   ./test/run-test.sh [--keep]
#
# Options:
#   --keep    Don't clean up container after test (for debugging)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"
BUNDLE_DIR="$TEST_DIR/bundle"
KEEP_CONTAINER=false

# Parse args
for arg in "$@"; do
  case $arg in
    --keep)
      KEEP_CONTAINER=true
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

cleanup() {
  if [ "$KEEP_CONTAINER" = false ]; then
    log_info "Cleaning up..."
    cd "$TEST_DIR"
    docker compose -f docker-compose.test.yml down -v 2>/dev/null || true
    rm -rf "$BUNDLE_DIR" "$TEST_DIR/test-config" "$TEST_DIR/steampipe.env"
  else
    log_warn "Container kept running. Clean up with:"
    echo "  cd $TEST_DIR && docker compose -f docker-compose.test.yml down -v"
  fi
}

# Cleanup on exit (unless --keep)
trap cleanup EXIT

echo "============================================"
echo "Steampipe Bundle Deployment Test"
echo "============================================"
echo

# ---- Step 1: Find or build bundle ----
log_info "Looking for bundle..."

TARBALL=$(find "$REPO_DIR/build" -name "steampipe-bundle-*.tgz" 2>/dev/null | head -1)

if [ -z "$TARBALL" ]; then
  log_info "No bundle found, building..."
  cd "$REPO_DIR"
  ./build_steampipe_bundle.sh
  TARBALL=$(find "$REPO_DIR/build" -name "steampipe-bundle-*.tgz" | head -1)
fi

if [ -z "$TARBALL" ]; then
  log_error "Failed to find or build bundle"
  exit 1
fi

echo "  Using: $TARBALL"
echo

# ---- Step 2: Extract bundle ----
log_info "Extracting bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
tar -xzf "$TARBALL" -C "$BUNDLE_DIR"
echo "  Extracted to: $BUNDLE_DIR"
echo

# ---- Step 3: Create test configs ----
log_info "Creating test configs..."
mkdir -p "$TEST_DIR/test-config"

# Create minimal jira config (won't actually connect, just for startup test)
cat > "$TEST_DIR/test-config/jira.spc" << 'EOF'
connection "jira" {
  plugin                = "jira@1.1.0"
  base_url              = "http://localhost:8080"
  personal_access_token = "test-token"
}
EOF

# Create steampipe.env
cat > "$TEST_DIR/steampipe.env" << 'EOF'
STEAMPIPE_CONFIG_PATH=/etc/steampipe
STEAMPIPE_DATABASE_PORT=9193
STEAMPIPE_LOG_LEVEL=info
STEAMPIPE_LISTEN=network
EOF

echo "  Created test configs"
echo

# ---- Step 4: Build and start container ----
log_info "Building and starting container..."
cd "$TEST_DIR"
docker compose -f docker-compose.test.yml up -d --build

echo "  Container started"
echo

# ---- Step 5: Wait for healthy ----
log_info "Waiting for steampipe to be ready..."

MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  if docker compose -f docker-compose.test.yml ps | grep -q "healthy"; then
    echo "  Steampipe is healthy!"
    break
  fi

  # Check if container crashed
  if docker compose -f docker-compose.test.yml ps | grep -q "exited"; then
    log_error "Container exited unexpectedly"
    echo "  Logs:"
    docker compose -f docker-compose.test.yml logs --tail=50
    exit 1
  fi

  echo "  Waiting... ($WAITED/$MAX_WAIT seconds)"
  sleep 5
  WAITED=$((WAITED + 5))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  log_error "Timeout waiting for steampipe to be ready"
  echo "  Logs:"
  docker compose -f docker-compose.test.yml logs --tail=50
  exit 1
fi
echo

# ---- Step 6: Run smoke tests ----
log_info "Running smoke tests..."

# Test 1: Basic connection
echo "  Test 1: Basic PostgreSQL connection..."
if docker compose -f docker-compose.test.yml exec -T steampipe \
    psql -h localhost -p 9193 -U steampipe -d steampipe -c "SELECT 1 AS test" > /dev/null 2>&1; then
  echo "    [PASS] Basic connection"
else
  log_error "Basic connection failed"
  exit 1
fi

# Test 2: Check steampipe version
echo "  Test 2: Steampipe version..."
VERSION=$(docker compose -f docker-compose.test.yml exec -T steampipe \
    ./steampipe/steampipe --version 2>/dev/null | head -1)
echo "    [PASS] $VERSION"

# Test 3: List installed plugins
echo "  Test 3: Installed plugins..."
PLUGINS=$(docker compose -f docker-compose.test.yml exec -T steampipe \
    psql -h localhost -p 9193 -U steampipe -d steampipe -t -c \
    "SELECT plugin FROM steampipe_internal.steampipe_plugin" 2>/dev/null | grep -v "^$" | wc -l)
echo "    [PASS] Found $PLUGINS plugin(s) registered"

# Test 4: Query system table
echo "  Test 4: Query system table..."
if docker compose -f docker-compose.test.yml exec -T steampipe \
    psql -h localhost -p 9193 -U steampipe -d steampipe -c \
    "SELECT current_database(), current_user" > /dev/null 2>&1; then
  echo "    [PASS] System query works"
else
  log_error "System query failed"
  exit 1
fi

echo

# ---- Done ----
echo "============================================"
echo -e "${GREEN}All tests PASSED!${NC}"
echo "============================================"
echo
echo "Bundle successfully deployed and tested in AlmaLinux 9."
echo
if [ "$KEEP_CONTAINER" = true ]; then
  echo "Container is still running. Connect with:"
  echo "  psql -h localhost -p 9193 -U steampipe -d steampipe"
  echo
  echo "View logs:"
  echo "  cd $TEST_DIR && docker compose -f docker-compose.test.yml logs -f"
fi
