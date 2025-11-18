"""
Bandwidth history API endpoints
"""
from fastapi import APIRouter, Depends, Query
from typing import List, Optional, Dict
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from pydantic import BaseModel
import re

from ..auth import get_current_user
from ..database import AsyncSessionLocal, InterfaceStatsDB, ClientBandwidthStatsDB
from ..models import (
    ClientBandwidthHistory, ClientBandwidthCurrent, ClientBandwidthDataPoint
)
from ..collectors.client_bandwidth import collect_client_bandwidth
from ..collectors.network_devices import discover_network_devices
from ..collectors.dhcp import parse_kea_leases
from ..collectors.network import collect_interface_stats
from ..config import settings
from sqlalchemy import func


def _is_ipv4(ip: str) -> bool:
    """Check if an IP address is IPv4"""
    try:
        parts = ip.split('.')
        if len(parts) != 4:
            return False
        for part in parts:
            num = int(part)
            if num < 0 or num > 255:
                return False
        return True
    except (ValueError, AttributeError):
        return False


router = APIRouter(prefix="/api/bandwidth", tags=["bandwidth"])


class InterfaceDataPoint(BaseModel):
    """Single data point for interface bandwidth"""
    timestamp: datetime
    rx_mbps: float
    tx_mbps: float


class BandwidthHistory(BaseModel):
    """Bandwidth history for an interface"""
    interface: str
    data: List[InterfaceDataPoint]


def parse_time_range(range_str: str) -> timedelta:
    """Parse time range string to timedelta
    
    Supports: 5m, 30m, 1h, 3h, 12h, 1d, 1w, 1M (30 days), 1y (365 days)
    
    Args:
        range_str: Time range string (e.g., "1h", "30m", "1d")
        
    Returns:
        timedelta: Parsed time delta
    """
    range_str = range_str.strip().lower()
    
    # Extract number and unit
    if not range_str:
        return timedelta(hours=1)  # Default to 1 hour
    
    # Find where the number ends and unit begins
    num_str = ""
    unit = ""
    
    for char in range_str:
        if char.isdigit() or char == '.':
            num_str += char
        else:
            unit = range_str[len(num_str):]
            break
    
    if not num_str:
        return timedelta(hours=1)
    
    try:
        value = float(num_str)
    except ValueError:
        return timedelta(hours=1)
    
    # Parse unit
    if unit in ['m', 'min', 'mins', 'minute', 'minutes']:
        return timedelta(minutes=value)
    elif unit in ['h', 'hr', 'hrs', 'hour', 'hours']:
        return timedelta(hours=value)
    elif unit in ['d', 'day', 'days']:
        return timedelta(days=value)
    elif unit in ['w', 'week', 'weeks']:
        return timedelta(weeks=value)
    elif unit in ['M', 'month', 'months']:
        return timedelta(days=value * 30)  # Approximate
    elif unit in ['y', 'year', 'years']:
        return timedelta(days=value * 365)  # Approximate
    else:
        return timedelta(hours=1)  # Default


