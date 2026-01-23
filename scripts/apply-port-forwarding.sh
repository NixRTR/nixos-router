#!/usr/bin/env bash
# Apply port forwarding rules from config/port-forwarding.nix to iptables
# This script can be run manually to apply rules without using the WebUI

set -euo pipefail

# Check if we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# The backend source is in the Nix store, but we can use systemctl to get the environment
# Or we can use the Python from the router-webui service
# The simplest approach: use systemctl show to get the ExecStart command and extract paths

# Try to find Python from the router-webui service environment
PYTHON_BIN=""
BACKEND_PATH=""

# Method 1: Check if router-webui-backend service is running and get its environment
if systemctl is-active --quiet router-webui-backend.service 2>/dev/null; then
    # Get the Python path from the service
    PYTHON_BIN=$(systemctl show router-webui-backend.service -p ExecStart --value 2>/dev/null | sed -n 's|.*\(/nix/store/[^/]*/bin/python[^ ]*\).*|\1|p' | head -1)
    # Get backend path from WorkingDirectory
    BACKEND_PATH=$(systemctl show router-webui-backend.service -p WorkingDirectory --value 2>/dev/null)/backend
fi

# Method 2: Fallback - use system Python and find backend in common locations
if [ -z "$PYTHON_BIN" ]; then
    if command -v python3 &> /dev/null; then
        PYTHON_BIN="python3"
    elif [ -f "/run/current-system/sw/bin/python3" ]; then
        PYTHON_BIN="/run/current-system/sw/bin/python3"
    else
        echo "Error: Could not find Python 3" >&2
        exit 1
    fi
fi

# Find backend source - check Nix store or use WorkingDirectory from service
if [ -z "$BACKEND_PATH" ] || [ ! -d "$BACKEND_PATH" ]; then
    # Try to find it in the Nix store
    BACKEND_PATH=$(find /nix/store -type d -path "*/router-webui/backend" -prune 2>/dev/null | head -1)
    
    if [ -z "$BACKEND_PATH" ] || [ ! -d "$BACKEND_PATH" ]; then
        echo "Error: Could not find backend source directory" >&2
        echo "Please ensure router-webui is installed and configured" >&2
        echo "Tried: $BACKEND_PATH" >&2
        exit 1
    fi
fi

echo "Applying port forwarding rules from /etc/nixos/config/port-forwarding.nix..."
echo "Using Python: $PYTHON_BIN"
echo "Using backend: $BACKEND_PATH"

# Set PYTHONPATH and run the applier
export PYTHONPATH="$BACKEND_PATH/.."
"$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$BACKEND_PATH')
from utils.port_forwarding_applier import apply_port_forwarding_rules
apply_port_forwarding_rules()
"

echo ""
echo "Port forwarding rules applied successfully!"
echo ""
echo "To verify, run: sudo iptables -t nat -L WEBUI_PORT_FORWARD -v -n"
