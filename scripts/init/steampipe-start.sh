#!/bin/bash
#
# Steampipe service start script
# Steampipe and embedded postgres are pre-built in the image
#
set -e

HOME_DIR="/home/fadzi"
INSTALL_DIR="$HOME_DIR/.steampipe"

# Environment
export STEAMPIPE_INSTALL_DIR="$INSTALL_DIR"
export STEAMPIPE_UPDATE_CHECK=false
export HOME="$HOME_DIR"

# Start steampipe
exec steampipe service start --foreground
