"""
Database connection and ORM models using SQLAlchemy
"""
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy import Column, Integer, Float, String, Boolean, BigInteger, DateTime, Text, Index, text, ForeignKey
from sqlalchemy.dialects.postgresql import INET, MACADDR, JSONB, ARRAY
from datetime import datetime
from typing import AsyncGenerator

from .config import settings

# Create async engine
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_size=20,
    max_overflow=40,
    pool_pre_ping=True,
)

# Create async session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)

# Base class for ORM models
Base = declarative_base()


class SystemMetricsDB(Base):
    """System metrics table"""
    __tablename__ = "system_metrics"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    cpu_percent = Column(Float)
    memory_percent = Column(Float)
    memory_used_mb = Column(Integer)
    memory_total_mb = Column(Integer)
    load_avg_1m = Column(Float)
    load_avg_5m = Column(Float)
    load_avg_15m = Column(Float)
    uptime_seconds = Column(BigInteger)
    
    __table_args__ = (
        Index('idx_timestamp', 'timestamp', postgresql_using='btree'),
    )


class InterfaceStatsDB(Base):
    """Network interface stats table"""
    __tablename__ = "interface_stats"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False)
    interface = Column(String(32), nullable=False)
    rx_bytes = Column(BigInteger)
    tx_bytes = Column(BigInteger)
    rx_packets = Column(BigInteger)
    tx_packets = Column(BigInteger)
    rx_errors = Column(BigInteger)
    tx_errors = Column(BigInteger)
    rx_dropped = Column(BigInteger)
    tx_dropped = Column(BigInteger)
    
    __table_args__ = (
        Index('idx_interface_time', 'interface', 'timestamp', postgresql_using='btree'),
    )


class DiskIOMetricsDB(Base):
    """Disk I/O metrics table"""
    __tablename__ = "disk_io_metrics"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    device = Column(String(32), nullable=False)
    read_bytes_per_sec = Column(Float)
    write_bytes_per_sec = Column(Float)
    read_ops_per_sec = Column(Float)
    write_ops_per_sec = Column(Float)
    
    __table_args__ = (
        Index('idx_disk_io_device_time', 'device', 'timestamp', postgresql_using='btree'),
    )


class TemperatureMetricsDB(Base):
    """Temperature metrics table"""
    __tablename__ = "temperature_metrics"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    sensor_name = Column(String(128), nullable=False)
    temperature_c = Column(Float)
    label = Column(String(128))
    critical = Column(Float)
    
    __table_args__ = (
        Index('idx_temperature_sensor_time', 'sensor_name', 'timestamp', postgresql_using='btree'),
    )


class DHCPLeaseDB(Base):
    """DHCP leases table - tracks devices (MAC) with current IP assignments"""
    __tablename__ = "dhcp_leases"
    
    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(32), nullable=False, index=True)
    mac_address = Column(MACADDR, nullable=False)
    ip_address = Column(INET, nullable=False)
    hostname = Column(String(255))
    lease_start = Column(DateTime(timezone=True))
    lease_end = Column(DateTime(timezone=True))
    last_seen = Column(DateTime(timezone=True), nullable=False, index=True)
    is_static = Column(Boolean, default=False)
    
    __table_args__ = (
        # Each device (MAC) can only have one active lease per network
        Index('idx_dhcp_network_mac', 'network', 'mac_address', unique=True),
        # Each IP can only be assigned once per network
        Index('idx_dhcp_network_ip', 'network', 'ip_address', unique=True),
    )


class ServiceStatusDB(Base):
    """Service status table"""
    __tablename__ = "service_status"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False)
    service_name = Column(String(128), nullable=False)
    is_active = Column(Boolean)
    is_enabled = Column(Boolean)
    pid = Column(Integer)
    memory_mb = Column(Float)
    cpu_percent = Column(Float)
    
    __table_args__ = (
        Index('idx_service_time', 'service_name', 'timestamp', postgresql_using='btree'),
    )


class ConfigChangeDB(Base):
    """Configuration changes log table"""
    __tablename__ = "config_changes"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    user_id = Column(String(64))
    change_type = Column(String(64))
    change_data = Column(JSONB)
    applied = Column(Boolean, default=False)
    applied_at = Column(DateTime(timezone=True))
    error_message = Column(Text)


