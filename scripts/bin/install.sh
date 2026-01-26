#!/bin/bash
#
# Steam Engine Post-Import Installer
# Run once after WSL import to set up steampipe and gateway services
#
# Usage: install.sh /mnt/c/path/to/steampipe-bundle.tgz
#
set -euo pipefail

# ============================================
# Logging
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC}  $*"; }

# ============================================
# Configuration
# ============================================
BUNDLE_SRC="${1:-}"
BUNDLE_DST="/opt/steampipe/steampipe-bundle.tgz"
PERSIST_DIR="/opt/steampipe"
SECRETS_DIR="/opt/wsl-secrets"

echo ""
echo "============================================"
echo "  Steam Engine Installer"
echo "============================================"
echo ""

# ============================================
# Phase 1: PREFLIGHT
# ============================================
log_info "Phase 1: Preflight checks"

# Check bundle argument
if [ -z "$BUNDLE_SRC" ]; then
    log_fail "Usage: install.sh /mnt/c/path/to/steampipe-bundle.tgz"
fi

# Check bundle exists
if [ ! -f "$BUNDLE_SRC" ]; then
    log_fail "Bundle not found: $BUNDLE_SRC"
fi
log_ok "Bundle found: $BUNDLE_SRC"

# Check running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_fail "Run with sudo: sudo install.sh $BUNDLE_SRC"
fi
log_ok "Running as root"

# Check secrets mount
if [ ! -d "$SECRETS_DIR" ]; then
    log_warn "Secrets directory missing: $SECRETS_DIR"
elif [ -z "$(ls -A $SECRETS_DIR 2>/dev/null)" ]; then
    log_warn "Secrets directory empty - configure after install"
elif [ ! -f "$SECRETS_DIR/steampipe.env" ]; then
    log_warn "steampipe.env not found - configure after install"
else
    log_ok "Secrets configured: $SECRETS_DIR/steampipe.env"
fi

echo ""

# ============================================
# Phase 2: COPY
# ============================================
log_info "Phase 2: Copy tarball into WSL"

if [ -f "$BUNDLE_DST" ]; then
    # Check if source is newer
    if [ "$BUNDLE_SRC" -nt "$BUNDLE_DST" ]; then
        log_info "Source bundle is newer, updating..."
        rm -f "$BUNDLE_DST"
    else
        log_skip "Bundle already copied: $BUNDLE_DST"
    fi
fi

if [ ! -f "$BUNDLE_DST" ]; then
    # Copy to /tmp first (faster than direct copy from Windows mount)
    TMP_BUNDLE="/tmp/steampipe-bundle-$$.tgz"
    log_info "Copying to temp: $TMP_BUNDLE"
    cp "$BUNDLE_SRC" "$TMP_BUNDLE"

    log_info "Moving to: $BUNDLE_DST"
    mv "$TMP_BUNDLE" "$BUNDLE_DST"
    chown steampipe:steampipe "$BUNDLE_DST"
    log_ok "Bundle copied: $(du -h $BUNDLE_DST | cut -f1)"
fi

echo ""

# ============================================
# Phase 3: SETUP
# ============================================
log_info "Phase 3: Setup persistent directories"

mkdir -p "$PERSIST_DIR/data"
mkdir -p "$PERSIST_DIR/internal"
mkdir -p "$PERSIST_DIR/logs"
chown -R steampipe:steampipe "$PERSIST_DIR"
log_ok "Directories ready: $PERSIST_DIR/{data,internal,logs}"

echo ""

# ============================================
# Phase 4: VERIFY BUNDLE
# ============================================
log_info "Phase 4: Verify bundle contents"

# Quick extraction test to /tmp
TMP_TEST="/tmp/steampipe-test-$$"
mkdir -p "$TMP_TEST"
tar -xzf "$BUNDLE_DST" -C "$TMP_TEST" --strip-components=0 2>/dev/null || log_fail "Bundle extraction failed"

if [ -x "$TMP_TEST/steampipe/steampipe" ]; then
    log_ok "Steampipe binary present"
else
    rm -rf "$TMP_TEST"
    log_fail "Steampipe binary missing in bundle"
fi

if [ -x "$TMP_TEST/db/14.19.0/postgres/bin/postgres" ]; then
    log_ok "Postgres binary present"
else
    rm -rf "$TMP_TEST"
    log_fail "Postgres binary missing in bundle"
fi

rm -rf "$TMP_TEST"

echo ""

# ============================================
# Phase 5: SERVICES
# ============================================
log_info "Phase 5: Enable services"

systemctl daemon-reload
log_ok "Systemd reloaded"

systemctl enable steampipe.service gateway.service
log_ok "Services enabled"

echo ""

# ============================================
# Phase 6: START
# ============================================
log_info "Phase 6: Start services"

systemctl start steampipe.service
sleep 2

if systemctl is-active --quiet steampipe.service; then
    log_ok "Steampipe started"
else
    log_warn "Steampipe failed to start - check: journalctl -u steampipe"
fi

systemctl start gateway.service
sleep 2

if systemctl is-active --quiet gateway.service; then
    log_ok "Gateway started"
else
    log_warn "Gateway failed to start - check: journalctl -u gateway"
fi

echo ""

# ============================================
# Summary
# ============================================
echo "============================================"
echo "  Installation Complete"
echo "============================================"
echo ""
echo "Bundle:    $BUNDLE_DST"
echo "Data:      $PERSIST_DIR/data"
echo "Runtime:   /run/steampipe (tmpfs)"
echo "Secrets:   $SECRETS_DIR"
echo ""
echo "Services:"
systemctl is-active steampipe.service && echo "  steampipe: running" || echo "  steampipe: stopped"
systemctl is-active gateway.service && echo "  gateway:   running" || echo "  gateway:   stopped"
echo ""
echo "Commands:"
echo "  systemctl status steampipe gateway"
echo "  journalctl -u steampipe -f"
echo "  steampipe query"
echo ""
