# Plan: Simplify Steampipe Setup Flow

## Current Problem
- Too many scripts with overlapping responsibilities
- Steampipe setup split between build-time and runtime
- Hard to debug, messy error handling
- Windows Defender deletes binaries from ext4

## New Approach

**Build time (build.sh):** Platform only - no steampipe binaries
**Post-import (install.sh):** Single script does all steampipe/gateway setup

---

## Architecture

```
BUILD TIME                         POST-IMPORT
───────────                        ───────────
build.sh                           install.sh
    │                                  │
    ▼                                  ▼
┌─────────────┐                   ┌─────────────────────────────────┐
│ Platform    │                   │ 1. Copy tarball /mnt/c → /tmp   │
│ - AlmaLinux │                   │ 2. Copy /tmp → /opt/steampipe/  │
│ - systemd   │   WSL Import      │ 3. Setup persistent dirs        │
│ - java      │ ───────────────►  │ 4. Configure services           │
│ - users     │                   │ 5. Enable systemd units         │
│ - configs   │                   └─────────────────────────────────┘
└─────────────┘

SERVICE START (each boot)
─────────────────────────
setup-tmpfs.sh (ExecStartPre)
    │
    ▼
┌─────────────────────────────────────┐
│ 1. Extract /opt/steampipe/bundle.tgz│
│    → /run/steampipe (tmpfs)         │
│ 2. Symlink data → /opt/steampipe/   │
│ 3. Start steampipe                  │
└─────────────────────────────────────┘
```

---

## File Changes

### Remove from Dockerfile
- Steampipe bundle COPY/extraction
- Steampipe-specific setup (keep directory structure only)

### Keep in Dockerfile
- Base packages (java, postgresql-client)
- User creation (steampipe, fadzi)
- Directory stubs (/opt/steampipe, /opt/gateway, /opt/wsl-secrets)
- Config files (.spc, application.yml, steampipe.env.example)
- Systemd service files (but services disabled by default)
- fstab for secrets mount

### New: scripts/bin/install.sh
Single post-import script with proper logging:

```
install.sh [--bundle PATH]

Phases:
  1. PREFLIGHT   - Check prerequisites
  2. COPY        - Bring tarball into WSL
  3. SETUP       - Create persistent directories
  4. CONFIGURE   - Set up symlinks and permissions
  5. SERVICES    - Enable and start systemd units
  6. VERIFY      - Health checks

Logging:
  [INFO]  step description
  [OK]    success
  [FAIL]  error with actionable message
  [SKIP]  already done
```

### Update: scripts/init/setup-tmpfs.sh
Called by systemd ExecStartPre:

```
1. Check /opt/steampipe/steampipe-bundle.tgz exists
2. Extract to /run/steampipe (RuntimeDirectory)
3. Symlink /run/steampipe/db/.../data → /opt/steampipe/data
4. Copy config files
5. Verify binaries executable
```

### Update: config/systemd/steampipe.service
```ini
[Service]
RuntimeDirectory=steampipe
RuntimeDirectoryMode=0755
Environment=STEAMPIPE_INSTALL_DIR=/run/steampipe
ExecStartPre=/opt/init/setup-tmpfs.sh
ExecStart=/opt/init/steampipe-start.sh
```

### Remove
- scripts/bin/install-steampipe.sh (replaced by install.sh)
- scripts/init/validate-mounts.sh (merged into install.sh and setup-tmpfs.sh)

---

## Directory Layout

### After build (in image)
```
/opt/steampipe/
├── config/
│   ├── jira.spc
│   ├── gitlab.spc
│   ├── bitbucket.spc
│   └── steampipe.env.example
└── (empty - no binaries)

/opt/gateway/
├── gateway.jar
└── application.yml
```

### After install.sh
```
/opt/steampipe/
├── steampipe-bundle.tgz    ← copied from Windows
├── config/                  ← unchanged
├── data/                    ← created (postgres data lives here)
└── internal/                ← created (plugin state)
```

### At runtime (after setup-tmpfs.sh)
```
/run/steampipe/              ← tmpfs, extracted on boot
├── steampipe/steampipe
├── db/14.19.0/postgres/
│   ├── bin/
│   └── data → /opt/steampipe/data
├── plugins/
└── config/                  ← copied from /opt/steampipe/config
```

