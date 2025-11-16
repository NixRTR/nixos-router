# Deploy WebUI Fixes - Complete Guide

## What's Being Fixed

This deployment includes **two critical fixes**:

### 1. DHCP MAC-Based Tracking
- **Problem**: Database constraint errors, lost device tracking, no bandwidth data storing
- **Solution**: Track devices by MAC address instead of IP address
- **Files**: `database.py`, `collectors/dhcp.py`, `websocket.py`

### 2. Bandwidth API Parameter Shadowing
- **Problem**: Bandwidth history API crashed with `TypeError: 'str' object is not callable`
- **Solution**: Renamed `range` parameter to `time_range` to avoid shadowing Python built-in
- **Files**: `api/bandwidth.py`

---

## Quick Deployment (Production Router)

### Step 1: Update Code

```bash
# SSH to your router
ssh routeradmin@192.168.2.1

# Navigate to config directory
cd /etc/nixos

# Pull latest changes
git pull
```

### Step 2: Run Database Migration

Choose one option:

**Option A: Migrate Existing Data** (Recommended - preserves history)
```bash
cd /etc/nixos/webui/backend/migrations
chmod +x migrate.sh
./migrate.sh
```

**Option B: Fresh Start** (Simpler - loses history, rebuilds quickly)
```bash
sudo systemctl stop router-webui-backend
sudo -u postgres psql -d router_webui -c "DROP TABLE IF EXISTS dhcp_leases CASCADE;"
# Table will be recreated on service restart
```

### Step 3: Rebuild System

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

This will take a few minutes to build and activate the new configuration.

### Step 4: Verify

```bash
# Watch the logs
sudo journalctl -u router-webui-backend -f
```

**What you should see** (after 10-30 seconds):
```
INFO: Started server process [xxxxx]
INFO: Application startup complete.
INFO: Uvicorn running on http://0.0.0.0:8080
INFO: WebSocket connection established
INFO: 192.168.2.11:xxxxx - "GET /api/bandwidth/history?interface=ppp0&range=1h HTTP/1.1" 200 OK
```

**What you should NOT see:**
```
❌ Error storing metrics: UniqueViolationError
❌ TypeError: 'str' object is not callable
```

Press Ctrl+C to exit the logs once you've verified it's working.

### Step 5: Test WebUI

1. Open http://192.168.2.1:8080
2. Login with your system credentials
3. Check each page:
   - **Dashboard** ✅ Should show client counts and system stats
   - **Network Bandwidth** ✅ Should show graphs with data (wait 30 seconds)
   - **DHCP Clients** ✅ Should list devices by MAC address
   - **Service Status** ✅ Should show running services

---

## Expected Results

### Before Fixes
```
Logs:
❌ Error storing metrics: UniqueViolationError: duplicate key...
❌ TypeError: 'str' object is not callable
❌ Error storing metrics... (repeating every 2 seconds)

WebUI:
❌ No bandwidth data available
❌ Client list may show errors
❌ Metrics not updating
❌ API 500 errors on Network page
```

### After Fixes
```
Logs:
✅ INFO: Broadcasting metrics to X clients
✅ INFO: GET /api/bandwidth/history... 200 OK
✅ INFO: WebSocket connection established
✅ (No error messages)

WebUI:
✅ Bandwidth graphs showing real-time data
✅ Client list populated with devices
✅ Historical charts working
✅ Device tracking preserved across IP changes
✅ Real-time updates smooth
```

---

## Troubleshooting

### Migration Fails

```bash
# Check database schema
sudo -u postgres psql -d router_webui -c "\d dhcp_leases"

# If old constraint exists, manually drop it
sudo -u postgres psql -d router_webui -c "DROP INDEX IF EXISTS dhcp_leases_ip_address_key;"

# Try migration again
cd /etc/nixos/webui/backend/migrations
./migrate.sh
```

### Service Won't Start

```bash
# Check detailed error
sudo journalctl -u router-webui-backend -n 100 --no-pager

# Verify database is accessible
sudo -u postgres psql -d router_webui -c "SELECT COUNT(*) FROM dhcp_leases;"

# Force service restart
sudo systemctl restart router-webui-backend
```

### Still Seeing Errors

```bash
# Verify you have latest code
cd /etc/nixos
git log --oneline -n 5

# Check running process
sudo systemctl status router-webui-backend

# Rebuild if needed
sudo nixos-rebuild switch
sudo systemctl restart router-webui-backend
```

### Bandwidth API Still Failing

```bash
# Verify the fix is deployed
grep "time_range" /nix/store/*/webui/backend/api/bandwidth.py

# Should show the parameter renamed to time_range
# If not, the old code is still running - rebuild needed
```

---

## Rollback (If Needed)

```bash
cd /etc/nixos
git log --oneline  # Find previous commit
git checkout <previous-commit-hash>

# Restore old database schema
sudo -u postgres psql -d router_webui <<EOF
DROP INDEX IF EXISTS idx_dhcp_network_mac;
DROP INDEX IF EXISTS idx_dhcp_network_ip;
CREATE UNIQUE INDEX dhcp_leases_ip_address_key ON dhcp_leases(ip_address);
EOF

# Rebuild
sudo nixos-rebuild switch
sudo systemctl restart router-webui-backend
```

---

## What Changed

### Code Changes

| File | Change | Reason |
|------|--------|--------|
| `database.py` | Added composite unique indexes | Track devices by MAC+network |
| `collectors/dhcp.py` | Deduplicate by (network, MAC) | Prevent duplicate device entries |
| `websocket.py` | Upsert by MAC instead of IP | Update device records correctly |
| `schema.sql` | Updated documentation | Reflect new schema design |
| `api/bandwidth.py` | Renamed `range` → `time_range` | Fix Python built-in shadowing |

### Database Schema

```sql
-- Before: Single unique constraint on IP
ip_address INET NOT NULL UNIQUE

-- After: Two composite unique constraints
UNIQUE INDEX idx_dhcp_network_mac ON (network, mac_address)
UNIQUE INDEX idx_dhcp_network_ip ON (network, ip_address)
```

### API Changes

```python
# Before: Shadowed built-in
def get_bandwidth_history(range: str, ...):

# After: No shadowing, API compatible
def get_bandwidth_history(time_range: str = Query(..., alias="range"), ...):
```

---

## Performance

- **No performance degradation** expected
- **Database**: Same number of queries, better deduplication
- **CPU/Memory**: No significant change
- **Network**: No change

---

## Next Steps

After successful deployment:

1. ✅ Monitor for 24 hours to ensure stability
2. ✅ Verify device tracking works across DHCP renewals
3. ✅ Confirm bandwidth charts populate correctly
4. ✅ Test all WebUI pages for functionality
5. ✅ Check client count accuracy matches reality

---

## Documentation

For more details, see:

- `MAC_BASED_TRACKING.md` - Technical details on DHCP changes
- `BANDWIDTH_API_FIX.md` - Details on API parameter fix
- `DEPLOY_MAC_TRACKING.md` - Detailed DHCP migration guide
- `IMPLEMENTATION_MAC_TRACKING.md` - Full implementation summary

---

## Questions?

If issues persist:

1. Check logs: `sudo journalctl -u router-webui-backend -f`
2. Verify schema: `sudo -u postgres psql -d router_webui -c "\d dhcp_leases"`
3. Check data: `sudo -u postgres psql -d router_webui -c "SELECT * FROM dhcp_leases LIMIT 5;"`
4. Review this guide again
5. Consider fresh start (Option B) if migration is problematic

**Status**: Both fixes tested and ready for deployment 🚀

