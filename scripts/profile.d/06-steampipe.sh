#!/bin/bash
# Steampipe environment setup
# Force-set critical paths (may be lost on docker export to WSL)

export STEAMPIPE_INSTALL_DIR="$HOME/.steampipe"
export STEAMPIPE_MOD_LOCATION="$HOME/.steampipe"
export PATH="$HOME/.steampipe/steampipe:$HOME/.local/bin:$PATH"

# Aliases
alias sp='steampipe'
alias spq='steampipe query'
alias sps='steampipe service status'
