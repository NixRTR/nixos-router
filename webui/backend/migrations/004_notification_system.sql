-- Migration: Notification system tables
-- Date: 2025-11-24
-- Description: Create tables for notification rules, state tracking, and history

CREATE TABLE IF NOT EXISTS notification_rules (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  enabled BOOLEAN DEFAULT TRUE,
  parameter_type VARCHAR(64) NOT NULL,
  parameter_config JSONB,
  threshold_info REAL,
  threshold_warning REAL,
  threshold_failure REAL,
  comparison_operator VARCHAR(10) DEFAULT 'gt',
  duration_seconds INTEGER NOT NULL,
  cooldown_seconds INTEGER NOT NULL,
  apprise_service_indices INTEGER[],
  message_template TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_rules_enabled ON notification_rules(enabled);

CREATE TABLE IF NOT EXISTS notification_state (
  rule_id INTEGER PRIMARY KEY REFERENCES notification_rules(id) ON DELETE CASCADE,
  current_level VARCHAR(20),
  threshold_exceeded_at TIMESTAMPTZ,
  last_notification_at TIMESTAMPTZ,
  last_notification_level VARCHAR(20),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_history (
  id SERIAL PRIMARY KEY,
  rule_id INTEGER REFERENCES notification_rules(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ NOT NULL,
  level VARCHAR(20) NOT NULL,
  value REAL NOT NULL,
  message TEXT,
  sent_successfully BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_notification_history_rule_id ON notification_history(rule_id);
CREATE INDEX IF NOT EXISTS idx_notification_history_timestamp ON notification_history(timestamp DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at'
  ) THEN
    CREATE OR REPLACE FUNCTION set_updated_at()
    RETURNS TRIGGER AS $func$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $func$ LANGUAGE plpgsql;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'notification_rules_updated_at'
  ) THEN
    CREATE TRIGGER notification_rules_updated_at
    BEFORE UPDATE ON notification_rules
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'notification_state_updated_at'
  ) THEN
    CREATE TRIGGER notification_state_updated_at
    BEFORE UPDATE ON notification_state
    FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
  END IF;
END
$$;

