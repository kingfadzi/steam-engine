#!/bin/bash
#
# Build self-contained Steampipe bundle for air-gapped WSL deployment
#
# This script creates a single tarball that can be extracted and run anywhere.
# Configs are externalized and mounted from host system (e.g., /etc/steampipe/).
#
# Usage:
#   ./build_steampipe_bundle.sh [version]
#
# Example:
#   ./build_steampipe_bundle.sh           # Uses version from versions.conf or "dev"
#   ./build_steampipe_bundle.sh v1.0.0    # Creates steampipe-bundle-v1.0.0.tgz
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"
BUNDLE_TEMPLATES_DIR="$SCRIPT_DIR/bundle-templates"
CONFIG_DIR="$SCRIPT_DIR/config"
BUILD_DIR="$SCRIPT_DIR/build"

# Source version configuration
if [ -f "$SCRIPT_DIR/versions.conf" ]; then
  source "$SCRIPT_DIR/versions.conf"
fi

# Bundle version from arg, env, or default
BUNDLE_VERSION="${1:-${BUNDLE_VERSION:-dev}}"
BUNDLE_NAME="steampipe-bundle-${BUNDLE_VERSION}"
BUNDLE_DIR="$BUILD_DIR/$BUNDLE_NAME"

echo "============================================"
echo "Steampipe Bundle Builder"
echo "============================================"
echo "Bundle:     $BUNDLE_NAME"
echo "Steampipe:  ${STEAMPIPE_VERSION:-unknown}"
echo "PostgreSQL: ${POSTGRES_VERSION:-unknown}"
echo "FDW:        ${FDW_VERSION:-unknown}"
echo "Plugins:    ${PLUGINS[*]:-unknown}"
echo "============================================"
echo

# ---- Step 1: Validate artifacts ----
echo "[1/7] Validating artifacts..."

missing=0
for artifact in steampipe_linux_amd64.tar.gz steampipe-plugins.tar.gz steampipe-db.tar.gz steampipe-internal.tar.gz; do
  if [ ! -f "$ARTIFACTS_DIR/$artifact" ]; then
    echo "  ERROR: Missing $artifact"
    missing=1
  else
    echo "  Found: $artifact"
  fi
done

if [ $missing -eq 1 ]; then
  echo ""
  echo "ERROR: Artifacts missing. Run 'scripts/download.sh' first."
  exit 1
fi
echo

# ---- Step 2: Validate templates ----
echo "[2/7] Validating bundle templates..."

for file in bin/common.sh bin/server bin/stop bin/status steampipe.env.example \
            systemd/steampipe.service systemd/install-service.sh config-templates/README.md; do
  if [ ! -f "$BUNDLE_TEMPLATES_DIR/$file" ]; then
    echo "  ERROR: Missing template: bundle-templates/$file"
    exit 1
  fi
done
echo "  All templates present"
echo

# ---- Step 3: Create bundle structure ----
echo "[3/7] Creating bundle structure..."

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"/{bin,config,steampipe,db,plugins,internal,config-templates,systemd}
echo "  Created directory structure"
echo

# ---- Step 4: Extract artifacts ----
echo "[4/7] Extracting artifacts..."

echo "  Extracting steampipe binary..."
tar -xzf "$ARTIFACTS_DIR/steampipe_linux_amd64.tar.gz" -C "$BUNDLE_DIR/steampipe"

echo "  Extracting plugins..."
tar -xzf "$ARTIFACTS_DIR/steampipe-plugins.tar.gz" -C "$BUNDLE_DIR/plugins"

echo "  Extracting database..."
tar -xzf "$ARTIFACTS_DIR/steampipe-db.tar.gz" -C "$BUNDLE_DIR/db"

echo "  Extracting internal files..."
tar -xzf "$ARTIFACTS_DIR/steampipe-internal.tar.gz" -C "$BUNDLE_DIR/internal"
echo

# ---- Step 5: Verify extraction ----
echo "[5/7] Verifying extracted artifacts..."

# Check steampipe binary
if [ ! -x "$BUNDLE_DIR/steampipe/steampipe" ]; then
  chmod +x "$BUNDLE_DIR/steampipe/steampipe"
fi

if [ ! -x "$BUNDLE_DIR/steampipe/steampipe" ]; then
  echo "  ERROR: steampipe binary not executable"
  exit 1
fi
echo "  Steampipe binary: OK"

