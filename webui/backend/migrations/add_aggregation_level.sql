-- Migration: Add aggregation_level column to client_bandwidth_stats
-- and create client_connection_stats table
-- Run this migration to update existing database schema

-- Add aggregation_level column to client_bandwidth_stats
ALTER TABLE client_bandwidth_stats 
ADD COLUMN IF NOT EXISTS aggregation_level VARCHAR(3) DEFAULT 'raw';

-- Update existing rows to have 'raw' aggregation level
UPDATE client_bandwidth_stats 
SET aggregation_level = 'raw' 
WHERE aggregation_level IS NULL;

-- Make the column NOT NULL after setting defaults
ALTER TABLE client_bandwidth_stats 
ALTER COLUMN aggregation_level SET NOT NULL;

-- Add index for aggregation_level
CREATE INDEX IF NOT EXISTS idx_client_bandwidth_agg_level 
ON client_bandwidth_stats(aggregation_level, timestamp DESC);

-- Create client_connection_stats table if it doesn't exist
CREATE TABLE IF NOT EXISTS client_connection_stats (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    client_ip INET NOT NULL,
    client_mac MACADDR NOT NULL,
    remote_ip INET NOT NULL,
    remote_port INTEGER NOT NULL,
    rx_bytes BIGINT NOT NULL,
    tx_bytes BIGINT NOT NULL,
    rx_bytes_total BIGINT NOT NULL,
    tx_bytes_total BIGINT NOT NULL,
    aggregation_level VARCHAR(3) DEFAULT 'raw' NOT NULL
);

-- Create indexes for client_connection_stats
CREATE INDEX IF NOT EXISTS idx_client_connection_client_time 
ON client_connection_stats(client_ip, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_client_connection_client_remote 
ON client_connection_stats(client_ip, remote_ip, remote_port, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_client_connection_timestamp 
ON client_connection_stats(timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_client_connection_agg_level 
ON client_connection_stats(aggregation_level, timestamp DESC);

