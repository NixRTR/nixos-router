# MAC-Based DHCP Lease Tracking

## Overview

The WebUI has been updated to track DHCP clients by MAC address (device) instead of IP address. This provides better device tracking and resolves several issues.

## Why This Change?

### Previous Design (IP-based)
```
dhcp_leases table:
  - ip_address UNIQUE  ← Primary identifier
  - mac_address
```

**Problems:**
1. ❌ Lost device history when IP changed
2. ❌ If Device A released `192.168.2.100` and Device B got it, we lost track of Device A
3. ❌ Duplicate entry errors when same IP appeared multiple times in Kea lease file
4. ❌ Client count showed IPs, not devices

### New Design (MAC-based)
```
dhcp_leases table:
  - (network, mac_address) UNIQUE  ← Device identifier
  - (network, ip_address) UNIQUE   ← No conflicts
```

**Benefits:**
1. ✅ Tracks unique devices across IP changes
2. ✅ Accurate device count
3. ✅ Device history preserved even when IP changes
4. ✅ Handles Kea lease file duplicates correctly
5. ✅ No more constraint violation errors

## What Changed

### 1. Database Schema (`database.py`)
```python
class DHCPLeaseDB(Base):
    # ...
    __table_args__ = (
        # Each device (MAC) can only have one active lease per network
        Index('idx_dhcp_network_mac', 'network', 'mac_address', unique=True),
        # Each IP can only be assigned once per network
        Index('idx_dhcp_network_ip', 'network', 'ip_address', unique=True),
    )
```

### 2. Data Collection (`collectors/dhcp.py`)
```python
# Deduplicate by (network, MAC) instead of IP
leases_dict[(network, mac)] = dhcp_lease
```

### 3. Storage Logic (`websocket.py`)
```python
# Upsert based on MAC+network instead of IP
result = await session.execute(
    select(DHCPLeaseDB).where(
        DHCPLeaseDB.network == lease.network,
        DHCPLeaseDB.mac_address == lease.mac_address
    )
)
```

## Deployment

### For New Installations
No action needed - the schema will be created correctly on first run.

### For Existing Installations

You have two options:

#### Option 1: Migrate Existing Data (Recommended)

```bash
# On your router (SSH)
cd /etc/nixos/webui/backend/migrations

# Make migration script executable
chmod +x migrate.sh

# Run migration (will prompt for confirmation)
./migrate.sh
```

The migration will:
1. Drop old `ip_address` unique constraint
2. Add new composite unique indexes
3. Clean up any duplicate data
4. Verify data integrity

#### Option 2: Fresh Start (Simpler, loses history)

```bash
# On your router (SSH)

# Stop the backend
sudo systemctl stop router-webui-backend

# Drop and recreate the DHCP table
sudo -u postgres psql -d router_webui -c "DROP TABLE IF EXISTS dhcp_leases CASCADE;"

# Restart backend (will recreate table with new schema)
sudo systemctl start router-webui-backend
```

### After Migration

```bash
# Rebuild NixOS with updated code
cd /etc/nixos
git pull  # or copy updated files
sudo nixos-rebuild switch

# Restart backend
sudo systemctl restart router-webui-backend

# Monitor for errors
sudo journalctl -u router-webui-backend -f
```

## Verification

### Check Database Schema
```bash
sudo -u postgres psql -d router_webui -c "\d dhcp_leases"
```

Expected output should show:
```
Indexes:
    "dhcp_leases_pkey" PRIMARY KEY, btree (id)
    "idx_dhcp_network_ip" UNIQUE, btree (network, ip_address)
    "idx_dhcp_network_mac" UNIQUE, btree (network, mac_address)
    "idx_dhcp_leases_last_seen" btree (last_seen DESC)
    "idx_dhcp_leases_network" btree (network)
```

### Check for Errors
```bash
# Should see NO constraint violations
sudo journalctl -u router-webui-backend -n 100 --no-pager | grep -i "constraint\|error"
```

### Check WebUI
1. Open http://192.168.2.1:8080
2. Go to "DHCP Clients" page
3. Should see devices listed by MAC address
4. Device count should be accurate
5. If a device changes IP, it should still show the same device

## Rollback

If you need to rollback (shouldn't be necessary):

```bash
# Restore old schema
sudo -u postgres psql -d router_webui <<EOF
DROP INDEX IF EXISTS idx_dhcp_network_mac;
DROP INDEX IF EXISTS idx_dhcp_network_ip;
CREATE UNIQUE INDEX dhcp_leases_ip_address_key ON dhcp_leases(ip_address);
EOF

# Revert code and rebuild
cd /etc/nixos
git checkout <previous-commit>
sudo nixos-rebuild switch
sudo systemctl restart router-webui-backend
```

## Technical Details

### Unique Constraints

The table now has two composite unique constraints:

1. **`(network, mac_address)`** - One lease per device per network
   - Same MAC can exist in both homelab and lan
   - Same MAC cannot exist twice in same network
   - Device is tracked even if IP changes

2. **`(network, ip_address)`** - One device per IP per network
   - Same IP can exist in both homelab and lan
   - Same IP cannot be assigned to multiple devices in same network
   - Prevents IP conflicts

### Deduplication Logic

The collector now deduplicates by `(network, MAC)` tuple:

```python
leases_dict[(network, mac)] = dhcp_lease
```

If the Kea lease file contains:
```
192.168.2.100, aa:bb:cc:11:22:33, hostname1
192.168.2.150, aa:bb:cc:11:22:33, hostname1  ← Same device, new IP
192.168.2.100, dd:ee:ff:44:55:66, hostname2  ← Different device, old IP
```

Result (deduplicated):
- Device `aa:bb:cc:11:22:33` → `192.168.2.150` (latest)
- Device `dd:ee:ff:44:55:66` → `192.168.2.100`

### Storage Behavior

When updating the database:

1. **Existing device, same IP**: Update lease times, hostname
2. **Existing device, new IP**: Update IP address (device tracked across IP change)
3. **New device**: Insert new record
4. **IP released by one device, taken by another**: Both records updated correctly

## Benefits in Practice

### Scenario 1: Device IP Change
```
Before:
  - Device A (aa:bb:cc) gets 192.168.2.100
  - Device A renews, gets 192.168.2.150
  - Old system: Lost track of Device A, shows as two "clients"
  - New system: Same device, updated IP, accurate count ✅

### Scenario 2: IP Reuse
```
Before:
  - Device A releases 192.168.2.100
  - Device B gets 192.168.2.100
  - Old system: Showed Device B with Device A's history
  - New system: Device A and B tracked separately ✅
```

### Scenario 3: Kea Lease File Duplicates
```
Before:
  - Kea file has multiple entries for same IP
  - Old system: Database constraint error ❌
  - New system: Deduplicated by MAC, no errors ✅
```

## Questions?

If you encounter any issues:

1. Check logs: `sudo journalctl -u router-webui-backend -f`
2. Verify schema: `sudo -u postgres psql -d router_webui -c "\d dhcp_leases"`
3. Check data: `sudo -u postgres psql -d router_webui -c "SELECT * FROM dhcp_leases;"`
4. Review migration: `cat /etc/nixos/webui/backend/migrations/001_mac_based_tracking.sql`

