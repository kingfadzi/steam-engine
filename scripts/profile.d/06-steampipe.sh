#!/bin/bash
# Steampipe environment setup

export STEAMPIPE_INSTALL_DIR=/opt/steampipe
export PATH="/opt/steampipe/steampipe:/opt/steampipe/bin:$PATH"

# Aliases
alias sp='steampipe'
alias spq='steampipe query'
alias sps='steampipe service status'