---

## install.sh Pseudocode

```bash
#!/bin/bash
set -euo pipefail

# Logging
log_info()  { echo "[INFO]  $*"; }
log_ok()    { echo "[OK]    $*"; }
log_fail()  { echo "[FAIL]  $*" >&2; exit 1; }
log_skip()  { echo "[SKIP]  $*"; }

# Config
BUNDLE_SRC="${1:-/mnt/c/devhome/projects/steamengine/binaries/steampipe-bundle.tgz}"
BUNDLE_DST="/opt/steampipe/steampipe-bundle.tgz"
PERSIST_DIR="/opt/steampipe"

#─────────────────────────────────────
# Phase 1: PREFLIGHT
#─────────────────────────────────────
log_info "Phase 1: Preflight checks"

[ -f "$BUNDLE_SRC" ] || log_fail "Bundle not found: $BUNDLE_SRC"
log_ok "Bundle found: $BUNDLE_SRC"

[ -d "/opt/wsl-secrets" ] || log_fail "Secrets directory missing"
[ -f "/opt/wsl-secrets/steampipe.env" ] || log_fail "steampipe.env not found"
log_ok "Secrets configured"

#─────────────────────────────────────
# Phase 2: COPY
#─────────────────────────────────────
log_info "Phase 2: Copy tarball into WSL"

if [ -f "$BUNDLE_DST" ]; then
    log_skip "Bundle already copied"
else
    TMP_BUNDLE="/tmp/steampipe-bundle.tgz"
    cp "$BUNDLE_SRC" "$TMP_BUNDLE"
    mv "$TMP_BUNDLE" "$BUNDLE_DST"
    chown steampipe:steampipe "$BUNDLE_DST"
    log_ok "Copied to $BUNDLE_DST"
fi

#─────────────────────────────────────
# Phase 3: SETUP
#─────────────────────────────────────
log_info "Phase 3: Setup persistent directories"

mkdir -p "$PERSIST_DIR/data"
mkdir -p "$PERSIST_DIR/internal"
chown -R steampipe:steampipe "$PERSIST_DIR"
log_ok "Directories created"

#─────────────────────────────────────
# Phase 4: SERVICES
#─────────────────────────────────────
log_info "Phase 4: Enable services"

systemctl daemon-reload
systemctl enable steampipe gateway
systemctl start steampipe gateway
log_ok "Services started"

#─────────────────────────────────────
# Phase 5: VERIFY
#─────────────────────────────────────
log_info "Phase 5: Verify"

sleep 3
systemctl is-active steampipe || log_fail "steampipe not running"
systemctl is-active gateway || log_fail "gateway not running"
log_ok "All services running"

echo ""
echo "Installation complete!"
```

---

## Testing in Docker

```bash
# Build platform image
./build.sh vpn

# Run container with systemd
docker run -d --name steam-test \
  --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v $(pwd)/binaries:/mnt/binaries:ro \
  steam-engine:vpn

# Exec into container and run install
docker exec -it steam-test bash
export BUNDLE_SRC=/mnt/binaries/steampipe-bundle.tgz
install.sh "$BUNDLE_SRC"

# Verify
systemctl status steampipe gateway
```

---

## Migration Steps

1. [ ] Update Dockerfile - remove steampipe bundle, keep platform only
2. [ ] Create scripts/bin/install.sh - single post-import script
3. [ ] Update scripts/init/setup-tmpfs.sh - extract to RuntimeDirectory
4. [ ] Update config/systemd/steampipe.service - use RuntimeDirectory
5. [ ] Update config/systemd/gateway.service - similar pattern if needed
6. [ ] Remove old scripts (install-steampipe.sh, validate-mounts.sh)
7. [ ] Update build.sh --debug mode for new flow
8. [ ] Test in Docker
9. [ ] Test in WSL

---

## Success Criteria

1. `build.sh vpn` produces platform image with no steampipe binaries
2. `install.sh` runs post-import with clear logging
3. Services start from /run/steampipe (tmpfs)
4. Data persists in /opt/steampipe/data across reboots
5. No files accessible to Windows Defender contain executables
