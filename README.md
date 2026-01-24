# Steam Engine

WSL image for Steampipe + Gateway ETL. Extracts Jira/GitLab data via Steampipe and loads to DW PostgreSQL for dbt transforms.

## Quick Start

```bash
./binaries.sh
./build.sh vpn --validate
```

Then in PowerShell:
```powershell
wsl --import steam-engine C:\wsl\steam-engine steam-engine-vpn.tar
wsl -d steam-engine
```

## Profiles

| Profile | DNS | Use Case |
|---------|-----|----------|
| `vpn` | 8.8.8.8 | Laptop/VPN |
| `lan` | Corporate | VDI |

## Project Structure

```
steam-engine/
├── Dockerfile
├── build.sh
├── binaries.sh
├── profiles/
│   ├── base.args
│   ├── vpn.args
│   └── lan.args
├── config/
│   ├── wsl.conf
│   ├── steampipe/*.spc
│   ├── gateway/application.yml
│   └── systemd/*.service
├── scripts/
│   ├── bin/
│   ├── init/
│   ├── profile.d/
│   └── download.sh
├── binaries/
└── artifacts/
```

## Configuration

### Gateway Repo

Set in `profiles/base.args`:
```
GATEWAY_REPO=git@github.com:kingfadzi/gateway.git
GATEWAY_REF=main
```

Override:
```bash
GATEWAY_REPO=git@github.com:myorg/gateway.git ./binaries.sh
```

### Secrets

Create on Windows at `C:\devhome\projects\steamengine\secrets\`:

**steampipe.env**
```bash
JIRA_URL=https://jira.company.com
JIRA_TOKEN=xxx
GITLAB_URL=https://gitlab.company.com
GITLAB_TOKEN=xxx
```

**gateway.env**
```bash
DW_HOST=dw.company.com
DW_PORT=5432
DW_DATABASE=lct_data
DW_USER=gateway
DW_PASSWORD=xxx
```

## Scripts

| Script | Purpose |
|--------|---------|
| `binaries.sh` | Download/build steampipe bundle + gateway JAR |
| `binaries.sh --force` | Rebuild binaries |
| `build.sh <profile>` | Build WSL image |
| `build.sh <profile> --validate` | Build with smoke tests |
| `build.sh <profile> --no-cache` | Force full rebuild |
| `scripts/download.sh` | Download steampipe artifacts |
