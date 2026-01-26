#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"

# === Binary URLs ===
STEAMPIPE_BUNDLE_URL="https://github.com/kingfadzi/steampipe-bundler/releases/download/v20260125/steampipe-bundle-20260125.tgz"
GATEWAY_URL="https://github.com/kingfadzi/gateway/releases/download/v1.0.0/jira-sync-service-1.0.0-SNAPSHOT.jar"

# Steampipe CLI RPM
STEAMPIPE_VERSION="1.0.1"
STEAMPIPE_RPM_URL="https://github.com/turbot/steampipe/releases/download/v${STEAMPIPE_VERSION}/steampipe_linux_amd64.rpm"

# PostgreSQL RPMs
POSTGRES_VERSION="14.20"
PGDG_URL="https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-9-x86_64"
POSTGRES_RPMS=(
    "postgresql14-libs-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
    "postgresql14-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
    "postgresql14-server-${POSTGRES_VERSION}-1PGDG.rhel9.x86_64.rpm"
)

# Parse arguments
FORCE=false
ACTION=""
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --fetch-pg|postgres) ACTION="postgres" ;;
        --all) ACTION="all" ;;
    esac
done

download_binary() {
    local name="$1"
    local url="$2"
    local dest="$3"

    if [[ -f "$BINARIES_DIR/$dest" ]] && [[ "$FORCE" != "true" ]]; then
        echo "Exists: $dest (use --force to re-download)"
        return
    fi

    echo "Downloading: $name → $dest"
    curl -fL# "$url" -o "$BINARIES_DIR/$dest"
    echo "  Done: $(du -h "$BINARIES_DIR/$dest" | cut -f1)"
}

fetch_postgres() {
    echo "=== Fetching PostgreSQL $POSTGRES_VERSION RPMs ==="
    mkdir -p "$BINARIES_DIR/postgres"

    for rpm in "${POSTGRES_RPMS[@]}"; do
        local dest="$BINARIES_DIR/postgres/$rpm"
        if [[ -f "$dest" ]] && [[ "$FORCE" != "true" ]]; then
            echo "Exists: $rpm"
        else
            echo "Downloading: $rpm"
            curl -fL# "$PGDG_URL/$rpm" -o "$dest"
        fi
    done

    echo "=== PostgreSQL RPMs ready ==="
    ls -lh "$BINARIES_DIR/postgres/"
}

fetch_steampipe_gateway() {
    echo "=== Downloading binaries ==="
    download_binary "Steampipe Bundle (for FDW)" "$STEAMPIPE_BUNDLE_URL" "steampipe-bundle.tgz"
    download_binary "Steampipe RPM" "$STEAMPIPE_RPM_URL" "steampipe_linux_amd64.rpm"
    download_binary "Gateway" "$GATEWAY_URL" "gateway.jar"
    echo "=== Done ==="
}

mkdir -p "$BINARIES_DIR"

case "$ACTION" in
    postgres)
        fetch_postgres
        ;;
    all)
        fetch_steampipe_gateway
        fetch_postgres
        ;;
    *)
        fetch_steampipe_gateway
        ;;
esac
