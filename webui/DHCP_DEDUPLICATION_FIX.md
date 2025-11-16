# DHCP Lease Deduplication Fix

## Problem

The WebUI backend was experiencing two related issues:

1. **Database Constraint Errors**: Repeated errors about duplicate IP addresses:
   ```
   UniqueViolationError: duplicate key value violates unique constraint "dhcp_leases_ip_address_key"
   DETAIL: Key (ip_address)=(192.168.2.106) already exists.
   ```

2. **No Bandwidth Data**: The Network Bandwidth page showed "No bandwidth data available" despite the system collecting data.

## Root Cause

The Kea DHCP lease file (`/var/lib/kea/dhcp4.leases`) is a CSV file that can contain multiple entries for the same IP address (historical leases, renewed leases, etc.).

The `parse_kea_leases()` function was reading ALL entries and returning them as a list, including duplicates. When the storage function tried to insert these leases:

1. First lease with IP `192.168.2.106` → No conflict, added to session
2. Second lease with same IP → Also added to session (not yet committed)
3. On commit → Both try to INSERT → Unique constraint violation

Because the transaction failed, **ALL metrics** (bandwidth, system, services) were rolled back, preventing any data from being stored.

## Solution

Modified `webui/backend/collectors/dhcp.py` to deduplicate leases by IP address:

```python
# Use dict to automatically deduplicate by IP (keeps last occurrence)
leases_dict = {}

for row in reader:
    # ... parse lease data ...
    leases_dict[ip] = dhcp_lease  # Overwrites previous entry with same IP

return list(leases_dict.values())
```

This ensures each IP address appears only once in the returned list, using the most recent entry from the lease file.

## Impact

After this fix:
- ✅ DHCP lease database errors will be resolved
- ✅ Bandwidth and other metrics will be stored successfully
- ✅ Historical bandwidth charts will populate with data
- ✅ WebSocket real-time updates will work properly

## Deployment

The fix is in `webui/backend/collectors/dhcp.py`. To deploy:

```bash
# On your router
sudo systemctl restart router-webui-backend

# Monitor for errors
sudo journalctl -u router-webui-backend -f
```

You should immediately see the constraint errors stop appearing.

## Verification

1. Check logs - errors should stop:
   ```bash
   sudo journalctl -u router-webui-backend -n 50 --no-pager
   ```

2. Access WebUI - bandwidth data should appear after 10-30 seconds
   ```
   http://192.168.2.1:8080
   ```

3. Navigate to Network Bandwidth page - chart should populate

## Notes

- The database still has the UNIQUE constraint on `ip_address`, which is correct for maintaining current state
- The deduplication happens at collection time, preventing duplicates from reaching the storage layer
- Historical lease data is not stored; only the current state is maintained
- If you need historical lease tracking, the database schema would need modification (e.g., remove unique constraint, add effective_date ranges)

