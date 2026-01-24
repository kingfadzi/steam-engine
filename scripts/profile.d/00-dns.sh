#!/bin/bash
# Set DNS from baked-in config (per profile)
if [ -f /etc/resolv.conf.wsl ]; then
    sudo cp /etc/resolv.conf.wsl /etc/resolv.conf 2>/dev/null || true
fi
