"""
WebSocket connection manager and metrics broadcaster
"""
import asyncio
import json
import concurrent.futures
import time
from typing import List, Set, Optional, Tuple
from fastapi import WebSocket, WebSocketDisconnect
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import MetricsSnapshot, SystemMetrics, InterfaceStats, ServiceStatus, DHCPLease, DNSMetrics
from .database import AsyncSessionLocal, SystemMetricsDB, InterfaceStatsDB, ServiceStatusDB, DHCPLeaseDB, DiskIOMetricsDB, TemperatureMetricsDB, ClientBandwidthStatsDB, ClientConnectionStatsDB
from .collectors.system import collect_system_metrics, collect_disk_io, collect_temperatures, get_io_wait_percent
from .collectors.network import collect_interface_stats
from .collectors.dhcp import parse_kea_leases
from .collectors.services import collect_service_statuses
from .collectors.dns import collect_dns_stats
from .collectors.client_bandwidth import collect_client_bandwidth
from .collectors.client_connections import collect_client_connections
from .collectors.cake import collect_cake_stats, cake_stats_to_dict
from .utils.cake import is_cake_enabled
from .database import CakeStatsDB
from .config import settings


class ConnectionManager:
    """Manage WebSocket connections"""
    
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()
        self.broadcast_task: asyncio.Task = None
        self.pending_store_tasks: Set[asyncio.Task] = set()
        self._store_semaphore = asyncio.Semaphore(5)  # Limit concurrent store operations
        self.executor = concurrent.futures.ThreadPoolExecutor(max_workers=3)  # For CPU-bound/sync operations
        self._db_write_times: List[float] = []  # Track recent DB write latencies (keep last 5)
        self._last_db_write_time: Optional[float] = None  # Last write duration in ms
        
    async def connect(self, websocket: WebSocket):
        """Accept new WebSocket connection"""
        await websocket.accept()
        self.active_connections.add(websocket)
        
    def disconnect(self, websocket: WebSocket):
        """Remove WebSocket connection"""
        self.active_connections.discard(websocket)
        
    async def send_personal_message(self, message: dict, websocket: WebSocket):
        """Send message to specific client"""
        try:
            await websocket.send_json(message)
        except Exception:
            self.disconnect(websocket)
            
    async def broadcast(self, message: dict):
        """Broadcast message to all connected clients"""
        disconnected = set()
        
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                disconnected.add(connection)
        
        # Remove disconnected clients
        for connection in disconnected:
            self.disconnect(connection)
    
    async def start_broadcasting(self):
        """Start the broadcast loop"""
        if self.broadcast_task is None or self.broadcast_task.done():
            self.broadcast_task = asyncio.create_task(self._broadcast_loop())
    
    async def stop_broadcasting(self):
        """Stop the broadcast loop"""
        if self.broadcast_task and not self.broadcast_task.done():
            self.broadcast_task.cancel()
            try:
                await self.broadcast_task
            except asyncio.CancelledError:
                pass
        # Shutdown executor
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=False)
    
    def _should_throttle_collection(self, system_metrics: SystemMetrics) -> Tuple[bool, str]:
        """Check if collection should be throttled based on multiple factors
        
        Args:
            system_metrics: Current system metrics
            
        Returns:
            Tuple[bool, str]: (should_throttle, reason)
        """
        # Clean up completed tasks first
        self.pending_store_tasks = {t for t in self.pending_store_tasks if not t.done()}
        
        # 1. Check pending write queue depth
        if len(self.pending_store_tasks) >= settings.max_pending_write_tasks:
            return (True, f"pending_writes:{len(self.pending_store_tasks)}")
        
        # 2. Check DB write latency (average of last 3 writes)
        if self._db_write_times:
            avg_latency = sum(self._db_write_times[-3:]) / min(3, len(self._db_write_times))
            if avg_latency > settings.max_db_write_latency_ms:
                return (True, f"db_latency:{avg_latency:.1f}ms")
        
        # 3. Check I/O wait percentage
        io_wait = get_io_wait_percent()
        if io_wait > settings.max_io_wait_percent:
            return (True, f"io_wait:{io_wait:.1f}%")
        
        # 4. Check CPU usage
        if system_metrics.cpu_percent > settings.bandwidth_max_cpu_percent:
            return (True, f"cpu:{system_metrics.cpu_percent:.1f}%")
        
        # 5. Check loadavg (fallback)
        if system_metrics.load_avg_1m > settings.max_loadavg_1m:
            return (True, f"loadavg_1m:{system_metrics.load_avg_1m:.2f}")
        if system_metrics.load_avg_5m > settings.max_loadavg_5m:
            return (True, f"loadavg_5m:{system_metrics.load_avg_5m:.2f}")
        
        return (False, "")
    
    async def _broadcast_loop(self):
        """Background task that collects and broadcasts metrics"""
        while True:
            try:
                # Get system metrics first to check throttling
                system_metrics = collect_system_metrics()
                
                # Check if we should throttle collection
                should_throttle, throttle_reason = self._should_throttle_collection(system_metrics)
                
                if should_throttle:
                    print(f"Collection throttled: {throttle_reason}")
                    # Use throttled interval
                    collection_interval = settings.collection_interval_throttled
                else:
                    # Use normal interval
                    collection_interval = settings.collection_interval_normal
                
                # Always collect metrics and store in database (regardless of connections)
                metrics = await self._collect_all_metrics(should_throttle)
                
                # Only broadcast if we have connected clients
                if self.active_connections:
                    await self.broadcast({
                        "type": "metrics",
                        "data": metrics
                    })
                
                # Wait for next collection interval (dynamic based on throttling)
                await asyncio.sleep(collection_interval)
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"Error in broadcast loop: {e}")
                await asyncio.sleep(settings.collection_interval_normal)
    
    async def _collect_all_metrics(self, should_throttle: bool = False) -> dict:
        """Collect all metrics and store in database
        
        Args:
            should_throttle: If True, skip expensive collections
            
        Returns:
            dict: Serialized metrics snapshot
        """
        # Collect from all sources (lightweight collectors - always run)
        system_metrics = collect_system_metrics()
        interface_stats = collect_interface_stats()
        service_statuses = collect_service_statuses()
        dns_stats = collect_dns_stats()
        disk_io = collect_disk_io()
        temperatures = collect_temperatures()
        
        # Collect DHCP leases in executor (file I/O)
        loop = asyncio.get_event_loop()
        dhcp_leases = await loop.run_in_executor(self.executor, parse_kea_leases)
        
        # Collect client bandwidth (with CPU governance built-in) - run in executor
        client_bandwidth = []
        if settings.bandwidth_collection_enabled and not (should_throttle and not settings.bandwidth_collection_enabled_under_load):
            client_bandwidth = await loop.run_in_executor(self.executor, collect_client_bandwidth)
        
        # Collect client connections - run in executor, skip if throttled
        client_connections = []
        if settings.bandwidth_collection_enabled and not should_throttle:
            client_connections = await loop.run_in_executor(self.executor, collect_client_connections)
        
        # Collect CAKE statistics if enabled - run in executor
        cake_stats = None
        if not should_throttle:
            is_enabled, _ = await loop.run_in_executor(self.executor, is_cake_enabled)
            if is_enabled:
                cake_stats = await loop.run_in_executor(self.executor, collect_cake_stats)
        
        # Store in database asynchronously with task tracking
        # Clean up completed tasks first
        self.pending_store_tasks = {t for t in self.pending_store_tasks if not t.done()}
        
        # Only create new task if we don't have too many pending
        if len(self.pending_store_tasks) < 10:  # Max 10 pending store operations
            task = asyncio.create_task(self._store_metrics_with_semaphore(
                system_metrics,
                interface_stats,
                service_statuses,
                dhcp_leases,
                disk_io,
                temperatures,
                client_bandwidth,
                client_connections,
                cake_stats
            ))
            self.pending_store_tasks.add(task)
            # Remove task from set when done
            task.add_done_callback(self.pending_store_tasks.discard)
        
        # Create snapshot for broadcast
        snapshot = MetricsSnapshot(
            timestamp=datetime.now(timezone.utc),
            system=system_metrics,
            interfaces=interface_stats,
            services=service_statuses,
            dhcp_clients=dhcp_leases,
            dns_stats=dns_stats
        )
        
        return json.loads(snapshot.model_dump_json())
    
    async def _store_metrics_with_semaphore(
        self,
        system: SystemMetrics,
        interfaces: List[InterfaceStats],
        services: List[ServiceStatus],
        dhcp_leases: List[DHCPLease],
        disk_io: List,
        temperatures: List,
        client_bandwidth: List[dict] = None,
        client_connections: List[dict] = None,
        cake_stats = None
    ):
        """Wrapper that uses semaphore to limit concurrent store operations"""
        async with self._store_semaphore:
            await self._store_metrics(
                system,
                interfaces,
                services,
                dhcp_leases,
                disk_io,
                temperatures,
                client_bandwidth,
                client_connections,
                cake_stats
            )
    
    async def _store_metrics(
        self,
        system: SystemMetrics,
        interfaces: List[InterfaceStats],
        services: List[ServiceStatus],
        dhcp_leases: List[DHCPLease],
        disk_io: List,
        temperatures: List,
        client_bandwidth: List[dict] = None,
        client_connections: List[dict] = None,
        cake_stats = None
    ):
        """Store metrics in database
        
        Args:
            system: System metrics
            interfaces: Interface statistics
            services: Service statuses
            dhcp_leases: DHCP leases
            disk_io: Disk I/O metrics
            temperatures: Temperature metrics
            client_bandwidth: Client bandwidth statistics
        """
        try:
            async with AsyncSessionLocal() as session:
                # Store system metrics
                system_db = SystemMetricsDB(
                    timestamp=system.timestamp,
                    cpu_percent=system.cpu_percent,
                    memory_percent=system.memory_percent,
                    memory_used_mb=system.memory_used_mb,
                    memory_total_mb=system.memory_total_mb,
                    load_avg_1m=system.load_avg_1m,
                    load_avg_5m=system.load_avg_5m,
                    load_avg_15m=system.load_avg_15m,
                    uptime_seconds=system.uptime_seconds
                )
                session.add(system_db)
                
                # Store interface stats (bulk insert)
                if interfaces:
                    interface_mappings = [
                        {
                            'timestamp': iface.timestamp,
                            'interface': iface.interface,
                            'rx_bytes': iface.rx_bytes,
                            'tx_bytes': iface.tx_bytes,
                            'rx_packets': iface.rx_packets,
                            'tx_packets': iface.tx_packets,
                            'rx_errors': iface.rx_errors,
                            'tx_errors': iface.tx_errors,
                            'rx_dropped': iface.rx_dropped,
                            'tx_dropped': iface.tx_dropped
                        }
                        for iface in interfaces
                    ]
                    session.bulk_insert_mappings(InterfaceStatsDB, interface_mappings)
                
                # Store service statuses (bulk insert)
                if services:
                    service_mappings = [
                        {
                            'timestamp': service.timestamp,
                            'service_name': service.service_name,
                            'is_active': service.is_active,
                            'is_enabled': service.is_enabled,
                            'pid': service.pid,
                            'memory_mb': service.memory_mb,
                            'cpu_percent': service.cpu_percent
                        }
                        for service in services
                    ]
                    session.bulk_insert_mappings(ServiceStatusDB, service_mappings)
                
                # Optimized DHCP lease updates (batch queries instead of per-lease queries)
                if dhcp_leases:
                    from sqlalchemy import or_, and_
                    
                    # Build sets of MACs and IPs to query
                    networks = list(set(lease.network for lease in dhcp_leases))
                    mac_addresses = list(set(lease.mac_address for lease in dhcp_leases))
                    ip_addresses = list(set(lease.ip_address for lease in dhcp_leases))
                    
                    # Single batch query to get ALL existing leases matching our MACs or IPs
                    # Build OR conditions for (network, mac) pairs and (network, ip) pairs
                    conditions = []
                    for network in networks:
                        # Add conditions for MAC addresses in this network
                        if mac_addresses:
                            conditions.append(
                                and_(DHCPLeaseDB.network == network, DHCPLeaseDB.mac_address.in_(mac_addresses))
                            )
                        # Add conditions for IP addresses in this network
                        if ip_addresses:
                            conditions.append(
                                and_(DHCPLeaseDB.network == network, DHCPLeaseDB.ip_address.in_(ip_addresses))
                            )
                    
                    if conditions:
                        result = await session.execute(
                            select(DHCPLeaseDB).where(or_(*conditions))
                        )
                        existing_leases = result.scalars().all()
                    else:
                        existing_leases = []
                    
                    # Build lookup dictionaries: (network, mac) -> lease and (network, ip) -> lease
                    existing_by_mac_key: dict = {}  # (network, mac) -> DHCPLeaseDB
                    existing_by_ip_key: dict = {}   # (network, ip) -> DHCPLeaseDB
                    for existing in existing_leases:
                        mac_key = (existing.network, existing.mac_address)
                        ip_key = (existing.network, existing.ip_address)
                        existing_by_mac_key[mac_key] = existing
                        existing_by_ip_key[ip_key] = existing
                    
                    # Process leases in memory
                    leases_to_update = []  # List of (existing_lease, new_data)
                    leases_to_delete = []  # List of leases to delete
                    leases_to_insert = []  # List of new lease data
                    
                    for lease in dhcp_leases:
                        mac_key = (lease.network, lease.mac_address)
                        ip_key = (lease.network, lease.ip_address)
                        existing_by_mac = existing_by_mac_key.get(mac_key)
                        existing_by_ip = existing_by_ip_key.get(ip_key)
                        
                        if existing_by_mac:
                            # Device (MAC) exists - update it
                            # If IP changed and conflicts with another device, delete the conflict
                            if existing_by_mac.ip_address != lease.ip_address:
                                if existing_by_ip and existing_by_ip.id != existing_by_mac.id:
                                    leases_to_delete.append(existing_by_ip)
                                    # Remove from lookup dicts to avoid processing again
                                    if (existing_by_ip.network, existing_by_ip.ip_address) in existing_by_ip_key:
                                        del existing_by_ip_key[(existing_by_ip.network, existing_by_ip.ip_address)]
                            
                            leases_to_update.append((existing_by_mac, {
                                'ip_address': lease.ip_address,
                                'hostname': lease.hostname,
                                'lease_start': lease.lease_start,
                                'lease_end': lease.lease_end,
                                'last_seen': lease.last_seen,
                                'is_static': lease.is_static
                            }))
                        elif existing_by_ip:
                            # IP exists but MAC changed - check if new MAC has existing lease
                            existing_new_mac = existing_by_mac_key.get(mac_key)
                            if existing_new_mac:
                                # New MAC already has a lease - delete old IP lease, update MAC's lease
                                leases_to_delete.append(existing_by_ip)
                                leases_to_update.append((existing_new_mac, {
                                    'ip_address': lease.ip_address,
                                    'hostname': lease.hostname,
                                    'lease_start': lease.lease_start,
                                    'lease_end': lease.lease_end,
                                    'last_seen': lease.last_seen,
                                    'is_static': lease.is_static
                                }))
                            else:
                                # Update IP lease with new MAC
                                leases_to_update.append((existing_by_ip, {
                                    'mac_address': lease.mac_address,
                                    'hostname': lease.hostname,
                                    'lease_start': lease.lease_start,
                                    'lease_end': lease.lease_end,
                                    'last_seen': lease.last_seen,
                                    'is_static': lease.is_static
                                }))
                        else:
                            # New lease - insert
                            leases_to_insert.append({
                                'network': lease.network,
                                'mac_address': lease.mac_address,
                                'ip_address': lease.ip_address,
                                'hostname': lease.hostname,
                                'lease_start': lease.lease_start,
                                'lease_end': lease.lease_end,
                                'last_seen': lease.last_seen,
                                'is_static': lease.is_static
                            })
                    
                    # Execute batch operations
                    # Delete conflicting leases first
                    for lease_to_delete in leases_to_delete:
                        await session.delete(lease_to_delete)
                    if leases_to_delete:
                        await session.flush()  # Ensure deletions are visible
                    
                    # Update existing leases
                    for existing_lease, update_data in leases_to_update:
                        for key, value in update_data.items():
                            setattr(existing_lease, key, value)
                    
                    # Bulk insert new leases
                    if leases_to_insert:
                        session.bulk_insert_mappings(DHCPLeaseDB, leases_to_insert)
                
                # Store disk I/O metrics (bulk insert)
                if disk_io:
                    disk_mappings = [
                        {
                            'timestamp': disk.timestamp,
                            'device': disk.device,
                            'read_bytes_per_sec': disk.read_bytes_per_sec,
                            'write_bytes_per_sec': disk.write_bytes_per_sec,
                            'read_ops_per_sec': disk.read_ops_per_sec,
                            'write_ops_per_sec': disk.write_ops_per_sec
                        }
                        for disk in disk_io
                    ]
                    session.bulk_insert_mappings(DiskIOMetricsDB, disk_mappings)
                
                # Store temperature metrics (bulk insert)
                if temperatures:
                    temp_mappings = [
                        {
                            'timestamp': temp.timestamp,
                            'sensor_name': temp.sensor_name,
                            'temperature_c': temp.temperature_c,
                            'label': temp.label,
                            'critical': temp.critical
                        }
                        for temp in temperatures
                    ]
                    session.bulk_insert_mappings(TemperatureMetricsDB, temp_mappings)
                
                # Store client bandwidth statistics (bulk insert)
                if client_bandwidth:
                    bandwidth_mappings = [
                        {
                            'timestamp': bw_data['timestamp'],
                            'mac_address': bw_data['mac_address'],
                            'ip_address': bw_data['ip_address'],
                            'network': bw_data['network'],
                            'rx_bytes': bw_data['rx_bytes'],
                            'tx_bytes': bw_data['tx_bytes'],
                            'rx_bytes_total': bw_data['rx_bytes_total'],
                            'tx_bytes_total': bw_data['tx_bytes_total'],
                            'aggregation_level': 'raw'
                        }
                        for bw_data in client_bandwidth
                    ]
                    session.bulk_insert_mappings(ClientBandwidthStatsDB, bandwidth_mappings)
                
                # Store client connection statistics (bulk insert)
                if client_connections:
                    connection_mappings = [
                        {
                            'timestamp': conn_data['timestamp'],
                            'client_ip': conn_data['client_ip'],
                            'client_mac': conn_data['client_mac'],
                            'remote_ip': conn_data['remote_ip'],
                            'remote_port': conn_data['remote_port'],
                            'rx_bytes': conn_data['rx_bytes'],
                            'tx_bytes': conn_data['tx_bytes'],
                            'rx_bytes_total': conn_data['rx_bytes_total'],
                            'tx_bytes_total': conn_data['tx_bytes_total'],
                            'aggregation_level': 'raw'
                        }
                        for conn_data in client_connections
                    ]
                    session.bulk_insert_mappings(ClientConnectionStatsDB, connection_mappings)
                
                # Store CAKE statistics if available
                if cake_stats:
                    import json
                    cake_dict = cake_stats_to_dict(cake_stats)
                    cake_db = CakeStatsDB(
                        timestamp=cake_stats.timestamp,
                        interface=cake_stats.interface,
                        rate_mbps=cake_stats.rate_mbps,
                        target_ms=cake_stats.target_ms,
                        interval_ms=cake_stats.interval_ms,
                        classes=json.dumps(cake_dict['classes']),  # Store classes as JSON string
                        way_inds=cake_stats.way_inds,
                        way_miss=cake_stats.way_miss,
                        way_cols=cake_stats.way_cols
                    )
                    session.add(cake_db)
                
                # Track DB write latency
                commit_start = time.time()
                await session.commit()
                commit_duration_ms = (time.time() - commit_start) * 1000
                
                # Track write times (keep last 5)
                self._db_write_times.append(commit_duration_ms)
                if len(self._db_write_times) > 5:
                    self._db_write_times.pop(0)
                self._last_db_write_time = commit_duration_ms
                
        except Exception as e:
            # Log the full error for debugging
            import traceback
            error_details = traceback.format_exc()
            print(f"Error storing metrics: {e}")
            print(f"Error details: {error_details}")
            
            # If it's a constraint violation, try to provide more context
            if "UniqueViolationError" in str(type(e)) or "duplicate key" in str(e).lower():
                print("This appears to be a database constraint violation.")
                print("If you see 'dhcp_leases_ip_address_key', the old constraint may still exist.")
                print("Run the migration: webui/backend/migrations/001_mac_based_tracking.sql")


# Global connection manager instance
manager = ConnectionManager()


async def websocket_endpoint(websocket: WebSocket, token: str):
    """WebSocket endpoint handler
    
    Args:
        websocket: WebSocket connection
        token: JWT authentication token
    """
    from .auth import decode_access_token
    
    # Verify authentication
    username = decode_access_token(token)
    if not username:
        await websocket.close(code=4001, reason="Invalid authentication token")
        return
    
    await manager.connect(websocket)
    
    try:
        while True:
            # Keep connection alive and handle incoming messages
            data = await websocket.receive_text()
            
            # Echo back (can handle commands in the future)
            await manager.send_personal_message(
                {"type": "echo", "data": data},
                websocket
            )
            
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"WebSocket error: {e}")
        manager.disconnect(websocket)

