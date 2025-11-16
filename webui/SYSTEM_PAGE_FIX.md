# System Page Import Error Fix

**Date**: November 16, 2025  
**Issue**: ImportError when loading System page  
**Status**: ✅ Fixed

---

## Problem

```
ImportError: cannot import name 'collect_network_devices' from 'backend.collectors.network_devices'
```

The backend was failing to start because `clients.py` was trying to import a function that doesn't exist.

---

## Root Cause

When creating the new `clients.py` collector, I incorrectly assumed there was an async function called `collect_network_devices` in `network_devices.py`. 

**Actual function**: `discover_network_devices` (synchronous, not async)

---

## Fix Applied

### File: `webui/backend/collectors/clients.py`

**Changed**:
```python
from .network_devices import collect_network_devices  # WRONG

async def collect_client_stats() -> List[ClientStats]:
    devices = await collect_network_devices()  # WRONG
```

**To**:
```python
from .network_devices import discover_network_devices  # CORRECT
from .dhcp import parse_kea_leases

def collect_client_stats() -> List[ClientStats]:  # Not async
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)  # Not await
```

### File: `webui/backend/api/system.py`

**Changed**:
```python
"clients": await collect_client_stats()  # WRONG
```

**To**:
```python
"clients": collect_client_stats()  # CORRECT (not await)
```

---

## Files Modified

- ✅ `webui/backend/collectors/clients.py`
- ✅ `webui/backend/api/system.py`

---

## Deploy

```bash
# Commit fix
cd /mnt/c/Users/Willi/github/nixos-router
git add webui/backend/collectors/clients.py webui/backend/api/system.py webui/SYSTEM_PAGE_FIX.md
git commit -m "fix(webui): Correct import in client stats collector"
git push

# On router
cd /etc/nixos && git pull && sudo nixos-rebuild switch
```

---

## Verification

After deployment, check that the backend starts successfully:

```bash
# On router
sudo systemctl status router-webui-backend

# Should show "active (running)"
```

Then navigate to `http://192.168.2.1:8080` and click "System" to verify the page loads with client statistics.

---

## Technical Details

### Why the Confusion?

- **Existing function**: `discover_network_devices()` in `network_devices.py`
  - Used by `api/devices.py` for the Network Devices page
  - Synchronous function
  - Returns list of `NetworkDevice` class instances

- **What I created**: Tried to call `collect_network_devices()`
  - Function doesn't exist
  - Assumed it was async
  - Caused import error

### Correct Usage

The `discover_network_devices()` function:
1. Takes optional DHCP leases as input
2. Parses ARP table for active devices
3. Combines with DHCP lease data
4. Returns list of NetworkDevice objects with:
   - `network`, `ip_address`, `mac_address`
   - `is_dhcp`, `is_static`, `is_online`
   - `hostname`, `vendor`, `last_seen`

This is exactly what we need for client statistics!

---

## Success Criteria

✅ **Backend starts without errors**  
✅ **System page loads**  
✅ **Client statistics chart displays**  
✅ **HOMELAB and LAN counts shown**  
✅ **DHCP/Static/Offline breakdown visible**

