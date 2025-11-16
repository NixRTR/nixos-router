# Deploy MAC-Based DHCP Tracking

## Quick Deployment Guide

### Step 1: Update Code on Router

```bash
# On your router (SSH)
cd /etc/nixos

# Pull latest changes
git pull

# OR manually copy files if needed:
# From Windows: scp -r webui/backend routeradmin@192.168.2.1:/etc/nixos/webui/
```

### Step 2: Choose Migration Strategy

#### Option A: Migrate Existing Data (Recommended)
Preserves existing DHCP client information.

```bash
cd /etc/nixos/webui/backend/migrations
chmod +x migrate.sh
./migrate.sh
```

#### Option B: Fresh Start (Simpler)
Loses existing DHCP history, but will rebuild quickly.

```bash
sudo systemctl stop router-webui-backend
sudo -u postgres psql -d router_webui -c "DROP TABLE IF EXISTS dhcp_leases CASCADE;"
```

### Step 3: Rebuild System

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

### Step 4: Verify

```bash
# Check service status
sudo systemctl status router-webui-backend

# Watch logs (should see NO constraint errors)
sudo journalctl -u router-webui-backend -f
```

Press Ctrl+C after 30 seconds. You should see:
- ✅ No "UniqueViolationError" messages
- ✅ "Stored metrics" messages every few seconds
- ✅ WebSocket connections working

### Step 5: Test WebUI

1. Open http://192.168.2.1:8080
2. Login with your system credentials
3. Navigate to:
   - **Dashboard** - Should show client counts
   - **DHCP Clients** - Should list devices by MAC
   - **Network Bandwidth** - Should show graphs (after ~30 seconds)

## Expected Results

### Before Fix
```
journalctl output:
Error storing metrics: UniqueViolationError: duplicate key value violates unique constraint
Error storing metrics: UniqueViolationError: duplicate key value violates unique constraint
...

WebUI:
❌ No bandwidth data available
❌ Client list errors
❌ Metrics not updating
```

### After Fix
```
journalctl output:
INFO: WebSocket connection established
INFO: Broadcasting metrics to 1 clients
INFO: Broadcasting metrics to 1 clients
...

WebUI:
✅ Bandwidth graphs showing data
✅ Client list populated
✅ Real-time updates working
✅ Device tracking across IP changes
```

## Files Changed

- `webui/backend/database.py` - Updated schema with composite unique constraints
- `webui/backend/collectors/dhcp.py` - Deduplicate by MAC instead of IP
- `webui/backend/websocket.py` - Upsert based on MAC instead of IP
- `webui/backend/schema.sql` - Updated documentation
- `webui/backend/migrations/001_mac_based_tracking.sql` - Migration script
- `webui/backend/migrations/migrate.sh` - Migration helper

## Troubleshooting

### Migration Fails
```bash
# Check existing constraints
sudo -u postgres psql -d router_webui -c "\d dhcp_leases"

# Manually drop old constraint if needed
sudo -u postgres psql -d router_webui -c "DROP INDEX IF EXISTS dhcp_leases_ip_address_key;"

# Try migration again
cd /etc/nixos/webui/backend/migrations
./migrate.sh
```

### Service Won't Start
```bash
# Check detailed error
sudo journalctl -u router-webui-backend -n 50 --no-pager

# Verify database connection
sudo -u router-webui psql -d router_webui -c "SELECT COUNT(*) FROM dhcp_leases;"

# Reset if needed (Option B above)
```

### Still Seeing Errors
```bash
# Verify you have the latest code
cd /etc/nixos
git log --oneline -n 5

# Check which version is running
sudo systemctl status router-webui-backend | grep "Main PID"
ps aux | grep [p]ython | grep webui

# Force restart
sudo systemctl restart router-webui-backend
```

## Rollback (If Needed)

```bash
cd /etc/nixos
git log --oneline  # Find previous commit
git checkout <commit-hash>
sudo nixos-rebuild switch
sudo systemctl restart router-webui-backend
```

## Summary of Changes

| Aspect | Before | After |
|--------|--------|-------|
| Primary Key | IP address | (network, MAC address) |
| Duplicate Detection | By IP | By (network, MAC) |
| Device Tracking | Lost on IP change | Preserved across IP changes |
| Client Count | IPs (inaccurate) | Devices (accurate) |
| Constraint Errors | Yes, frequent | No, resolved |
| Bandwidth Data | Not storing | Storing successfully |

## Performance Impact

- ✅ No negative performance impact
- ✅ Same number of database operations
- ✅ Slightly better deduplication (less data to store)
- ✅ More accurate metrics

## Next Steps

After successful deployment:

1. Monitor for 24 hours to ensure stability
2. Verify device tracking across DHCP renewals
3. Check client list accuracy
4. Confirm bandwidth graphs populate correctly
5. (Optional) Clean up old DHCP history if desired

## Questions?

See `MAC_BASED_TRACKING.md` for detailed technical information.