class NetworkDeviceDB(Base):
    """Network devices table - all discovered devices (DHCP and static)"""
    __tablename__ = "network_devices"
    
    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(32), nullable=False, index=True)
    mac_address = Column(MACADDR, nullable=False)
    ip_address = Column(INET, nullable=False)
    hostname = Column(String(255))
    vendor = Column(String(255))  # Device manufacturer from MAC OUI
    is_dhcp = Column(Boolean, default=False)
    is_static = Column(Boolean, default=False)
    is_online = Column(Boolean, default=True, index=True)
    first_seen = Column(DateTime(timezone=True), nullable=False)
    last_seen = Column(DateTime(timezone=True), nullable=False, index=True)
    
    __table_args__ = (
        # Each device (MAC) tracked per network
        Index('idx_network_devices_network_mac', 'network', 'mac_address', unique=True),
    )


class DeviceOverrideDB(Base):
    """Per-device overrides (nickname, favorite)"""
    __tablename__ = "device_overrides"
    
    id = Column(Integer, primary_key=True, index=True)
    mac_address = Column(MACADDR, nullable=False, unique=True, index=True)
    nickname = Column(String(255))
    favorite = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)


class ClientBandwidthStatsDB(Base):
    """Per-client bandwidth statistics (tracked by MAC address)"""
    __tablename__ = "client_bandwidth_stats"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    mac_address = Column(MACADDR, nullable=False, index=True)
    ip_address = Column(INET, nullable=False, index=True)
    network = Column(String(32), nullable=False)
    rx_bytes = Column(BigInteger, nullable=False)  # download bytes in this interval
    tx_bytes = Column(BigInteger, nullable=False)  # upload bytes in this interval
    rx_bytes_total = Column(BigInteger, nullable=False)  # cumulative download
    tx_bytes_total = Column(BigInteger, nullable=False)  # cumulative upload
    aggregation_level = Column(String(3), default='raw', nullable=False)  # 'raw', '1m', '5m', '1h', '1d'
    
    __table_args__ = (
        Index('idx_client_bandwidth_mac_time', 'mac_address', 'timestamp', postgresql_using='btree'),
        Index('idx_client_bandwidth_timestamp', 'timestamp', postgresql_using='btree'),
        Index('idx_client_bandwidth_agg_level', 'aggregation_level', 'timestamp', postgresql_using='btree'),
    )


class ClientConnectionStatsDB(Base):
    """Per-connection bandwidth statistics (tracked by client IP and remote IP:Port)"""
    __tablename__ = "client_connection_stats"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    client_ip = Column(INET, nullable=False, index=True)
    client_mac = Column(MACADDR, nullable=False)
    remote_ip = Column(INET, nullable=False)
    remote_port = Column(Integer, nullable=False)
    rx_bytes = Column(BigInteger, nullable=False)  # download bytes in this interval
    tx_bytes = Column(BigInteger, nullable=False)  # upload bytes in this interval
    rx_bytes_total = Column(BigInteger, nullable=False)  # cumulative download
    tx_bytes_total = Column(BigInteger, nullable=False)  # cumulative upload
    aggregation_level = Column(String(3), default='raw', nullable=False)  # 'raw', '1m', '5m', '1h', '1d'
    
    __table_args__ = (
        Index('idx_client_connection_client_time', 'client_ip', 'timestamp', postgresql_using='btree'),
        Index('idx_client_connection_client_remote', 'client_ip', 'remote_ip', 'remote_port', 'timestamp', postgresql_using='btree'),
        Index('idx_client_connection_timestamp', 'timestamp', postgresql_using='btree'),
        Index('idx_client_connection_agg_level', 'aggregation_level', 'timestamp', postgresql_using='btree'),
    )


class SpeedtestResultDB(Base):
    """Speedtest results table"""
    __tablename__ = "speedtest_results"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    download_mbps = Column(Float, nullable=False)
    upload_mbps = Column(Float, nullable=False)
    ping_ms = Column(Float, nullable=False)
    server_name = Column(String(255))
    server_location = Column(String(255))
    
    __table_args__ = (
        Index('idx_speedtest_results_timestamp', 'timestamp', postgresql_using='btree'),
    )


