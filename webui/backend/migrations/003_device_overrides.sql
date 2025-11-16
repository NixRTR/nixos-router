-- Migration: Device nicknames and favorites
-- Date: 2025-11-16
-- Description: Create table to store per-device overrides (nickname, favorite)

CREATE TABLE IF NOT EXISTS device_overrides (
  id SERIAL PRIMARY KEY,
  mac_address MACADDR NOT NULL UNIQUE,
  nickname VARCHAR(255),
  favorite BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_device_overrides_mac ON device_overrides(mac_address);

-- Trigger to update updated_at on change
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'device_overrides_updated_at'
  ) THEN
    CREATE OR REPLACE FUNCTION set_updated_at()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER device_overrides_updated_at
    BEFORE UPDATE ON device_overrides
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;
