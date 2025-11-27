-- Migration 005: Apprise Services Database Storage
-- Migrate Apprise service URLs from config file to database

-- Apprise services table
CREATE TABLE IF NOT EXISTS apprise_services (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    url TEXT NOT NULL,
    original_secret_string TEXT,  -- Original string from secrets if migrated
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_apprise_services_enabled ON apprise_services(enabled);