class CakeStatsDB(Base):
    """CAKE traffic shaping statistics table"""
    __tablename__ = "cake_stats"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    interface = Column(String(32), nullable=False)
    
    # Overall stats
    rate_mbps = Column(Float)              # Priority layer bandwidth threshold
    target_ms = Column(Float)              # AQM target delay
    interval_ms = Column(Float)            # AQM interval
    
    # Traffic class stats (stored as JSONB for flexibility)
    classes = Column(JSONB)                # { "bulk": { "pk_delay": ..., "av_delay": ..., "bytes": ..., "drops": ... }, ... }
    
    # Hash statistics
    way_inds = Column(BigInteger)          # Indirect hits
    way_miss = Column(BigInteger)          # Hash misses  
    way_cols = Column(BigInteger)          # Hash collisions
    
    __table_args__ = (
        Index('idx_cake_stats_interface_time', 'interface', 'timestamp', postgresql_using='btree'),
        Index('idx_cake_stats_timestamp', 'timestamp', postgresql_using='btree'),
    )


class NotificationRuleDB(Base):
    """Notification rule definition"""
    __tablename__ = "notification_rules"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    enabled = Column(Boolean, default=True)
    parameter_type = Column(String(64), nullable=False)
    parameter_config = Column(JSONB)
    threshold_info = Column(Float)
    threshold_warning = Column(Float)
    threshold_failure = Column(Float)
    comparison_operator = Column(String(10), default='gt')
    duration_seconds = Column(Integer, nullable=False)
    cooldown_seconds = Column(Integer, nullable=False)
    apprise_service_indices = Column(ARRAY(Integer))
    message_template = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    __table_args__ = (
        Index('idx_notification_rules_enabled', 'enabled', postgresql_using='btree'),
    )


class NotificationStateDB(Base):
    """Notification rule runtime state"""
    __tablename__ = "notification_state"

    rule_id = Column(Integer, ForeignKey('notification_rules.id', ondelete='CASCADE'), primary_key=True)
    current_level = Column(String(20))
    threshold_exceeded_at = Column(DateTime(timezone=True))
    last_notification_at = Column(DateTime(timezone=True))
    last_notification_level = Column(String(20))
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)