# Check plugins
PLUGIN_COUNT=$(find "$BUNDLE_DIR/plugins" -name "*.plugin" 2>/dev/null | wc -l)
echo "  Plugins found: $PLUGIN_COUNT"
if [ "$PLUGIN_COUNT" -eq 0 ]; then
  echo "  ERROR: No plugins found!"
  exit 1
fi

# Check postgres
if [ ! -d "$BUNDLE_DIR/db/${POSTGRES_VERSION:-14.19.0}/postgres" ]; then
  echo "  WARNING: PostgreSQL directory structure may differ"
  # List what we have
  find "$BUNDLE_DIR/db" -maxdepth 2 -type d | head -5
fi
echo "  PostgreSQL: OK"

# Check internal files
if [ ! -f "$BUNDLE_DIR/internal/.passwd" ]; then
  echo "  ERROR: Missing internal/.passwd"
  exit 1
fi
echo "  Internal files: OK"
echo

# ---- Step 6: Copy templates and scripts ----
echo "[6/7] Copying launcher scripts and templates..."

# Copy bin scripts
cp "$BUNDLE_TEMPLATES_DIR/bin/common.sh" "$BUNDLE_DIR/bin/"
cp "$BUNDLE_TEMPLATES_DIR/bin/server" "$BUNDLE_DIR/bin/"
cp "$BUNDLE_TEMPLATES_DIR/bin/stop" "$BUNDLE_DIR/bin/"
cp "$BUNDLE_TEMPLATES_DIR/bin/status" "$BUNDLE_DIR/bin/"
chmod +x "$BUNDLE_DIR/bin/"*
echo "  Copied bin/ scripts"

# Copy env example
cp "$BUNDLE_TEMPLATES_DIR/steampipe.env.example" "$BUNDLE_DIR/"
echo "  Copied steampipe.env.example"

# Copy systemd files
cp "$BUNDLE_TEMPLATES_DIR/systemd/steampipe.service" "$BUNDLE_DIR/systemd/"
cp "$BUNDLE_TEMPLATES_DIR/systemd/install-service.sh" "$BUNDLE_DIR/systemd/"
chmod +x "$BUNDLE_DIR/systemd/install-service.sh"
echo "  Copied systemd/ files"

# Copy config templates
cp "$BUNDLE_TEMPLATES_DIR/config-templates/README.md" "$BUNDLE_DIR/config-templates/"
for spc in jira.spc gitlab.spc bitbucket.spc; do
  if [ -f "$CONFIG_DIR/$spc" ]; then
    cp "$CONFIG_DIR/$spc" "$BUNDLE_DIR/config-templates/"
    echo "  Copied $spc"
  fi
done

# Copy test script
cp "$SCRIPT_DIR/test_bundle.sh" "$BUNDLE_DIR/" 2>/dev/null || true
if [ -f "$BUNDLE_DIR/test_bundle.sh" ]; then
  chmod +x "$BUNDLE_DIR/test_bundle.sh"
  echo "  Copied test_bundle.sh"
fi

# Create VERSION file
cat > "$BUNDLE_DIR/VERSION" << EOF
Bundle Version: $BUNDLE_VERSION
Build Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Steampipe: ${STEAMPIPE_VERSION:-unknown}
PostgreSQL: ${POSTGRES_VERSION:-unknown}
FDW: ${FDW_VERSION:-unknown}
Plugins: ${PLUGINS[*]:-unknown}
EOF
echo "  Created VERSION file"
echo

# ---- Step 7: Create tarball ----
echo "[7/7] Creating tarball..."

mkdir -p "$BUILD_DIR"
TARBALL="$BUILD_DIR/${BUNDLE_NAME}.tgz"
tar -czf "$TARBALL" -C "$BUNDLE_DIR" .

SIZE=$(du -h "$TARBALL" | cut -f1)
echo "  Created: $TARBALL"
echo "  Size: $SIZE"
echo

# ---- Done ----
echo "============================================"
echo "Build complete!"
echo "============================================"
echo
echo "Output: $TARBALL"
echo
echo "To test the build (before deploying):"
echo "  mkdir -p /tmp/steampipe-test"
echo "  tar -xzf $TARBALL -C /tmp/steampipe-test"
echo "  /tmp/steampipe-test/test_bundle.sh"
echo
echo "To deploy:"
echo "  1. sudo mkdir -p /opt/steampipe"
echo "  2. sudo tar -xzf $TARBALL -C /opt/steampipe"
echo "  3. sudo cp /opt/steampipe/config-templates/*.spc /opt/steampipe/config/"
echo "  4. Edit /opt/steampipe/config/*.spc with your credentials"
echo "  5. cd /opt/steampipe && ./bin/server"
echo
