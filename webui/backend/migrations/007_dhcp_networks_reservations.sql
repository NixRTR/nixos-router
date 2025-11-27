-- Migration 007: DHCP Networks and Reservations Database Storage
-- Migrate DHCP configuration from router-config.nix to database

-- DHCP networks table (one per network: homelab/lan)
CREATE TABLE IF NOT EXISTS dhcp_networks (
    id SERIAL PRIMARY KEY,
    network VARCHAR(50) NOT NULL UNIQUE,  -- "homelab" or "lan"
    enabled BOOLEAN DEFAULT TRUE,
    start INET NOT NULL,  -- IP range start
    end INET NOT NULL,  -- IP range end
    lease_time VARCHAR(20) NOT NULL,  -- e.g., "1h", "1d", "86400"
    dns_servers INET[],  -- Array of DNS server IPs
    dynamic_domain TEXT,  -- Optional dynamic DNS domain (e.g., "dhcp.homelab.local")
    original_config_path TEXT,  -- For migration tracking: "homelab.dhcp" or "lan.dhcp"
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dhcp_networks_network ON dhcp_networks(network);
CREATE INDEX IF NOT EXISTS idx_dhcp_networks_enabled ON dhcp_networks(enabled);

-- DHCP reservations table
CREATE TABLE IF NOT EXISTS dhcp_reservations (
    id SERIAL PRIMARY KEY,
    network_id INTEGER NOT NULL REFERENCES dhcp_networks(id) ON DELETE CASCADE,
    hostname VARCHAR(255) NOT NULL,
    hw_address MACADDR NOT NULL,  -- MAC address
    ip_address INET NOT NULL,  -- Reserved IP address
    comment TEXT,
    enabled BOOLEAN DEFAULT TRUE,
    original_config_path TEXT,  -- For migration tracking
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(network_id, hw_address),  -- One reservation per MAC per network
    UNIQUE(network_id, ip_address)  -- One reservation per IP per network
);

CREATE INDEX IF NOT EXISTS idx_dhcp_reservations_network_id ON dhcp_reservations(network_id);
CREATE INDEX IF NOT EXISTS idx_dhcp_reservations_hw_address ON dhcp_reservations(hw_address);
CREATE INDEX IF NOT EXISTS idx_dhcp_reservations_ip_address ON dhcp_reservations(ip_address);
CREATE INDEX IF NOT EXISTS idx_dhcp_reservations_enabled ON dhcp_reservations(enabled);

-- Create triggers for updated_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'dhcp_networks_updated_at'
  ) THEN
    CREATE TRIGGER dhcp_networks_updated_at
    BEFORE UPDATE ON dhcp_networks
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'dhcp_reservations_updated_at'
  ) THEN
    CREATE TRIGGER dhcp_reservations_updated_at
    BEFORE UPDATE ON dhcp_reservations
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;