class NotificationHistoryDB(Base):
    """Notification send history"""
    __tablename__ = "notification_history"

    id = Column(Integer, primary_key=True, index=True)
    rule_id = Column(Integer, ForeignKey('notification_rules.id', ondelete='CASCADE'), nullable=False, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    level = Column(String(20), nullable=False)
    value = Column(Float, nullable=False)
    message = Column(Text)
    sent_successfully = Column(Boolean, default=False)
    
    __table_args__ = (
        Index('idx_notification_history_rule_id', 'rule_id', postgresql_using='btree'),
        Index('idx_notification_history_timestamp', 'timestamp', postgresql_using='btree'),
    )


class AppriseServiceDB(Base):
    """Apprise service configuration"""
    __tablename__ = "apprise_services"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    url = Column(Text, nullable=False)
    original_secret_string = Column(Text)  # Original string from secrets if migrated
    enabled = Column(Boolean, default=True, index=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    
    __table_args__ = (
        Index('idx_apprise_services_enabled', 'enabled', postgresql_using='btree'),
    )


class DnsZoneDB(Base):
    """DNS zone configuration"""
    __tablename__ = "dns_zones"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)  # Domain name (e.g., "jeandr.net")
    network = Column(String(50), nullable=False)  # "homelab" or "lan"
    authoritative = Column(Boolean, default=True)  # Serve locally (transparent zone)
    forward_to = Column(Text)  # Optional: Forward queries to this DNS server
    delegate_to = Column(Text)  # Optional: Delegate zone to this DNS server (NS records)
    enabled = Column(Boolean, default=True, index=True)
    original_config_path = Column(Text)  # For migration tracking: "homelab.dns" or "lan.dns"
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    
    __table_args__ = (
        Index('idx_dns_zones_network', 'network', postgresql_using='btree'),
        Index('idx_dns_zones_enabled', 'enabled', postgresql_using='btree'),
        Index('idx_dns_zones_name_network', 'name', 'network', unique=True, postgresql_using='btree'),
    )


class DnsRecordDB(Base):
    """DNS record configuration"""
    __tablename__ = "dns_records"
    
    id = Column(Integer, primary_key=True, index=True)
    zone_id = Column(Integer, ForeignKey('dns_zones.id', ondelete='CASCADE'), nullable=False, index=True)
    name = Column(String(255), nullable=False)  # Hostname (e.g., "hera.jeandr.net" or "*.jeandr.net")
    type = Column(String(10), nullable=False)  # "A" or "CNAME"
    value = Column(Text, nullable=False)  # IP address for A, target hostname for CNAME
    comment = Column(Text)
    enabled = Column(Boolean, default=True, index=True)
    original_config_path = Column(Text)  # For migration tracking
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    
    __table_args__ = (
        Index('idx_dns_records_zone_id', 'zone_id', postgresql_using='btree'),
        Index('idx_dns_records_type', 'type', postgresql_using='btree'),
        Index('idx_dns_records_enabled', 'enabled', postgresql_using='btree'),
    )


class DhcpNetworkDB(Base):
    """DHCP network configuration (one per network: homelab/lan)"""
    __tablename__ = "dhcp_networks"
    
    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(50), nullable=False, unique=True)  # "homelab" or "lan"
    enabled = Column(Boolean, default=True, index=True)
    start = Column(INET, nullable=False)  # IP range start
    end = Column(INET, nullable=False)  # IP range end
    lease_time = Column(String(20), nullable=False)  # e.g., "1h", "1d", "86400"
    dns_servers = Column(ARRAY(INET))  # Array of DNS server IPs
    dynamic_domain = Column(Text)  # Optional dynamic DNS domain (e.g., "dhcp.homelab.local")
    original_config_path = Column(Text)  # For migration tracking: "homelab.dhcp" or "lan.dhcp"
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    
    __table_args__ = (
        Index('idx_dhcp_networks_network', 'network', postgresql_using='btree'),
        Index('idx_dhcp_networks_enabled', 'enabled', postgresql_using='btree'),
    )


