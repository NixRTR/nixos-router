-- Migration: Add disk I/O and temperature metrics tables
-- Date: 2025-11-16
-- Description: Add historical tracking for disk I/O and temperature metrics
--              Enables persistent storage and historical queries

-- Step 1: Create disk I/O metrics table
CREATE TABLE IF NOT EXISTS disk_io_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    device VARCHAR(32) NOT NULL,
    read_bytes_per_sec REAL,
    write_bytes_per_sec REAL,
    read_ops_per_sec REAL,
    write_ops_per_sec REAL
);

-- Step 2: Create index for efficient queries by device and time
CREATE INDEX IF NOT EXISTS idx_disk_io_device_time ON disk_io_metrics(device, timestamp DESC);

-- Step 3: Create temperature metrics table
CREATE TABLE IF NOT EXISTS temperature_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    sensor_name VARCHAR(128) NOT NULL,
    temperature_c REAL,
    label VARCHAR(128),
    critical REAL
);

-- Step 4: Create index for efficient queries by sensor and time
CREATE INDEX IF NOT EXISTS idx_temperature_sensor_time ON temperature_metrics(sensor_name, timestamp DESC);

-- Step 5: Verify tables were created
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('disk_io_metrics', 'temperature_metrics');

