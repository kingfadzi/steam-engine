# Steam Engine - Steampipe Docker

Steampipe SQL query engine with GitLab, Jira, and Bitbucket plugins.

## Quick Start (Docker)

```bash
# Configure credentials
cp config/*.spc.example config/*.spc  # if examples exist
# Edit config/*.spc files with your credentials

# Build and run
docker compose up -d

# Query
docker compose exec steampipe steampipe query "select * from jira_board"
```

## Connect via PostgreSQL

```bash
psql -h localhost -p 9193 -U steampipe -d steampipe
```

## Configuration

Edit files in `config/`:

| File | Purpose |
|------|---------|
| `jira.spc` | Jira DC/Server (PAT auth) |
| `gitlab.spc` | GitLab (token auth) |
| `bitbucket.spc` | Bitbucket (app password) |

Plugin versions are configured in `versions.conf`.

### Example: jira.spc
```hcl
connection "jira" {
  plugin                = "jira"
  base_url              = "http://your-jira:8080"
  personal_access_token = "your-pat-token"
}
```

### Example: gitlab.spc
```hcl
connection "gitlab" {
  plugin  = "theapsgroup/gitlab"
  token   = "glpat-xxxx"
  baseurl = "https://your-gitlab.com"
}
```

## Deployment Modes

### Mode 1: Self-Contained Bundle (Recommended for Air-Gapped WSL)

A single tarball containing everything needed to run Steampipe. Extract anywhere, configure, run.

```bash
# On connected machine: build the bundle
./scripts/download.sh              # Download artifacts
./build_steampipe_bundle.sh v1.0.0 # Create bundle

# Transfer to air-gapped machine
scp build/steampipe-bundle-v1.0.0.tgz user@target:/tmp/

# On target machine: deploy
sudo mkdir -p /opt/steampipe
sudo tar -xzf /tmp/steampipe-bundle-v1.0.0.tgz -C /opt/steampipe

# Set up configs (steampipe reads from config/ directory)
sudo mkdir -p /opt/steampipe/config
sudo cp /opt/steampipe/config-templates/*.spc /opt/steampipe/config/
sudo vi /opt/steampipe/config/jira.spc    # Add your credentials
sudo vi /opt/steampipe/config/gitlab.spc

# Configure environment (optional)
cp /opt/steampipe/steampipe.env.example /opt/steampipe/steampipe.env
vi /opt/steampipe/steampipe.env    # Review settings

# Run directly
cd /opt/steampipe && ./bin/server

# OR install as systemd service
sudo /opt/steampipe/systemd/install-service.sh
sudo systemctl enable --now steampipe

# Query
psql -h localhost -p 9193 -U steampipe -d steampipe
```

**Bundle structure:**
```
steampipe-bundle-v1.0.0.tgz
├── bin/                    # Launcher scripts (server, stop, status)
├── config/                 # Plugin configs (.spc files go here)
├── steampipe/              # Steampipe binary
├── db/                     # Embedded PostgreSQL
├── plugins/                # Plugin binaries
├── config-templates/       # Example configs (copy to config/)
├── steampipe.env.example   # Environment config template
└── systemd/                # Optional systemd integration
```

### Mode 2: Native (Local Testing on WSL/RHEL/AlmaLinux)

Run steampipe directly without Docker. Ideal for local development and testing.

```bash
# 1. Install oras (one-time)
VERSION=1.3.0
curl -LO https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz
tar -zxf oras_${VERSION}_linux_amd64.tar.gz
sudo mv oras /usr/local/bin/  # or ~/.local/bin/

# 2. Download artifacts (requires internet)
scripts/download.sh

# 3. Install natively
scripts/install-native.sh

# 4. Configure credentials
# Edit ~/.steampipe/config/*.spc with your credentials

# 5. Start service
scripts/run-native.sh

# 6. Query
psql -h localhost -p 9193 -U steampipe -d steampipe

# Stop when done
scripts/stop-native.sh
```

### Mode 2: Docker Compose (Remote Deployment)

Run steampipe in a container. Used for production deployments via GitLab pipeline.

```bash
# On a machine with internet: download artifacts
scripts/download.sh

# Stage to target server
scripts/stage_artifacts.sh mars /apps/data/steam-engine fadzi

# On target: build and run (or let pipeline handle it)
scripts/build.sh
docker compose up -d
```

## Air-Gapped Deployment

For environments without internet access:

```bash
# 1. On connected machine: download all artifacts
scripts/download.sh

# 2. Transfer artifacts to air-gapped environment
scp -r artifacts/* user@target:/path/to/steam-engine/artifacts/

# 3. On air-gapped machine: build and run
scripts/build.sh
docker compose up -d
```

## CI/CD Pipeline

GitLab pipeline deploys to target server automatically.

**Pre-requisites (once before first deployment):**

1. Download and stage artifacts:
```bash
scripts/download.sh
scripts/stage_artifacts.sh
```

2. Configure credentials on server:
```bash
ssh mars "mkdir -p /apps/data/steam-engine/shared/config"
ssh mars "vi /apps/data/steam-engine/shared/config/jira.spc"
ssh mars "vi /apps/data/steam-engine/shared/config/gitlab.spc"
ssh mars "vi /apps/data/steam-engine/shared/config/bitbucket.spc"
```

Both `shared/artifacts/` and `shared/config/` persist across releases.

## Testing the Bundle

Test deployment in an AlmaLinux 9 container before deploying to production:

```bash
# Build and test in one command
./test/run-test.sh

# Keep container running for debugging
./test/run-test.sh --keep
psql -h localhost -p 9193 -U steampipe -d steampipe
```

The test script:
1. Builds the bundle (if not already built)
2. Spins up an AlmaLinux 9 container
3. Extracts and starts steampipe
4. Runs smoke tests (connection, version, plugin check)
5. Cleans up

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `build_steampipe_bundle.sh` | Build self-contained bundle tarball |
| `test/run-test.sh` | Test bundle deployment in AlmaLinux 9 container |
| `test_bundle.sh` | Verify bundle integrity after extraction |
| `scripts/download.sh` | Download artifacts via oras/curl (requires internet) |
| `scripts/install-native.sh` | Install steampipe natively (no Docker) |
| `scripts/run-native.sh` | Start steampipe service natively |
| `scripts/stop-native.sh` | Stop steampipe service |
| `scripts/build.sh` | Build Docker image from artifacts |
| `scripts/stage_artifacts.sh` | Copy artifacts to remote server |

## Notes

- **Jira DC requires jira@1.1.0** - Plugin 2.x uses Cloud v3 API which doesn't work with Data Center
- Based on AlmaLinux 9
- Offline build uses `Dockerfile.offline` with pre-downloaded artifacts
- Artifact versions configured in `versions.conf`
