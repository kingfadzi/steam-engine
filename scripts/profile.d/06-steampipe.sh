#!/bin/bash
# Steampipe environment setup
# Force-set critical paths (may be lost on docker export to WSL)

export STEAMPIPE_INSTALL_DIR=/opt/steampipe
export STEAMPIPE_MOD_LOCATION=/opt/steampipe
export PATH="/opt/steampipe/steampipe:/opt/steampipe/bin:$PATH"

# Ensure HOME is set for service user context
export HOME="${HOME:-/opt/steampipe}"

# Aliases
alias sp='steampipe'
alias spq='steampipe query'
alias sps='steampipe service status'
