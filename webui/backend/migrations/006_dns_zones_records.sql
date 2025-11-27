-- Migration 006: DNS Zones and Records Database Storage
-- Migrate DNS configuration from router-config.nix to database

-- DNS zones table
CREATE TABLE IF NOT EXISTS dns_zones (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,  -- Domain name (e.g., "jeandr.net")
    network VARCHAR(50) NOT NULL,  -- "homelab" or "lan"
    authoritative BOOLEAN DEFAULT TRUE,  -- Serve locally (transparent zone)
    forward_to TEXT,  -- Optional: Forward queries to this DNS server (e.g., "192.168.1.1")
    delegate_to TEXT,  -- Optional: Delegate zone to this DNS server (NS records)
    enabled BOOLEAN DEFAULT TRUE,
    original_config_path TEXT,  -- For migration tracking: "homelab.dns" or "lan.dns"
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(name, network)  -- Zone name must be unique per network
);

CREATE INDEX IF NOT EXISTS idx_dns_zones_network ON dns_zones(network);
CREATE INDEX IF NOT EXISTS idx_dns_zones_enabled ON dns_zones(enabled);

-- DNS records table
CREATE TABLE IF NOT EXISTS dns_records (
    id SERIAL PRIMARY KEY,
    zone_id INTEGER NOT NULL REFERENCES dns_zones(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,  -- Hostname (e.g., "hera.jeandr.net" or "*.jeandr.net")
    type VARCHAR(10) NOT NULL,  -- "A" or "CNAME"
    value TEXT NOT NULL,  -- IP address for A, target hostname for CNAME
    comment TEXT,
    enabled BOOLEAN DEFAULT TRUE,
    original_config_path TEXT,  -- For migration tracking
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dns_records_zone_id ON dns_records(zone_id);
CREATE INDEX IF NOT EXISTS idx_dns_records_type ON dns_records(type);
CREATE INDEX IF NOT EXISTS idx_dns_records_enabled ON dns_records(enabled);

-- Create triggers for updated_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'dns_zones_updated_at'
  ) THEN
    CREATE TRIGGER dns_zones_updated_at
    BEFORE UPDATE ON dns_zones
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'dns_records_updated_at'
  ) THEN
    CREATE TRIGGER dns_records_updated_at
    BEFORE UPDATE ON dns_records
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;

