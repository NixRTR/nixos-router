-- Migration: Add device bandwidth tracking
-- Date: 2025-11-16
-- Description: Add tables for per-device bandwidth accounting
--              Tracks upload/download rates per IP address

-- Step 1: Create device bandwidth table
CREATE TABLE IF NOT EXISTS device_bandwidth (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    network VARCHAR(32) NOT NULL,      -- 'homelab' or 'lan'
    ip_address INET NOT NULL,          -- Device IP address
    mac_address MACADDR,               -- Device MAC address (if known)
    hostname VARCHAR(255),             -- Device hostname
    rx_bytes_per_sec REAL,             -- Download rate (bytes/sec)
    tx_bytes_per_sec REAL              -- Upload rate (bytes/sec)
);

-- Step 2: Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_device_bandwidth_ip_time ON device_bandwidth(ip_address, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_device_bandwidth_network_time ON device_bandwidth(network, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_device_bandwidth_timestamp ON device_bandwidth(timestamp DESC);

-- Step 3: Create aggregated bandwidth table for historical summaries
CREATE TABLE IF NOT EXISTS device_bandwidth_summary (
    id SERIAL PRIMARY KEY,
    network VARCHAR(32) NOT NULL,      -- 'homelab' or 'lan'
    ip_address INET NOT NULL,          -- Device IP address
    mac_address MACADDR,               -- Device MAC address (if known)
    hostname VARCHAR(255),             -- Device hostname
    period_start TIMESTAMPTZ NOT NULL, -- Start of period (hour/day/month)
    period_end TIMESTAMPTZ NOT NULL,   -- End of period
    period_type VARCHAR(16) NOT NULL,  -- 'hour', 'day', 'month'
    total_rx_bytes BIGINT,             -- Total bytes downloaded
    total_tx_bytes BIGINT,             -- Total bytes uploaded
    avg_rx_bytes_per_sec REAL,         -- Average download rate
    avg_tx_bytes_per_sec REAL,         -- Average upload rate
    max_rx_bytes_per_sec REAL,         -- Peak download rate
    max_tx_bytes_per_sec REAL          -- Peak upload rate
);

-- Step 4: Create indexes for summary queries
CREATE INDEX IF NOT EXISTS idx_device_summary_ip_period ON device_bandwidth_summary(ip_address, period_type, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_device_summary_network_period ON device_bandwidth_summary(network, period_type, period_start DESC);

-- Step 5: Verify tables were created
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('device_bandwidth', 'device_bandwidth_summary');
