#!/bin/bash
# Change to home directory on WSL login
#
# WSL defaults to Windows CWD; this ensures we land in $HOME

if [[ -n "$WSL_DISTRO_NAME" && "$PWD" == /mnt/* ]]; then
    cd "$HOME" || true
fi
