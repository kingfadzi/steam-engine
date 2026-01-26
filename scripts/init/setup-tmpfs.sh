#!/bin/bash
#
# Extract steampipe bundle to tmpfs before service start
# Called by systemd ExecStartPre
#
set -e

BUNDLE="/opt/steampipe/steampipe-bundle.tgz"
RUNTIME_DIR="/run/steampipe"
PERSIST_DIR="/opt/steampipe"
SECRETS_DIR="/opt/wsl-secrets"

log() { echo "[setup-tmpfs] $*"; }

log "Setting up steampipe in tmpfs..."

# ============================================
# Check bundle exists
# ============================================
if [ ! -f "$BUNDLE" ]; then
    log "ERROR: Bundle not found: $BUNDLE"
    log "Run: sudo install.sh /mnt/c/path/to/steampipe-bundle.tgz"
    exit 1
fi

# ============================================
# Check secrets
# ============================================
if [ ! -f "$SECRETS_DIR/steampipe.env" ]; then
    log "ERROR: Secrets not configured: $SECRETS_DIR/steampipe.env"
    log "Create from example: cp /opt/steampipe/config/steampipe.env.example $SECRETS_DIR/steampipe.env"
    exit 1
fi

# ============================================
# Extract to RuntimeDirectory
# ============================================
# Note: /run/steampipe is created by systemd RuntimeDirectory directive
if [ ! -d "$RUNTIME_DIR" ]; then
    log "ERROR: Runtime directory missing: $RUNTIME_DIR"
    log "This should be created by systemd RuntimeDirectory"
    exit 1
fi

log "Extracting bundle to $RUNTIME_DIR..."
tar -xzf "$BUNDLE" -C "$RUNTIME_DIR"

# ============================================
# Setup data symlink
# ============================================
PG_DIR="$RUNTIME_DIR/db/14.19.0/postgres"

if [ -d "$PG_DIR" ]; then
    # Remove extracted data dir (if any) and symlink to persistent
    rm -rf "$PG_DIR/data" 2>/dev/null || true

    # Ensure persistent data dir exists
    mkdir -p "$PERSIST_DIR/data"

    # Create symlink
    ln -sf "$PERSIST_DIR/data" "$PG_DIR/data"
    log "Linked data: $PG_DIR/data -> $PERSIST_DIR/data"
fi

# ============================================
# Copy config files
# ============================================
if [ -d "$PERSIST_DIR/config" ]; then
    mkdir -p "$RUNTIME_DIR/config"
    cp -r "$PERSIST_DIR/config/"* "$RUNTIME_DIR/config/" 2>/dev/null || true
    log "Copied config files"
fi

# ============================================
# Set permissions
# ============================================
chown -R steampipe:steampipe "$RUNTIME_DIR"
chown -R steampipe:steampipe "$PERSIST_DIR/data"
chmod +x "$RUNTIME_DIR/steampipe/steampipe"
chmod +x "$RUNTIME_DIR/db/14.19.0/postgres/bin/"* 2>/dev/null || true

# ============================================
# Verify
# ============================================
if [ ! -x "$RUNTIME_DIR/steampipe/steampipe" ]; then
    log "ERROR: Steampipe binary not executable"
    exit 1
fi

if [ ! -x "$RUNTIME_DIR/db/14.19.0/postgres/bin/postgres" ]; then
    log "ERROR: Postgres binary not executable"
    exit 1
fi

log "Ready: $RUNTIME_DIR ($(du -sh $RUNTIME_DIR | cut -f1))"
