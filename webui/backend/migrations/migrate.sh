#!/usr/bin/env bash
# Database migration script for Router WebUI
# Run this on the router after updating the code

set -e

echo "=================================="
echo "Router WebUI Database Migration"
echo "=================================="
echo ""
echo "This will update the DHCP leases table to track devices by MAC address"
echo "instead of IP address, allowing better device tracking across IP changes."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# Get database connection details from environment or defaults
DB_NAME="${ROUTER_WEBUI_DB_NAME:-router_webui}"
DB_USER="${ROUTER_WEBUI_DB_USER:-router_webui}"
DB_HOST="${ROUTER_WEBUI_DB_HOST:-localhost}"

echo ""
echo "Applying migration 001_mac_based_tracking.sql..."
echo ""

# Run migration
sudo -u postgres psql -d "$DB_NAME" -f "$(dirname "$0")/001_mac_based_tracking.sql"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Migration completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart the WebUI backend:"
    echo "     sudo systemctl restart router-webui-backend"
    echo ""
    echo "  2. Monitor for errors:"
    echo "     sudo journalctl -u router-webui-backend -f"
    echo ""
else
    echo ""
    echo "❌ Migration failed!"
    echo ""
    echo "Please check the error messages above and try again."
    exit 1
fi

