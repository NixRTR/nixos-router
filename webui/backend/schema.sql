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

-- Network devices (all discovered devices - DHCP and static)
-- Discovered via ARP table scanning + DHCP leases
CREATE TABLE IF NOT EXISTS network_devices (
    id SERIAL PRIMARY KEY,
    network VARCHAR(32) NOT NULL,      -- 'homelab' or 'lan'
    mac_address MACADDR NOT NULL,      -- Device identifier
    ip_address INET NOT NULL,          -- Current IP address
    hostname VARCHAR(255),             -- Device hostname
    vendor VARCHAR(255),               -- Manufacturer from MAC OUI
    is_dhcp BOOLEAN DEFAULT FALSE,     -- Using DHCP
    is_static BOOLEAN DEFAULT FALSE,   -- Static DHCP reservation
    is_online BOOLEAN DEFAULT TRUE,    -- Currently active (in ARP)
    first_seen TIMESTAMPTZ NOT NULL,   -- First discovery
    last_seen TIMESTAMPTZ NOT NULL     -- Last activity
);

CREATE INDEX IF NOT EXISTS idx_network_devices_network ON network_devices(network);
CREATE INDEX IF NOT EXISTS idx_network_devices_online ON network_devices(is_online);
CREATE INDEX IF NOT EXISTS idx_network_devices_last_seen ON network_devices(last_seen DESC);

-- Unique constraint: one entry per device per network
CREATE UNIQUE INDEX IF NOT EXISTS idx_network_devices_network_mac ON network_devices(network, mac_address);

-- Disk I/O metrics time-series
CREATE TABLE IF NOT EXISTS disk_io_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    device VARCHAR(32) NOT NULL,
    read_bytes_per_sec REAL,
    write_bytes_per_sec REAL,
    read_ops_per_sec REAL,
    write_ops_per_sec REAL
);

CREATE INDEX IF NOT EXISTS idx_disk_io_device_time ON disk_io_metrics(device, timestamp DESC);

-- Temperature metrics time-series
CREATE TABLE IF NOT EXISTS temperature_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    sensor_name VARCHAR(128) NOT NULL,
    temperature_c REAL,
    label VARCHAR(128),
    critical REAL
);

CREATE INDEX IF NOT EXISTS idx_temperature_sensor_time ON temperature_metrics(sensor_name, timestamp DESC);

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

-- Per-client bandwidth statistics (tracked by MAC address, IPv4 only)
CREATE TABLE IF NOT EXISTS client_bandwidth_stats (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    mac_address MACADDR NOT NULL,
    ip_address INET NOT NULL,
    network VARCHAR(32) NOT NULL,
    rx_bytes BIGINT NOT NULL,  -- download bytes in this interval
    tx_bytes BIGINT NOT NULL,  -- upload bytes in this interval
    rx_bytes_total BIGINT NOT NULL,  -- cumulative download
    tx_bytes_total BIGINT NOT NULL,  -- cumulative upload
    aggregation_level VARCHAR(2) DEFAULT 'raw'  -- 'raw', '1m', '5m', '1h', '1d'
);

CREATE INDEX IF NOT EXISTS idx_client_bandwidth_mac_time ON client_bandwidth_stats(mac_address, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_client_bandwidth_timestamp ON client_bandwidth_stats(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_client_bandwidth_mac ON client_bandwidth_stats(mac_address);
CREATE INDEX IF NOT EXISTS idx_client_bandwidth_agg_level ON client_bandwidth_stats(aggregation_level, timestamp DESC);

-- Per-connection bandwidth statistics (tracked by client IP and remote IP:Port, IPv4 only)
CREATE TABLE IF NOT EXISTS client_connection_stats (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    client_ip INET NOT NULL,
    client_mac MACADDR NOT NULL,
    remote_ip INET NOT NULL,
    remote_port INTEGER NOT NULL,
    rx_bytes BIGINT NOT NULL,  -- download bytes in this interval
    tx_bytes BIGINT NOT NULL,  -- upload bytes in this interval
    rx_bytes_total BIGINT NOT NULL,  -- cumulative download
    tx_bytes_total BIGINT NOT NULL,  -- cumulative upload
    aggregation_level VARCHAR(2) DEFAULT 'raw'  -- 'raw', '1m', '5m', '1h', '1d'
);

CREATE INDEX IF NOT EXISTS idx_client_connection_client_time ON client_connection_stats(client_ip, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_client_connection_client_remote ON client_connection_stats(client_ip, remote_ip, remote_port, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_client_connection_timestamp ON client_connection_stats(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_client_connection_agg_level ON client_connection_stats(aggregation_level, timestamp DESC);

-- Create hypertable for time-series data (if using TimescaleDB extension)
-- Uncomment if TimescaleDB is available:
-- SELECT create_hypertable('system_metrics', 'timestamp', if_not_exists => TRUE);
-- SELECT create_hypertable('interface_stats', 'timestamp', if_not_exists => TRUE);
-- SELECT create_hypertable('service_status', 'timestamp', if_not_exists => TRUE);

