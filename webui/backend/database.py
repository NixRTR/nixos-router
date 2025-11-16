"""
Database connection and ORM models using SQLAlchemy
"""
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy import Column, Integer, Float, String, Boolean, BigInteger, DateTime, Text, Index
from sqlalchemy.dialects.postgresql import INET, MACADDR, JSONB
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


class DeviceBandwidthDB(Base):
    """Device bandwidth metrics table"""
    __tablename__ = "device_bandwidth"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False, index=True)
    network = Column(String(32), nullable=False)
    ip_address = Column(INET, nullable=False)
    mac_address = Column(MACADDR)
    hostname = Column(String(255))
    rx_bytes_per_sec = Column(Float)
    tx_bytes_per_sec = Column(Float)

    __table_args__ = (
        Index('idx_device_bandwidth_ip_time', 'ip_address', 'timestamp', postgresql_using='btree'),
        Index('idx_device_bandwidth_network_time', 'network', 'timestamp', postgresql_using='btree'),
    )


class DeviceBandwidthSummaryDB(Base):
    """Device bandwidth summary table"""
    __tablename__ = "device_bandwidth_summary"

    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(32), nullable=False)
    ip_address = Column(INET, nullable=False)
    mac_address = Column(MACADDR)
    hostname = Column(String(255))
    period_start = Column(DateTime(timezone=True), nullable=False)
    period_end = Column(DateTime(timezone=True), nullable=False)
    period_type = Column(String(16), nullable=False)
    total_rx_bytes = Column(BigInteger)
    total_tx_bytes = Column(BigInteger)
    avg_rx_bytes_per_sec = Column(Float)
    avg_tx_bytes_per_sec = Column(Float)
    max_rx_bytes_per_sec = Column(Float)
    max_tx_bytes_per_sec = Column(Float)

    __table_args__ = (
        Index('idx_device_summary_ip_period', 'ip_address', 'period_type', 'period_start', postgresql_using='btree'),
        Index('idx_device_summary_network_period', 'network', 'period_type', 'period_start', postgresql_using='btree'),
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
    """Initialize database schema"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