@router.get("/history")
async def get_bandwidth_history(
    interface: Optional[str] = Query(None, description="Interface name (e.g., ppp0, br0)"),
    time_range: str = Query("1h", description="Time range (e.g., 10m, 1h, 1d, 1w)", alias="range"),
    _: str = Depends(get_current_user)
) -> List[BandwidthHistory]:
    """Get historical bandwidth data
    
    Args:
        interface: Optional interface filter (returns all if not specified)
        time_range: Time range string (default: 1h)
        
    Returns:
        List[BandwidthHistory]: Bandwidth history per interface
    """
    # Parse time range
    time_delta = parse_time_range(time_range)
    start_time = datetime.now(timezone.utc) - time_delta
    
    async with AsyncSessionLocal() as session:
        # Build query
        query = select(InterfaceStatsDB).where(
            InterfaceStatsDB.timestamp >= start_time
        ).order_by(InterfaceStatsDB.timestamp.asc())
        
        if interface:
            query = query.where(InterfaceStatsDB.interface == interface)
        
        result = await session.execute(query)
        stats = result.scalars().all()
    
    # Group by interface
    interfaces = {}
    for stat in stats:
        if stat.interface not in interfaces:
            interfaces[stat.interface] = []
        
        # Calculate bandwidth in Mbps
        # Note: We store cumulative bytes, need to calculate rate
        # For now, we'll use the raw bytes and let frontend calculate rate
        interfaces[stat.interface].append({
            'timestamp': stat.timestamp,
            'rx_bytes': stat.rx_bytes,
            'tx_bytes': stat.tx_bytes,
            'rx_mbps': 0.0,  # Will be calculated from deltas
            'tx_mbps': 0.0
        })
    
    # Calculate rates (Mbps) from byte deltas
    history_list = []
    for iface, data_points in interfaces.items():
        processed_points = []
        
        for i in range(len(data_points)):
            if i == 0:
                # First point, no rate calculation possible
                processed_points.append(InterfaceDataPoint(
                    timestamp=data_points[i]['timestamp'],
                    rx_mbps=0.0,
                    tx_mbps=0.0
                ))
            else:
                # Calculate rate from previous point
                prev = data_points[i - 1]
                curr = data_points[i]
                
                time_diff = (curr['timestamp'] - prev['timestamp']).total_seconds()
                if time_diff > 0:
                    # Bytes per second -> Megabits per second
                    rx_mbps = ((curr['rx_bytes'] - prev['rx_bytes']) * 8) / (time_diff * 1_000_000)
                    tx_mbps = ((curr['tx_bytes'] - prev['tx_bytes']) * 8) / (time_diff * 1_000_000)
                    
                    # Clamp to reasonable values (ignore spikes/anomalies)
                    rx_mbps = max(0, min(rx_mbps, 10000))  # Max 10 Gbps
                    tx_mbps = max(0, min(tx_mbps, 10000))
                else:
                    rx_mbps = 0.0
                    tx_mbps = 0.0
                
                processed_points.append(InterfaceDataPoint(
                    timestamp=curr['timestamp'],
                    rx_mbps=round(rx_mbps, 2),
                    tx_mbps=round(tx_mbps, 2)
                ))
        
        history_list.append(BandwidthHistory(
            interface=iface,
            data=processed_points
        ))
    
    return history_list


@router.get("/interfaces")
async def get_available_interfaces(
    _: str = Depends(get_current_user)
) -> List[str]:
    """Get list of interfaces with bandwidth data
    
    Returns:
        List[str]: Interface names
    """
    async with AsyncSessionLocal() as session:
        # Get distinct interfaces from last hour
        one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
        
        query = select(InterfaceStatsDB.interface).distinct().where(
            InterfaceStatsDB.timestamp >= one_hour_ago
        )
        
        result = await session.execute(query)
        interfaces = [row[0] for row in result.all()]
    
    return sorted(interfaces)


@router.get("/interfaces/current")
async def get_current_interface_stats(
    _: str = Depends(get_current_user)
) -> Dict[str, dict]:
    """Get current interface statistics for br0, br1, and ppp0
    
    Returns:
        Dict mapping interface names to their current stats
    """
    stats_list = collect_interface_stats()
    result = {}
    
    # Filter to only br0, br1, ppp0
    for stat in stats_list:
        if stat.interface in ['br0', 'br1', 'ppp0']:
            result[stat.interface] = {
                'rx_rate_mbps': round(stat.rx_rate_mbps or 0.0, 2),
                'tx_rate_mbps': round(stat.tx_rate_mbps or 0.0, 2),
                'rx_bytes': stat.rx_bytes,
                'tx_bytes': stat.tx_bytes,
            }
    
    return result