class DhcpReservationDB(Base):
    """DHCP static IP reservations"""
    __tablename__ = "dhcp_reservations"
    
    id = Column(Integer, primary_key=True, index=True)
    network_id = Column(Integer, ForeignKey('dhcp_networks.id', ondelete='CASCADE'), nullable=False, index=True)
    hostname = Column(String(255), nullable=False)
    hw_address = Column(MACADDR, nullable=False)  # MAC address
    ip_address = Column(INET, nullable=False)  # Reserved IP address
    comment = Column(Text)
    enabled = Column(Boolean, default=True, index=True)
    original_config_path = Column(Text)  # For migration tracking
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    
    __table_args__ = (
        Index('idx_dhcp_reservations_network_id', 'network_id', postgresql_using='btree'),
        Index('idx_dhcp_reservations_hw_address', 'hw_address', postgresql_using='btree'),
        Index('idx_dhcp_reservations_ip_address', 'ip_address', postgresql_using='btree'),
        Index('idx_dhcp_reservations_enabled', 'enabled', postgresql_using='btree'),
        Index('idx_dhcp_reservations_network_hw', 'network_id', 'hw_address', unique=True, postgresql_using='btree'),
        Index('idx_dhcp_reservations_network_ip', 'network_id', 'ip_address', unique=True, postgresql_using='btree'),
    )

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency for getting async database session"""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db():
    """Initialize database schema and apply migrations"""
    async with engine.begin() as conn:
        # Create all tables (if they don't exist)
        await conn.run_sync(Base.metadata.create_all)
        
        # Apply schema updates for existing tables
        await _apply_schema_updates(conn)


async def _apply_schema_updates(conn):
    """Apply schema updates to existing tables - covers all migrations"""
    
    # Migration 001: MAC-based DHCP lease tracking - ensure indexes exist
    await conn.execute(
        text("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_mac 
            ON dhcp_leases(network, mac_address)
        """)
    )
    await conn.execute(
        text("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_dhcp_network_ip 
            ON dhcp_leases(network, ip_address)
        """)
    )
    
    # Migration 002: Disk I/O and temperature metrics - tables created by SQLAlchemy,
    # but ensure indexes exist
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_disk_io_device_time 
            ON disk_io_metrics(device, timestamp DESC)
        """)
    )
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_temperature_sensor_time 
            ON temperature_metrics(sensor_name, timestamp DESC)
        """)
    )
    
    # Migration 003: Device overrides - ensure table and trigger exist
    # Table is created by SQLAlchemy, but trigger needs to be created
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'device_overrides_updated_at'
        """)
    )
    has_trigger = result.scalar() is not None
    
    if not has_trigger:
        # Create trigger function
        await conn.execute(
            text("""
                CREATE OR REPLACE FUNCTION set_updated_at()
                RETURNS TRIGGER AS $$
                BEGIN
                  NEW.updated_at = NOW();
                  RETURN NEW;
                END;
                $$ LANGUAGE plpgsql
            """)
        )
        # Create trigger
        await conn.execute(
            text("""
                CREATE TRIGGER device_overrides_updated_at
                BEFORE UPDATE ON device_overrides
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
        print("Created device_overrides trigger")
    
    # Migration: Add aggregation_level column to client_bandwidth_stats
    result = await conn.execute(
        text("""
            SELECT column_name, character_maximum_length
            FROM information_schema.columns 
            WHERE table_name = 'client_bandwidth_stats' 
            AND column_name = 'aggregation_level'
        """)
    )
    agg_level_info = result.fetchone()
    has_agg_level = agg_level_info is not None
    
    if not has_agg_level:
        # Add aggregation_level column
        await conn.execute(
            text("""
                ALTER TABLE client_bandwidth_stats 
                ADD COLUMN aggregation_level VARCHAR(3) DEFAULT 'raw'
            """)
        )
        # Update existing rows
        await conn.execute(
            text("""
                UPDATE client_bandwidth_stats 
                SET aggregation_level = 'raw' 
                WHERE aggregation_level IS NULL
            """)
        )
        # Make NOT NULL
        await conn.execute(
            text("""
                ALTER TABLE client_bandwidth_stats 
                ALTER COLUMN aggregation_level SET NOT NULL
            """)
        )
        print("Added aggregation_level column to client_bandwidth_stats")
    elif agg_level_info[1] == 2:
        # Column exists but is wrong size (VARCHAR(2) instead of VARCHAR(3))
        # Alter the column type
        await conn.execute(
            text("""
                ALTER TABLE client_bandwidth_stats 
                ALTER COLUMN aggregation_level TYPE VARCHAR(3)
            """)
        )
        print("Updated aggregation_level column size from VARCHAR(2) to VARCHAR(3)")
    
    # Ensure index exists (regardless of whether column was just added)
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_client_bandwidth_agg_level 
            ON client_bandwidth_stats(aggregation_level, timestamp DESC)
        """)
    )
    
    # Migration: Create client_connection_stats table
    result = await conn.execute(
        text("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_name = 'client_connection_stats'
        """)
    )
    has_connection_stats = result.scalar() is not None
    
    if has_connection_stats:
        # Check if aggregation_level column exists and has correct size
        result = await conn.execute(
            text("""
                SELECT column_name, character_maximum_length
                FROM information_schema.columns 
                WHERE table_name = 'client_connection_stats' 
                AND column_name = 'aggregation_level'
            """)
        )
        agg_level_info = result.fetchone()
        if agg_level_info and agg_level_info[1] == 2:
            # Column exists but is wrong size (VARCHAR(2) instead of VARCHAR(3))
            # Alter the column type
            await conn.execute(
                text("""
                    ALTER TABLE client_connection_stats 
                    ALTER COLUMN aggregation_level TYPE VARCHAR(3)
                """)
            )
            print("Updated client_connection_stats.aggregation_level column size from VARCHAR(2) to VARCHAR(3)")
        elif not agg_level_info:
            # Column doesn't exist, add it
            await conn.execute(
                text("""
                    ALTER TABLE client_connection_stats 
                    ADD COLUMN aggregation_level VARCHAR(3) DEFAULT 'raw'
                """)
            )
            await conn.execute(
                text("""
                    UPDATE client_connection_stats 
                    SET aggregation_level = 'raw' 
                    WHERE aggregation_level IS NULL
                """)
            )
            await conn.execute(
                text("""
                    ALTER TABLE client_connection_stats 
                    ALTER COLUMN aggregation_level SET NOT NULL
                """)
            )
            print("Added aggregation_level column to client_connection_stats")
    
    if not has_connection_stats:
        # Create client_connection_stats table
        await conn.execute(
            text("""
                CREATE TABLE client_connection_stats (
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
                )
            """)
        )
        # Create indexes
        await conn.execute(
            text("""
                CREATE INDEX idx_client_connection_client_time 
                ON client_connection_stats(client_ip, timestamp DESC)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_client_connection_client_remote 
                ON client_connection_stats(client_ip, remote_ip, remote_port, timestamp DESC)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_client_connection_timestamp 
                ON client_connection_stats(timestamp DESC)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_client_connection_agg_level 
                ON client_connection_stats(aggregation_level, timestamp DESC)
            """)
        )
        print("Created client_connection_stats table")
    
    # Migration: Create speedtest_results table
    result = await conn.execute(
        text("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_name = 'speedtest_results'
        """)
    )
    has_speedtest_results = result.scalar() is not None
    
    if not has_speedtest_results:
        await conn.execute(
            text("""
                CREATE TABLE speedtest_results (
                    id SERIAL PRIMARY KEY,
                    timestamp TIMESTAMPTZ NOT NULL,
                    download_mbps REAL NOT NULL,
                    upload_mbps REAL NOT NULL,
                    ping_ms REAL NOT NULL,
                    server_name VARCHAR(255),
                    server_location VARCHAR(255)
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_speedtest_results_timestamp 
                ON speedtest_results(timestamp DESC)
            """)
        )
        print("Created speedtest_results table")

    # Migration 004: Notification system tables - ensure indexes and triggers exist
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_notification_rules_enabled
            ON notification_rules(enabled)
        """)
    )
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_notification_history_rule_id
            ON notification_history(rule_id)
        """)
    )
    await conn.execute(
        text("""
            CREATE INDEX IF NOT EXISTS idx_notification_history_timestamp
            ON notification_history(timestamp DESC)
        """)
    )

    # Ensure trigger function exists
    await conn.execute(
        text("""
            CREATE OR REPLACE FUNCTION set_updated_at()
            RETURNS TRIGGER AS $$
            BEGIN
              NEW.updated_at = NOW();
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
        """)
    )

    # Ensure notification_rules trigger exists
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'notification_rules_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER notification_rules_updated_at
                BEFORE UPDATE ON notification_rules
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )

    # Ensure notification_state trigger exists
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'notification_state_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER notification_state_updated_at
                BEFORE UPDATE ON notification_state
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
    
    # Migration 005: Apprise services table
    result = await conn.execute(
        text("""
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'apprise_services'
        """)
    )
    has_apprise_services = result.scalar() is not None
    
    if not has_apprise_services:
        await conn.execute(
            text("""
                CREATE TABLE apprise_services (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    url TEXT NOT NULL,
                    original_secret_string TEXT,
                    enabled BOOLEAN DEFAULT TRUE,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_apprise_services_enabled 
                ON apprise_services(enabled)
            """)
        )
        print("Created apprise_services table")
    
    # Ensure apprise_services trigger exists
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'apprise_services_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER apprise_services_updated_at
                BEFORE UPDATE ON apprise_services
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
    
    # Migration 006: DNS zones and records tables
    result = await conn.execute(
        text("""
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'dns_zones'
        """)
    )
    has_dns_zones = result.scalar() is not None
    
    if not has_dns_zones:
        await conn.execute(
            text("""
                CREATE TABLE dns_zones (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    network VARCHAR(50) NOT NULL,
                    authoritative BOOLEAN DEFAULT TRUE,
                    forward_to TEXT,
                    delegate_to TEXT,
                    enabled BOOLEAN DEFAULT TRUE,
                    original_config_path TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW(),
                    UNIQUE(name, network)
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dns_zones_network 
                ON dns_zones(network)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dns_zones_enabled 
                ON dns_zones(enabled)
            """)
        )
        print("Created dns_zones table")
    
    result = await conn.execute(
        text("""
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'dns_records'
        """)
    )
    has_dns_records = result.scalar() is not None
    
    if not has_dns_records:
        await conn.execute(
            text("""
                CREATE TABLE dns_records (
                    id SERIAL PRIMARY KEY,
                    zone_id INTEGER NOT NULL REFERENCES dns_zones(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    type VARCHAR(10) NOT NULL,
                    value TEXT NOT NULL,
                    comment TEXT,
                    enabled BOOLEAN DEFAULT TRUE,
                    original_config_path TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dns_records_zone_id 
                ON dns_records(zone_id)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dns_records_type 
                ON dns_records(type)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dns_records_enabled 
                ON dns_records(enabled)
            """)
        )
        print("Created dns_records table")
    
    # Ensure DNS triggers exist
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'dns_zones_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER dns_zones_updated_at
                BEFORE UPDATE ON dns_zones
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
    
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'dns_records_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER dns_records_updated_at
                BEFORE UPDATE ON dns_records
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
    
    # Migration 007: DHCP networks and reservations tables
    result = await conn.execute(
        text("""
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'dhcp_networks'
        """)
    )
    has_dhcp_networks = result.scalar() is not None
    
    if not has_dhcp_networks:
        await conn.execute(
            text("""
                CREATE TABLE dhcp_networks (
                    id SERIAL PRIMARY KEY,
                    network VARCHAR(50) NOT NULL UNIQUE,
                    enabled BOOLEAN DEFAULT TRUE,
                    start INET NOT NULL,
                    end INET NOT NULL,
                    lease_time VARCHAR(20) NOT NULL,
                    dns_servers INET[],
                    dynamic_domain TEXT,
                    original_config_path TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_networks_network 
                ON dhcp_networks(network)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_networks_enabled 
                ON dhcp_networks(enabled)
            """)
        )
        print("Created dhcp_networks table")
    
    result = await conn.execute(
        text("""
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'dhcp_reservations'
        """)
    )
    has_dhcp_reservations = result.scalar() is not None
    
    if not has_dhcp_reservations:
        await conn.execute(
            text("""
                CREATE TABLE dhcp_reservations (
                    id SERIAL PRIMARY KEY,
                    network_id INTEGER NOT NULL REFERENCES dhcp_networks(id) ON DELETE CASCADE,
                    hostname VARCHAR(255) NOT NULL,
                    hw_address MACADDR NOT NULL,
                    ip_address INET NOT NULL,
                    comment TEXT,
                    enabled BOOLEAN DEFAULT TRUE,
                    original_config_path TEXT,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW(),
                    UNIQUE(network_id, hw_address),
                    UNIQUE(network_id, ip_address)
                )
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_reservations_network_id 
                ON dhcp_reservations(network_id)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_reservations_hw_address 
                ON dhcp_reservations(hw_address)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_reservations_ip_address 
                ON dhcp_reservations(ip_address)
            """)
        )
        await conn.execute(
            text("""
                CREATE INDEX idx_dhcp_reservations_enabled 
                ON dhcp_reservations(enabled)
            """)
        )
        print("Created dhcp_reservations table")
    
    # Ensure DHCP triggers exist
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'dhcp_networks_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER dhcp_networks_updated_at
                BEFORE UPDATE ON dhcp_networks
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )
    
    result = await conn.execute(
        text("""
            SELECT 1 FROM pg_trigger WHERE tgname = 'dhcp_reservations_updated_at'
        """)
    )
    if result.scalar() is None:
        await conn.execute(
            text("""
                CREATE TRIGGER dhcp_reservations_updated_at
                BEFORE UPDATE ON dhcp_reservations
                FOR EACH ROW EXECUTE PROCEDURE set_updated_at()
            """)
        )

