-- Migration: MAC-based DHCP lease tracking
-- Date: 2025-11-16
-- Description: Change from IP-based to MAC-based lease tracking
--              This allows tracking devices across IP changes

-- Step 1: Drop the old unique constraint on IP address
DROP INDEX IF EXISTS dhcp_leases_ip_address_key;

-- Step 2: Create new composite unique indexes
-- Each device (MAC) can only have one active lease per network
CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_mac ON dhcp_leases(network, mac_address);

-- Each IP can only be assigned once per network
CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_ip ON dhcp_leases(network, ip_address);

-- Step 3: Clean up any duplicate data
-- If there are multiple entries for the same (network, MAC), keep the most recent
DELETE FROM dhcp_leases a
USING dhcp_leases b
WHERE a.id < b.id
  AND a.network = b.network
  AND a.mac_address = b.mac_address;

-- If there are multiple entries for the same (network, IP), keep the most recent
DELETE FROM dhcp_leases a
USING dhcp_leases b
WHERE a.id < b.id
  AND a.network = b.network
  AND a.ip_address = b.ip_address;

-- Step 4: Verify data integrity
-- This should return 0 rows if migration is successful
SELECT network, mac_address, COUNT(*) as count
FROM dhcp_leases
GROUP BY network, mac_address
HAVING COUNT(*) > 1;

SELECT network, ip_address, COUNT(*) as count
FROM dhcp_leases
GROUP BY network, ip_address
HAVING COUNT(*) > 1;

