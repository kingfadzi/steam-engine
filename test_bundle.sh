#!/bin/bash
#
# test_bundle.sh - Verify steampipe bundle integrity
#
# Run this after extracting the bundle to verify all components are present
# and the steampipe binary works.
#
# Usage:
#   ./test_bundle.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0

echo "============================================"
echo "Steampipe Bundle Test"
echo "============================================"
echo "Bundle path: $SCRIPT_DIR"
echo

# Test function
check() {
  local name="$1"
  local condition="$2"

  if eval "$condition"; then
    echo "  [PASS] $name"
    return 0
  else
    echo "  [FAIL] $name"
    FAILED=1
    return 1
  fi
}

# ---- Test 1: Directory structure ----
echo "[1/5] Checking directory structure..."
check "bin/ directory exists" "[ -d '$SCRIPT_DIR/bin' ]"
check "steampipe/ directory exists" "[ -d '$SCRIPT_DIR/steampipe' ]"
check "db/ directory exists" "[ -d '$SCRIPT_DIR/db' ]"
check "plugins/ directory exists" "[ -d '$SCRIPT_DIR/plugins' ]"
check "internal/ directory exists" "[ -d '$SCRIPT_DIR/internal' ]"
check "config-templates/ directory exists" "[ -d '$SCRIPT_DIR/config-templates' ]"
check "systemd/ directory exists" "[ -d '$SCRIPT_DIR/systemd' ]"
echo

# ---- Test 2: Launcher scripts ----
echo "[2/5] Checking launcher scripts..."
check "bin/common.sh exists" "[ -f '$SCRIPT_DIR/bin/common.sh' ]"
check "bin/server is executable" "[ -x '$SCRIPT_DIR/bin/server' ]"
check "bin/stop is executable" "[ -x '$SCRIPT_DIR/bin/stop' ]"
check "bin/status is executable" "[ -x '$SCRIPT_DIR/bin/status' ]"
check "steampipe.env.example exists" "[ -f '$SCRIPT_DIR/steampipe.env.example' ]"
echo

# ---- Test 3: Steampipe binary ----
echo "[3/5] Checking steampipe binary..."
check "steampipe binary exists" "[ -f '$SCRIPT_DIR/steampipe/steampipe' ]"
check "steampipe binary is executable" "[ -x '$SCRIPT_DIR/steampipe/steampipe' ]"

# Try to run steampipe --version
echo "  Running: steampipe --version"
export STEAMPIPE_INSTALL_DIR="$SCRIPT_DIR"
if "$SCRIPT_DIR/steampipe/steampipe" --version 2>/dev/null; then
  echo "  [PASS] steampipe --version"
else
  echo "  [FAIL] steampipe --version"
  FAILED=1
fi
echo

# ---- Test 4: Plugins ----
echo "[4/5] Checking plugins..."
PLUGIN_COUNT=$(find "$SCRIPT_DIR/plugins" -name "*.plugin" 2>/dev/null | wc -l)
check "Plugins exist ($PLUGIN_COUNT found)" "[ '$PLUGIN_COUNT' -gt 0 ]"

# List plugins found
if [ "$PLUGIN_COUNT" -gt 0 ]; then
  echo "  Plugins:"
  find "$SCRIPT_DIR/plugins" -name "*.plugin" -exec basename {} \; | sed 's/^/    - /'
fi
echo

# ---- Test 5: Database ----
echo "[5/5] Checking database..."
PG_DIR=$(find "$SCRIPT_DIR/db" -name "postgres" -type d 2>/dev/null | head -1)
if [ -n "$PG_DIR" ]; then
  check "PostgreSQL directory exists" "[ -d '$PG_DIR' ]"
  check "PostgreSQL binary exists" "[ -f '$PG_DIR/bin/postgres' ] || [ -f '$PG_DIR/bin/pg_ctl' ]"

  # Check for FDW
  FDW_SO=$(find "$SCRIPT_DIR/db" -name "steampipe_postgres_fdw.so" 2>/dev/null | head -1)
  check "FDW extension exists" "[ -n '$FDW_SO' ]"
else
  echo "  [FAIL] PostgreSQL directory not found"
  FAILED=1
fi

# Check internal files
check "internal/.passwd exists" "[ -f '$SCRIPT_DIR/internal/.passwd' ]"
echo

# ---- Summary ----
echo "============================================"
if [ $FAILED -eq 0 ]; then
  echo "All tests PASSED"
  echo "============================================"
  echo
  echo "Bundle is ready for deployment."
  echo
  echo "Next steps:"
  echo "  1. Copy config templates to /etc/steampipe/"
  echo "  2. Edit .spc files with your credentials"
  echo "  3. Run ./bin/server to start"
  exit 0
else
  echo "Some tests FAILED"
  echo "============================================"
  echo
  echo "Please check the bundle contents and rebuild if necessary."
  exit 1
fi
