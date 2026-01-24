# Steam Engine WSL Image

Deployable WSL2 image containing Steampipe + Gateway ETL for extracting Jira/GitLab data to DW PostgreSQL.

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

### 1. Prepare Binaries

```bash
./binaries.sh
```

This builds/downloads:
- `binaries/steampipe-bundle.tgz` - Steampipe + plugins
- `binaries/gateway.jar` - Gateway batch service

### 2. Build WSL Image

```bash
./build.sh vpn    # For laptop/VPN use (public DNS)
./build.sh lan    # For VDI/corporate use (internal DNS)
```

### 3. Import to WSL

In PowerShell:
```powershell
wsl --import steam-engine C:\wsl\steam-engine steam-engine-vpn.tar
```

### 4. Configure Secrets

Create secrets directory on Windows:
```
C:\devhome\projects\wsl\secrets\steam-engine\
├── steampipe.env    # Data source credentials
└── gateway.env      # DW connection
```

**steampipe.env:**
```bash
# Jira
JIRA_URL=https://jira.company.com
JIRA_TOKEN=your-personal-access-token

# GitLab
GITLAB_URL=https://gitlab.company.com
GITLAB_TOKEN=glpat-xxxxxxxxxxxx

# Bitbucket (optional)
BITBUCKET_URL=https://bitbucket.company.com
BITBUCKET_USERNAME=your-username
BITBUCKET_PASSWORD=your-app-password
```

**gateway.env:**
```bash
# Data Warehouse PostgreSQL
DW_HOST=dw.company.com
DW_PORT=5432
DW_DATABASE=lct_data
DW_USER=gateway
DW_PASSWORD=your-password

# Steampipe password (from steampipe service start output)
STEAMPIPE_PASSWORD=xxxx
```

### 5. Start Services

```bash
wsl -d steam-engine

# Services start automatically via systemd
# Check status:
sudo systemctl status steampipe
sudo systemctl status gateway
```

## Usage

### Manual Sync

```bash
# Trigger specific sync
sync-now.sh gitlab
sync-now.sh jira

# Trigger all
sync-now.sh all

# Check status
sync-now.sh status
```

### Query Steampipe Directly

```bash
# Interactive query
steampipe query

# One-liner
steampipe query "SELECT * FROM jira_issue LIMIT 10"

# Via psql
psql -h localhost -p 9193 -U steampipe -d steampipe
```

### View Logs

```bash
# Steampipe logs
journalctl -u steampipe -f

# Gateway logs
journalctl -u gateway -f
```

## Scheduled Jobs

Gateway runs these jobs automatically:

| Job | Schedule | Description |
|-----|----------|-------------|
| GitLab | Every 30 min | Extract MR, pipeline, deploy metrics |
| Jira | Every 30 min | Extract issue metrics |
| SonarQube | Every 2 hours | Extract code quality metrics |

## Monitoring

```bash
# Health check
curl http://localhost:8080/actuator/health

# Prometheus metrics
curl http://localhost:8080/actuator/prometheus
```

## Profiles

| Profile | DNS | Use Case |
|---------|-----|----------|
| `vpn` | 8.8.8.8, 8.8.4.4 | Laptop on VPN |
| `lan` | 10.1.1.1, 10.1.1.2 | VDI on corporate network |

## Troubleshooting

### Steampipe won't start

```bash
# Check logs
journalctl -u steampipe -n 50

# Check config
cat /opt/steampipe/config/*.spc

# Test manually
STEAMPIPE_INSTALL_DIR=/opt/steampipe steampipe service start --foreground
```

### Gateway can't connect to DW

```bash
# Check environment
env | grep DW_

# Test connection
PGPASSWORD=$DW_PASSWORD psql -h $DW_HOST -U $DW_USER -d $DW_DATABASE -c "SELECT 1"
```

### Gateway can't connect to Steampipe

```bash
# Check steampipe is running
pg_isready -h localhost -p 9193 -U steampipe

# Get steampipe password
steampipe service status --show-password
```
