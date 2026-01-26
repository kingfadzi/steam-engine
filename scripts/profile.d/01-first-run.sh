#!/bin/bash
# Check if steampipe needs first-time initialization
if [ ! -x "$HOME/.steampipe/steampipe/steampipe" ]; then
    echo ""
    echo "=========================================="
    echo "  Steampipe first-time setup pending"
    echo "=========================================="
    echo ""
    echo "The steampipe service will auto-initialize on first start."
    echo "Check service status: systemctl status steampipe"
    echo ""
fi
