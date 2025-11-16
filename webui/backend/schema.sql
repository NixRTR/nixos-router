-- Router WebUI Database Schema
-- PostgreSQL schema for storing router metrics and configuration

-- System metrics time-series
CREATE TABLE IF NOT EXISTS system_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    cpu_percent REAL,
    memory_percent REAL,
    memory_used_mb INTEGER,
    memory_total_mb INTEGER,
    load_avg_1m REAL,
    load_avg_5m REAL,
    load_avg_15m REAL,
    uptime_seconds BIGINT
);

CREATE INDEX IF NOT EXISTS idx_system_metrics_timestamp ON system_metrics(timestamp DESC);

-- Network interface stats time-series
CREATE TABLE IF NOT EXISTS interface_stats (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    interface VARCHAR(32) NOT NULL,
    rx_bytes BIGINT,
    tx_bytes BIGINT,
    rx_packets BIGINT,
    tx_packets BIGINT,
    rx_errors BIGINT,
    tx_errors BIGINT,
    rx_dropped BIGINT,
    tx_dropped BIGINT
);

CREATE INDEX IF NOT EXISTS idx_interface_stats_interface_time ON interface_stats(interface, timestamp DESC);

-- DHCP leases (current state snapshot - tracks devices by MAC)
-- Design: Each device (MAC) can only have one active lease per network
--         Each IP can only be assigned once per network
--         This allows tracking devices across IP changes
CREATE TABLE IF NOT EXISTS dhcp_leases (
    id SERIAL PRIMARY KEY,
    network VARCHAR(32) NOT NULL,  -- 'homelab' or 'lan'
    mac_address MACADDR NOT NULL,  -- Device identifier
    ip_address INET NOT NULL,      -- Current IP assignment
    hostname VARCHAR(255),
    lease_start TIMESTAMPTZ,
    lease_end TIMESTAMPTZ,
    last_seen TIMESTAMPTZ NOT NULL,
    is_static BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_dhcp_leases_network ON dhcp_leases(network);
CREATE INDEX IF NOT EXISTS idx_dhcp_leases_last_seen ON dhcp_leases(last_seen DESC);

-- Unique constraint: one lease per device per network
CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_mac ON dhcp_leases(network, mac_address);

-- Unique constraint: one device per IP per network
CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_ip ON dhcp_leases(network, ip_address);

-- Service status time-series
CREATE TABLE IF NOT EXISTS service_status (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    service_name VARCHAR(128) NOT NULL,
    is_active BOOLEAN,
    is_enabled BOOLEAN,
    pid INTEGER,
    memory_mb REAL,
    cpu_percent REAL
);

CREATE INDEX IF NOT EXISTS idx_service_status_service_time ON service_status(service_name, timestamp DESC);

-- Configuration changes log (for Stage 2)
CREATE TABLE IF NOT EXISTS config_changes (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    user_id VARCHAR(64),
    change_type VARCHAR(64),  -- 'dhcp', 'dns', 'firewall', etc.
    change_data JSONB,
    applied BOOLEAN DEFAULT FALSE,
    applied_at TIMESTAMPTZ,
    error_message TEXT
);

-- Create hypertable for time-series data (if using TimescaleDB extension)
-- Uncomment if TimescaleDB is available:
-- SELECT create_hypertable('system_metrics', 'timestamp', if_not_exists => TRUE);
-- SELECT create_hypertable('interface_stats', 'timestamp', if_not_exists => TRUE);
-- SELECT create_hypertable('service_status', 'timestamp', if_not_exists => TRUE);

