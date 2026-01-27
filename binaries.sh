#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"

# === Versions ===
STEAMPIPE_VERSION="2.3.4"
POSTGRES_VERSION="14.19.0"
FDW_VERSION="2.1.4"

# === URLs ===
STEAMPIPE_URL="https://github.com/turbot/steampipe/releases/download/v${STEAMPIPE_VERSION}/steampipe_linux_amd64.tar.gz"
FDW_BASE_URL="https://github.com/turbot/steampipe-postgres-fdw/releases/download/v${FDW_VERSION}"
GATEWAY_URL="https://github.com/kingfadzi/gateway/releases/download/v1.0.0/jira-sync-service-1.0.0-SNAPSHOT.jar"

# PostgreSQL 14 RPMs (PGDG for RHEL 9)
PGDG_BASE_URL="https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-9-x86_64"

# Plugins (mirrored from ghcr.io to bundler)
JIRA_PLUGIN_VERSION="1.1.0"
GITLAB_PLUGIN_VERSION="0.6.0"
BUNDLER_BASE_URL="https://github.com/kingfadzi/steampipe-bundler/releases/download/v20260125"
JIRA_PLUGIN_URL="${BUNDLER_BASE_URL}/steampipe-plugin-jira-${JIRA_PLUGIN_VERSION}-linux-amd64.tar.gz"
GITLAB_PLUGIN_URL="${BUNDLER_BASE_URL}/steampipe-plugin-gitlab-${GITLAB_PLUGIN_VERSION}-linux-amd64.tar.gz"

# Parse arguments
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
    esac
done

download_binary() {
    local name="$1"
    local url="$2"
    local dest="$3"

    if [[ -f "$BINARIES_DIR/$dest" ]] && [[ "$FORCE" != "true" ]]; then
        echo "✓ Exists: $dest"
        return
    fi

    echo "↓ Downloading: $name"
    curl -fL# "$url" -o "$BINARIES_DIR/$dest"
    echo "  Done: $(du -h "$BINARIES_DIR/$dest" | cut -f1)"
}

mkdir -p "$BINARIES_DIR"

echo "=== Downloading Steampipe Components ==="
echo ""

# Steampipe CLI
download_binary "Steampipe CLI v${STEAMPIPE_VERSION}" \
    "$STEAMPIPE_URL" \
    "steampipe_linux_amd64.tar.gz"

# PostgreSQL 14.19 RPMs (matches steampipe expected version)
download_binary "PostgreSQL 14.19 Server" \
    "${PGDG_BASE_URL}/postgresql14-server-14.19-1PGDG.rhel9.x86_64.rpm" \
    "postgresql14-server.rpm"

download_binary "PostgreSQL 14.19 Libs" \
    "${PGDG_BASE_URL}/postgresql14-libs-14.19-1PGDG.rhel9.x86_64.rpm" \
    "postgresql14-libs.rpm"

download_binary "PostgreSQL 14.19 Client" \
    "${PGDG_BASE_URL}/postgresql14-14.19-1PGDG.rhel9.x86_64.rpm" \
    "postgresql14.rpm"

download_binary "PostgreSQL 14.19 Contrib" \
    "${PGDG_BASE_URL}/postgresql14-contrib-14.19-1PGDG.rhel9.x86_64.rpm" \
    "postgresql14-contrib.rpm"

# FDW
download_binary "FDW binary v${FDW_VERSION}" \
    "${FDW_BASE_URL}/steampipe_postgres_fdw.so.linux_amd64.gz" \
    "steampipe_postgres_fdw.so.gz"

download_binary "FDW control v${FDW_VERSION}" \
    "${FDW_BASE_URL}/steampipe_postgres_fdw.control" \
    "steampipe_postgres_fdw.control"

download_binary "FDW SQL v${FDW_VERSION}" \
    "${FDW_BASE_URL}/steampipe_postgres_fdw--1.0.sql" \
    "steampipe_postgres_fdw--1.0.sql"

# Gateway
download_binary "Gateway" \
    "$GATEWAY_URL" \
    "gateway.jar"

# Plugins
download_binary "Jira Plugin v${JIRA_PLUGIN_VERSION}" \
    "$JIRA_PLUGIN_URL" \
    "steampipe-plugin-jira.tar.gz"

download_binary "GitLab Plugin v${GITLAB_PLUGIN_VERSION}" \
    "$GITLAB_PLUGIN_URL" \
    "steampipe-plugin-gitlab.tar.gz"

echo ""
echo "=== Done ==="
ls -lh "$BINARIES_DIR/"