@router.get("/clients/debug")
async def get_client_bandwidth_debug(
    _: str = Depends(get_current_user)
) -> dict:
    """Debug endpoint to check bandwidth collection status
    
    Returns:
        dict: Debug information about bandwidth collection
    """
    import subprocess
    import os
    
    debug_info = {
        "collector_enabled": settings.bandwidth_collection_enabled,
        "nftables_table_exists": False,
        "nftables_counters": [],
        "nftables_set": [],
        "collector_test": None,
        "error": None
    }
    
    try:
        # Check if nftables table exists
        nft = os.environ.get("NFT_BIN", "nft")
        result = subprocess.run(
            [nft, "list", "table", "inet", "router_bandwidth"],
            capture_output=True,
            text=True,
            timeout=5
        )
        debug_info["nftables_table_exists"] = result.returncode == 0
        debug_info["nftables_output"] = result.stdout if result.returncode == 0 else result.stderr
        
        # List counters
        result = subprocess.run(
            [nft, "list", "counters", "inet", "router_bandwidth"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            debug_info["nftables_counters"] = result.stdout.splitlines()
        
        # List set
        result = subprocess.run(
            [nft, "list", "set", "inet", "router_bandwidth", "client_ips"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            debug_info["nftables_set"] = result.stdout.splitlines()
        
        # List all rules in forward chain to see per-IP rules
        result = subprocess.run(
            [nft, "list", "chain", "inet", "router_bandwidth", "forward"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            debug_info["nftables_rules"] = result.stdout.splitlines()
            # Count per-IP rules (rules with specific IP addresses, not @client_ips)
            per_ip_rules = [line for line in result.stdout.splitlines() if re.search(r'ip\s+(daddr|saddr)\s+\d+\.\d+\.\d+\.\d+', line)]
            debug_info["per_ip_rule_count"] = len(per_ip_rules)
            debug_info["sample_per_ip_rules"] = per_ip_rules[:5] if per_ip_rules else []
        
        # Test collector
        try:
            from ..collectors.client_bandwidth import collect_client_bandwidth, _read_nftables_counters
            counters = _read_nftables_counters()
            test_data = collect_client_bandwidth()
            debug_info["collector_test"] = {
                "counters_found": len(counters),
                "clients_collected": len(test_data),
                "sample_data": test_data[:3] if test_data else []
            }
        except Exception as e:
            debug_info["collector_test_error"] = str(e)
        
        # Check database
        async with AsyncSessionLocal() as session:
            from sqlalchemy import func
            result = await session.execute(
                select(func.count(ClientBandwidthStatsDB.id))
            )
            count = result.scalar()
            debug_info["database_records"] = count
            
            # Get latest record
            result = await session.execute(
                select(ClientBandwidthStatsDB)
                .order_by(ClientBandwidthStatsDB.timestamp.desc())
                .limit(1)
            )
            latest = result.scalar_one_or_none()
            if latest:
                debug_info["latest_record"] = {
                    "timestamp": str(latest.timestamp),
                    "mac_address": str(latest.mac_address),
                    "ip_address": str(latest.ip_address),
                    "rx_bytes": latest.rx_bytes,
                    "tx_bytes": latest.tx_bytes
                }
    
    except Exception as e:
        debug_info["error"] = str(e)
    
    return debug_info


@router.get("/clients/current")
async def get_current_client_bandwidth(
    _: str = Depends(get_current_user)
) -> List[ClientBandwidthCurrent]:
    """Get current bandwidth rates for all active clients
    
    Returns:
        List[ClientBandwidthCurrent]: Current bandwidth stats for each client
    """
    # Get current bandwidth data from collector
    current_data = collect_client_bandwidth()
    
    # Get device information for hostnames
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)
    # Filter to IPv4 only
    devices = [d for d in devices if _is_ipv4(d.ip_address)]
    device_map = {d.mac_address.lower(): d for d in devices}
    
    # Get latest stats from database for cumulative totals
    async with AsyncSessionLocal() as session:
        # Get most recent entry for each MAC address
        subquery = (
            select(
                ClientBandwidthStatsDB.mac_address,
                func.max(ClientBandwidthStatsDB.timestamp).label('max_timestamp')
            )
            .group_by(ClientBandwidthStatsDB.mac_address)
            .subquery()
        )
        
        query = select(ClientBandwidthStatsDB).join(
            subquery,
            (ClientBandwidthStatsDB.mac_address == subquery.c.mac_address) &
            (ClientBandwidthStatsDB.timestamp == subquery.c.max_timestamp)
        )
        
        result = await session.execute(query)
        db_stats = {str(row.mac_address).lower(): row for row in result.scalars().all()}
    
    # Combine current data with database stats (already filtered to IPv4 and bridge subnets by collector)
    results = []
    for data in current_data:
        # Double-check IPv4 and bridge subnets (collector should already filter, but be safe)
        if not _is_ipv4(data['ip_address']):
            continue
        # Only track IPs in bridge subnets (192.168.2.x for br0/homelab, 192.168.3.x for br1/lan)
        if not (data['ip_address'].startswith('192.168.2.') or data['ip_address'].startswith('192.168.3.')):
            continue
        mac = data['mac_address'].lower()
        device = device_map.get(mac)
        
        # Calculate rates (assuming 5-10 second collection interval)
        # Use interval bytes to calculate current rate
        collection_interval = 5.0  # seconds (approximate)
        rx_mbps = (data['rx_bytes'] * 8) / (collection_interval * 1_000_000)
        tx_mbps = (data['tx_bytes'] * 8) / (collection_interval * 1_000_000)
        
        # Use database cumulative totals if available, otherwise use current
        db_stat = db_stats.get(mac)
        rx_total = db_stat.rx_bytes_total if db_stat else data['rx_bytes_total']
        tx_total = db_stat.tx_bytes_total if db_stat else data['tx_bytes_total']
        
        results.append(ClientBandwidthCurrent(
            mac_address=data['mac_address'],
            ip_address=data['ip_address'],
            network=data['network'],
            hostname=device.hostname if device else None,
            rx_mbps=round(rx_mbps, 2),
            tx_mbps=round(tx_mbps, 2),
            rx_bytes_total=rx_total,
            tx_bytes_total=tx_total,
            last_updated=data['timestamp']
        ))
    
    return results


@router.get("/clients")
async def get_all_clients_bandwidth(
    _: str = Depends(get_current_user)
) -> List[ClientBandwidthCurrent]:
    """List all clients with current bandwidth stats
    
    Alias for /clients/current for convenience
    
    Returns:
        List[ClientBandwidthCurrent]: Current bandwidth stats for each client
    """
    return await get_current_client_bandwidth(_)


@router.get("/clients/{mac_address}")
async def get_client_bandwidth_history(
    mac_address: str,
    time_range: str = Query("1h", description="Time range (e.g., 10m, 1h, 1d, 1w)", alias="range"),
    interval: str = Query("raw", description="Aggregation interval: 'raw', '1m', '5m', '1h'"),
    _: str = Depends(get_current_user)
) -> ClientBandwidthHistory:
    """Get historical bandwidth data for a specific client
    
    Args:
        mac_address: MAC address of the client
        time_range: Time range string (default: 1h)
        interval: Aggregation interval - 'raw' for raw samples, or '1m', '5m', '1h' for aggregated
        
    Returns:
        ClientBandwidthHistory: Historical bandwidth data for the client
    """
    # Parse time range
    time_delta = parse_time_range(time_range)
    start_time = datetime.now(timezone.utc) - time_delta
    
    # Normalize MAC address
    mac_address = mac_address.lower().replace('-', ':')
    
    async with AsyncSessionLocal() as session:
        # Query database for client bandwidth stats
        query = select(ClientBandwidthStatsDB).where(
            ClientBandwidthStatsDB.mac_address == mac_address,
            ClientBandwidthStatsDB.timestamp >= start_time
        ).order_by(ClientBandwidthStatsDB.timestamp.asc())
        
        result = await session.execute(query)
        stats = result.scalars().all()
    
    if not stats:
        # Return empty history if no data found
        return ClientBandwidthHistory(
            mac_address=mac_address,
            ip_address="",
            network="",
            data=[]
        )
    
    # Get client info from first entry
    first_stat = stats[0]
    ip_address = str(first_stat.ip_address)
    network = first_stat.network
    
    # Process data points
    data_points = []
    
    if interval == "raw":
        # Return raw samples
        for i, stat in enumerate(stats):
            if i == 0:
                # First point, no rate calculation
                data_points.append(ClientBandwidthDataPoint(
                    timestamp=stat.timestamp,
                    rx_mbps=0.0,
                    tx_mbps=0.0,
                    rx_bytes=stat.rx_bytes,
                    tx_bytes=stat.tx_bytes
                ))
            else:
                # Calculate rate from previous point
                prev = stats[i - 1]
                time_diff = (stat.timestamp - prev.timestamp).total_seconds()
                
                if time_diff > 0:
                    rx_mbps = (stat.rx_bytes * 8) / (time_diff * 1_000_000)
                    tx_mbps = (stat.tx_bytes * 8) / (time_diff * 1_000_000)
                else:
                    rx_mbps = 0.0
                    tx_mbps = 0.0
                
                data_points.append(ClientBandwidthDataPoint(
                    timestamp=stat.timestamp,
                    rx_mbps=round(rx_mbps, 2),
                    tx_mbps=round(tx_mbps, 2),
                    rx_bytes=stat.rx_bytes,
                    tx_bytes=stat.tx_bytes
                ))
    else:
        # Aggregate by interval
        interval_seconds = {
            "1m": 60,
            "5m": 300,
            "1h": 3600
        }.get(interval, 60)
        
        # Group stats by time buckets
        buckets = {}
        for stat in stats:
            # Round timestamp to interval
            bucket_time = stat.timestamp.replace(
                second=(stat.timestamp.second // interval_seconds) * interval_seconds,
                microsecond=0
            )
            
            if bucket_time not in buckets:
                buckets[bucket_time] = {
                    'rx_bytes': 0,
                    'tx_bytes': 0,
                    'count': 0
                }
            
            buckets[bucket_time]['rx_bytes'] += stat.rx_bytes
            buckets[bucket_time]['tx_bytes'] += stat.tx_bytes
            buckets[bucket_time]['count'] += 1
        
        # Convert buckets to data points
        sorted_times = sorted(buckets.keys())
        for i, bucket_time in enumerate(sorted_times):
            bucket = buckets[bucket_time]
            
            if i == 0:
                rx_mbps = 0.0
                tx_mbps = 0.0
            else:
                prev_time = sorted_times[i - 1]
                time_diff = (bucket_time - prev_time).total_seconds()
                
                if time_diff > 0:
                    rx_mbps = (bucket['rx_bytes'] * 8) / (time_diff * 1_000_000)
                    tx_mbps = (bucket['tx_bytes'] * 8) / (time_diff * 1_000_000)
                else:
                    rx_mbps = 0.0
                    tx_mbps = 0.0
            
            data_points.append(ClientBandwidthDataPoint(
                timestamp=bucket_time,
                rx_mbps=round(rx_mbps, 2),
                tx_mbps=round(tx_mbps, 2),
                rx_bytes=bucket['rx_bytes'],
                tx_bytes=bucket['tx_bytes']
            ))
    
    return ClientBandwidthHistory(
        mac_address=mac_address,
        ip_address=ip_address,
        network=network,
        data=data_points
    )


@router.get("/clients/history/bulk")
async def get_bulk_client_bandwidth_history(
    time_range: str = Query("1h", description="Time range (e.g., 5m, 30m, 1h, 1d)", alias="range"),
    interval: str = Query("raw", description="Aggregation interval: 'raw', '1m', '5m', '1h'"),
    _: str = Depends(get_current_user)
) -> Dict[str, ClientBandwidthHistory]:
    """Get historical bandwidth data for all clients in a single call
    
    This endpoint efficiently returns aggregated historical data for all clients,
    avoiding the need to make individual API calls per client.
    
    Args:
        time_range: Time range string (default: 1h)
        interval: Aggregation interval - 'raw' for raw samples, or '1m', '5m', '1h' for aggregated
        
    Returns:
        Dict mapping MAC addresses to ClientBandwidthHistory objects
    """
    # Parse time range
    time_delta = parse_time_range(time_range)
    start_time = datetime.now(timezone.utc) - time_delta
    
    async with AsyncSessionLocal() as session:
        # Query database for all clients' bandwidth stats in one query
        query = select(ClientBandwidthStatsDB).where(
            ClientBandwidthStatsDB.timestamp >= start_time
        ).order_by(ClientBandwidthStatsDB.mac_address, ClientBandwidthStatsDB.timestamp.asc())
        
        result = await session.execute(query)
        all_stats = result.scalars().all()
    
    # Group by MAC address
    stats_by_mac: Dict[str, List[ClientBandwidthStatsDB]] = {}
    for stat in all_stats:
        mac = str(stat.mac_address).lower()
        if mac not in stats_by_mac:
            stats_by_mac[mac] = []
        stats_by_mac[mac].append(stat)
    
    # Process each client's data
    results: Dict[str, ClientBandwidthHistory] = {}
    
    for mac, stats in stats_by_mac.items():
        if not stats:
            continue
        
        # Get client info from first entry
        first_stat = stats[0]
        ip_address = str(first_stat.ip_address)
        # Filter to IPv4 only and bridge subnets only
        if not _is_ipv4(ip_address):
            continue
        # Only track IPs in bridge subnets (192.168.2.x for br0/homelab, 192.168.3.x for br1/lan)
        if not (ip_address.startswith('192.168.2.') or ip_address.startswith('192.168.3.')):
            continue
        network = first_stat.network
        
        # Process data points
        data_points = []
        
        if interval == "raw":
            # Return raw samples
            for i, stat in enumerate(stats):
                if i == 0:
                    # First point, no rate calculation
                    data_points.append(ClientBandwidthDataPoint(
                        timestamp=stat.timestamp,
                        rx_mbps=0.0,
                        tx_mbps=0.0,
                        rx_bytes=stat.rx_bytes,
                        tx_bytes=stat.tx_bytes
                    ))
                else:
                    # Calculate rate from previous point
                    prev = stats[i - 1]
                    time_diff = (stat.timestamp - prev.timestamp).total_seconds()
                    
                    if time_diff > 0:
                        rx_mbps = (stat.rx_bytes * 8) / (time_diff * 1_000_000)
                        tx_mbps = (stat.tx_bytes * 8) / (time_diff * 1_000_000)
                    else:
                        rx_mbps = 0.0
                        tx_mbps = 0.0
                    
                    data_points.append(ClientBandwidthDataPoint(
                        timestamp=stat.timestamp,
                        rx_mbps=round(rx_mbps, 2),
                        tx_mbps=round(tx_mbps, 2),
                        rx_bytes=stat.rx_bytes,
                        tx_bytes=stat.tx_bytes
                    ))
        else:
            # Aggregate by interval
            interval_seconds = {
                "1m": 60,
                "5m": 300,
                "1h": 3600
            }.get(interval, 60)
            
            # Group stats by time buckets
            buckets = {}
            for stat in stats:
                # Round timestamp to interval boundary
                # Convert to total seconds since epoch, round down, then convert back
                timestamp_seconds = int(stat.timestamp.timestamp())
                rounded_seconds = (timestamp_seconds // interval_seconds) * interval_seconds
                bucket_time = datetime.fromtimestamp(rounded_seconds, tz=timezone.utc).replace(microsecond=0)
                
                if bucket_time not in buckets:
                    buckets[bucket_time] = {
                        'rx_bytes': 0,
                        'tx_bytes': 0,
                        'count': 0
                    }
                
                buckets[bucket_time]['rx_bytes'] += stat.rx_bytes
                buckets[bucket_time]['tx_bytes'] += stat.tx_bytes
                buckets[bucket_time]['count'] += 1
            
            # Convert buckets to data points
            sorted_times = sorted(buckets.keys())
            for i, bucket_time in enumerate(sorted_times):
                bucket = buckets[bucket_time]
                
                if i == 0:
                    rx_mbps = 0.0
                    tx_mbps = 0.0
                else:
                    prev_time = sorted_times[i - 1]
                    time_diff = (bucket_time - prev_time).total_seconds()
                    
                    if time_diff > 0:
                        rx_mbps = (bucket['rx_bytes'] * 8) / (time_diff * 1_000_000)
                        tx_mbps = (bucket['tx_bytes'] * 8) / (time_diff * 1_000_000)
                    else:
                        rx_mbps = 0.0
                        tx_mbps = 0.0
                
                data_points.append(ClientBandwidthDataPoint(
                    timestamp=bucket_time,
                    rx_mbps=round(rx_mbps, 2),
                    tx_mbps=round(tx_mbps, 2),
                    rx_bytes=bucket['rx_bytes'],
                    tx_bytes=bucket['tx_bytes']
                ))
        
        results[mac] = ClientBandwidthHistory(
            mac_address=mac,
            ip_address=ip_address,
            network=network,
            data=data_points
        )
    
    return results

