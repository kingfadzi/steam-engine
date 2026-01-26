# Plan: Bake Everything Into Image

## Problem
- Windows Defender deletes extracted postgres binaries
- Steampipe binary is fine
- Currently too many scripts and complexity

## Solution
Bake everything into the Docker image. No post-import extraction needed.

---

## Architecture

```
PREP (one-time)                    BUILD                         POST-IMPORT
───────────────                    ─────                         ───────────
binaries.sh                        Dockerfile                    User actions
    │                                  │                             │
    ▼                                  ▼                             ▼
binaries/                          Image contains:               1. Configure secrets
├── postgres/*.rpm                 ├── /usr/pgsql-14/            2. systemctl enable
├── steampipe-bundle.tgz           │   └── bin/postgres          3. systemctl start
└── gateway.jar                    ├── /opt/steampipe/
                                   │   ├── steampipe/steampipe
                                   │   ├── plugins/
                                   │   ├── config/*.spc
                                   │   └── db/14.19.0/postgres/
                                   │       └── bin → /usr/pgsql-14/bin
                                   └── /opt/gateway/gateway.jar
```

---

## What Changes

### binaries.sh
- Add `--fetch-pg` to download PostgreSQL 14 RPMs
- Existing steampipe bundle fetch stays the same

### Dockerfile
- Install postgres from local RPMs
- Extract steampipe bundle during build (not runtime)
- Create symlink: steampipe's pg dir → system postgres
- Services enabled by default

### Remove
- `install.sh` - no longer needed
- `setup-tmpfs.sh` - no longer needed
- RuntimeDirectory complexity - not needed

### steampipe-start.sh
- Simplified: just source secrets and exec
- No extraction, no symlinks (done at build time)

---

## File Structure After Build

```
/usr/pgsql-14/                      ← RPM-installed (Defender trusts)
├── bin/
│   ├── postgres
│   ├── initdb
│   ├── pg_ctl
│   └── ...
├── lib/
└── share/

/opt/steampipe/                     ← Baked into image
├── steampipe/
│   └── steampipe                   ← Binary (not flagged)
├── plugins/
│   └── hub.steampipe.io/...
├── config/
│   ├── jira.spc
│   ├── gitlab.spc
│   └── steampipe.env.example
├── db/
│   └── 14.19.0/
│       └── postgres/
│           ├── bin → /usr/pgsql-14/bin    ← Symlink
│           ├── lib → /usr/pgsql-14/lib
│           └── share → /usr/pgsql-14/share
├── data/                           ← Postgres data (persists)
└── internal/

/opt/gateway/
├── gateway.jar
└── application.yml

/opt/wsl-secrets/                   ← Mounted from Windows
└── steampipe.env                   ← User creates this
```

---

## Implementation

### 1. binaries.sh additions

```bash
POSTGRES_VERSION="14.20"
PGDG_URL="https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-9-x86_64"

fetch_postgres() {
    mkdir -p "$SCRIPT_DIR/binaries/postgres"

    RPMS=(
        "postgresql14-libs-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
        "postgresql14-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
        "postgresql14-server-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
    )

    for rpm in "${RPMS[@]}"; do
        [ -f "binaries/postgres/$rpm" ] && continue
        curl -fSL -o "binaries/postgres/$rpm" "$PGDG_URL/$rpm"
    done
}
```

### 2. Dockerfile

```dockerfile
# ============================================
# PostgreSQL 14 from local RPMs
# ============================================
COPY binaries/postgres/*.rpm /tmp/postgres/
RUN dnf install -y /tmp/postgres/*.rpm \
    && rm -rf /tmp/postgres \
    && dnf clean all

# ============================================
# Steampipe (baked into image)
# ============================================
COPY binaries/steampipe-bundle.tgz /tmp/
RUN mkdir -p /opt/steampipe \
    && tar -xzf /tmp/steampipe-bundle.tgz -C /opt/steampipe \
    && rm /tmp/steampipe-bundle.tgz

# Symlink postgres to RPM installation
RUN mkdir -p /opt/steampipe/db/14.19.0/postgres \
    && ln -sf /usr/pgsql-14/bin /opt/steampipe/db/14.19.0/postgres/bin \
    && ln -sf /usr/pgsql-14/lib /opt/steampipe/db/14.19.0/postgres/lib \
    && ln -sf /usr/pgsql-14/share /opt/steampipe/db/14.19.0/postgres/share

# Persistent directories
RUN mkdir -p /opt/steampipe/data /opt/steampipe/internal \
    && chown -R steampipe:steampipe /opt/steampipe

# Enable services
RUN systemctl enable steampipe.service gateway.service
```

### 3. steampipe.service (simplified)

```ini
[Unit]
Description=Steampipe SQL Service
After=network.target local-fs.target
RequiresMountsFor=/opt/wsl-secrets

[Service]
Type=simple
User=steampipe
Group=steampipe

Environment=STEAMPIPE_INSTALL_DIR=/opt/steampipe
Environment=HOME=/opt/steampipe
WorkingDirectory=/opt/steampipe

ExecStart=/opt/init/steampipe-start.sh
ExecStop=/opt/steampipe/steampipe/steampipe service stop

Restart=on-failure
RestartSec=10
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

### 4. steampipe-start.sh (simplified)

```bash
#!/bin/bash
set -e

SECRETS="/opt/wsl-secrets/steampipe.env"

# Check secrets
if [ ! -f "$SECRETS" ]; then
    echo "ERROR: Secrets not configured: $SECRETS"
    echo "Copy example: cp /opt/steampipe/config/steampipe.env.example $SECRETS"
    exit 1
fi

# Source secrets
set -a
source "$SECRETS"
set +a

# Environment
export STEAMPIPE_INSTALL_DIR=/opt/steampipe
export HOME=/opt/steampipe

# Start
exec /opt/steampipe/steampipe/steampipe service start --foreground
```

---

## Post-Import User Steps

```bash
# 1. Start WSL
wsl -d steam-engine

# 2. Configure secrets (one-time)
cp /opt/steampipe/config/steampipe.env.example /mnt/c/devhome/projects/steamengine/secrets/steampipe.env
# Edit with your credentials

# 3. Restart to pick up fstab mount
wsl --shutdown
wsl -d steam-engine

# 4. Check services
systemctl status steampipe gateway
```

---

## Files to Modify

| File | Action |
|------|--------|
| binaries.sh | Add `--fetch-pg` for RPMs |
| Dockerfile | Install RPMs, extract bundle, create symlinks |
| steampipe.service | Remove RuntimeDirectory, simplify |
| steampipe-start.sh | Just source secrets and exec |
| install.sh | DELETE |
| setup-tmpfs.sh | Already deleted |

---

## Testing

```bash
# 1. Fetch postgres RPMs
./binaries.sh --fetch-pg

# 2. Build
./build.sh vpn --debug

# 3. Test in Docker
docker run --rm steam-engine:vpn ls -la /opt/steampipe/db/14.19.0/postgres/bin/
docker run --rm steam-engine:vpn /opt/steampipe/steampipe/steampipe --version
docker run --rm steam-engine:vpn /usr/pgsql-14/bin/postgres --version

# 4. Test in WSL
# - Import, configure secrets, check services start
```

---

## Expected Outcome

1. Single `build.sh vpn` produces complete image
2. No extraction at runtime
3. Postgres from RPMs (Defender safe)
4. Steampipe binary baked in (not flagged)
5. User just configures secrets and services auto-start
6. Simpler codebase (fewer scripts)
