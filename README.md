# Steam Engine

WSL image for Steampipe + Gateway ETL. Extracts Jira/GitLab data via Steampipe and loads to DW PostgreSQL for dbt transforms.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  WSL Image                                                  │
│                                                             │
│  ┌─────────────────────────┐      ┌─────────────┐          │
│  │  Steampipe              │ SQL  │   Gateway   │          │
│  │  ├─ embedded PostgreSQL │◄─────│ (batch job) │          │
│  │  │   (internal, :9193)  │      └──────┬──────┘          │
│  │  └─ plugins             │             │                 │
│  └──────────┬──────────────┘             │                 │
└─────────────┼────────────────────────────┼──────────────────┘
              │ API                        │ JDBC
              ▼                            ▼
       ┌──────────────┐            ┌──────────────────┐
       │ Jira/GitLab  │            │  DW PostgreSQL   │──► dbt
       │   (remote)   │            │    (remote)      │
       └──────────────┘            └──────────────────┘
```

## Quick Start

```bash
# 1. Prepare binaries (downloads artifacts, builds gateway JAR)
cd wsl
./binaries.sh

# 2. Build WSL image
./build.sh vpn    # For laptop/VPN (public DNS)
./build.sh lan    # For VDI (corporate DNS)

# 3. Import to WSL (PowerShell)
wsl --import steam-engine C:\wsl\steam-engine steam-engine-vpn.tar

# 4. Configure secrets on Windows
# See wsl/README.md for secret setup

# 5. Start
wsl -d steam-engine
```

## Project Structure

```
steam-engine/
├── wsl/                        # WSL image builder
│   ├── Dockerfile              # AlmaLinux 9 + Steampipe + Gateway
│   ├── build.sh                # Build & export WSL image
│   ├── binaries.sh             # Prepare binaries (steampipe + gateway)
│   ├── profiles/               # Build variants (vpn, lan)
│   ├── config/                 # Runtime configs
│   │   ├── steampipe/          # Plugin configs (.spc)
│   │   ├── gateway/            # Gateway application.yml
│   │   └── systemd/            # Service definitions
│   └── scripts/                # Init and utility scripts
├── bundle-templates/           # Steampipe bundle templates
├── build_steampipe_bundle.sh   # Build steampipe bundle
├── scripts/
│   └── download.sh             # Download steampipe artifacts
├── test/                       # Integration tests
├── versions.conf               # Artifact versions
└── README.md
```

## Configuration

### Gateway Repo (configurable)

Set in `wsl/profiles/base.args`:
```
GATEWAY_REPO=git@github.com:kingfadzi/gateway.git
GATEWAY_REF=main
```

Override at build time:
```bash
GATEWAY_REPO=git@github.com:myorg/gateway.git ./binaries.sh
```

### Secrets

Create on Windows at `C:\devhome\projects\wsl\secrets\steam-engine\`:

**steampipe.env** - Data source credentials:
```bash
JIRA_URL=https://jira.company.com
JIRA_TOKEN=xxx
GITLAB_URL=https://gitlab.company.com
GITLAB_TOKEN=xxx
```

**gateway.env** - DW connection:
```bash
DW_HOST=dw.company.com
DW_PORT=5432
DW_DATABASE=lct_data
DW_USER=gateway
DW_PASSWORD=xxx
```

## Testing

```bash
# Test steampipe bundle in AlmaLinux 9 container
./test/run-test.sh

# Keep container for debugging
./test/run-test.sh --keep
```

## Components

| Component | Purpose |
|-----------|---------|
| **Steampipe** | SQL interface to Jira/GitLab/Bitbucket APIs |
| **Gateway** | Spring Batch ETL - queries Steampipe, writes to DW |
| **DW PostgreSQL** | Target for fact tables, used by dbt |

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `wsl/binaries.sh` | Download/build steampipe bundle + gateway JAR |
| `wsl/build.sh` | Build WSL image from profile |
| `build_steampipe_bundle.sh` | Create self-contained steampipe tarball |
| `scripts/download.sh` | Download steampipe artifacts (requires oras) |
| `test/run-test.sh` | Test bundle in container |
