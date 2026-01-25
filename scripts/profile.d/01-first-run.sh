#!/bin/bash
# Check if steampipe needs installation on login
if [ ! -x "/opt/steampipe/steampipe/steampipe" ]; then
    echo ""
    echo "=========================================="
    echo "  Steampipe installation required!"
    echo "=========================================="
    echo ""
    echo "Run: install-steampipe.sh"
    echo ""
fi
