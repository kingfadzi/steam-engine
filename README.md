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
./binaries.sh

# 2. Build WSL image (--validate runs smoke tests before export)
./build.sh vpn --validate    # For laptop/VPN (public DNS)
./build.sh lan --validate    # For VDI (corporate DNS)

# 3. Import to WSL (PowerShell)
wsl --import steam-engine C:\wsl\steam-engine steam-engine-vpn.tar

# 4. Configure secrets on Windows
# See "Secrets" section below

# 5. Start
wsl -d steam-engine
```

## Project Structure

```
steam-engine/
├── Dockerfile              # WSL image definition
├── build.sh                # Build and export WSL image
├── binaries.sh             # Prepare binaries (downloads + packages)
├── profiles/
│   ├── base.args           # GATEWAY_REPO, common settings
│   ├── vpn.args            # Public DNS profile
│   └── lan.args            # Corporate DNS profile
├── config/
│   ├── wsl.conf
│   ├── steampipe/*.spc     # Plugin configs
│   ├── gateway/application.yml
│   └── systemd/*.service
├── scripts/
│   ├── bin/                # Utility scripts
│   ├── init/               # Service init scripts
│   ├── profile.d/          # Login-time scripts
│   └── download.sh         # Download steampipe artifacts
├── binaries/               # (gitignored) Prepped artifacts
│   ├── steampipe-bundle.tgz
│   └── gateway.jar
├── artifacts/              # (gitignored) Downloaded artifacts
└── README.md
```

## Configuration

### Gateway Repo

Set in `profiles/base.args`:
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

## Components

| Component | Purpose |
|-----------|---------|
| **Steampipe** | SQL interface to Jira/GitLab/Bitbucket APIs |
| **Gateway** | Spring Batch ETL - queries Steampipe, writes to DW |
| **DW PostgreSQL** | Target for fact tables, used by dbt |

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `binaries.sh` | Download/build steampipe bundle + gateway JAR |
| `binaries.sh --force` | Rebuild binaries even if they exist |
| `build.sh <profile>` | Build WSL image from profile |
| `build.sh <profile> --validate` | Build with smoke tests before export |
| `build.sh <profile> --no-cache` | Force full Docker rebuild |
| `scripts/download.sh` | Download steampipe artifacts (requires oras) |
