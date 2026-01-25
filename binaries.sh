#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"

# === Binary URLs ===
STEAMPIPE_URL="https://github.com/kingfadzi/steampipe-bundler/releases/download/v20260124/steampipe-bundle-20260124.tgz"
GATEWAY_URL="https://github.com/kingfadzi/gateway/releases/download/v1.0.0/jira-sync-service-1.0.0-SNAPSHOT.jar"

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
        echo "Exists: $dest (use --force to re-download)"
        return
    fi

    echo "Downloading: $name → $dest"
    curl -fL# "$url" -o "$BINARIES_DIR/$dest"
    echo "  Done: $(du -h "$BINARIES_DIR/$dest" | cut -f1)"
}

mkdir -p "$BINARIES_DIR"

echo "=== Downloading binaries ==="
download_binary "Steampipe" "$STEAMPIPE_URL" "steampipe-bundle.tgz"
download_binary "Gateway" "$GATEWAY_URL" "gateway.jar"
echo "=== Done ==="
