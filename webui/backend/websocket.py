"""
WebSocket connection manager and metrics broadcaster
"""
import asyncio
import json
from typing import List, Set
from fastapi import WebSocket, WebSocketDisconnect
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import MetricsSnapshot, SystemMetrics, InterfaceStats, ServiceStatus, DHCPLease, DNSMetrics
from .database import AsyncSessionLocal, SystemMetricsDB, InterfaceStatsDB, ServiceStatusDB, DHCPLeaseDB, DiskIOMetricsDB, TemperatureMetricsDB, ClientBandwidthStatsDB, ClientConnectionStatsDB
from .collectors.system import collect_system_metrics, collect_disk_io, collect_temperatures
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
    
    async def _broadcast_loop(self):
        """Background task that collects and broadcasts metrics"""
        while True:
            try:
                # Always collect metrics and store in database (regardless of connections)
                metrics = await self._collect_all_metrics()
                
                # Only broadcast if we have connected clients
                if self.active_connections:
                    await self.broadcast({
                        "type": "metrics",
                        "data": metrics
                    })
                
                # Wait for next collection interval
                await asyncio.sleep(settings.collection_interval)
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"Error in broadcast loop: {e}")
                await asyncio.sleep(settings.collection_interval)
    
    async def _collect_all_metrics(self) -> dict:
        """Collect all metrics and store in database
        
        Returns:
            dict: Serialized metrics snapshot
        """
        # Collect from all sources
        system_metrics = collect_system_metrics()
        interface_stats = collect_interface_stats()
        dhcp_leases = parse_kea_leases()
        service_statuses = collect_service_statuses()
        dns_stats = collect_dns_stats()
        disk_io = collect_disk_io()
        temperatures = collect_temperatures()
        
        # Collect client bandwidth (with CPU governance built-in)
        client_bandwidth = collect_client_bandwidth() if settings.bandwidth_collection_enabled else []
        
        # Collect client connections
        client_connections = collect_client_connections() if settings.bandwidth_collection_enabled else []
        
        # Collect CAKE statistics if enabled
        cake_stats = None
        if is_cake_enabled()[0]:  # Check if CAKE is enabled
            cake_stats = collect_cake_stats()
        
        # Store in database asynchronously
        asyncio.create_task(self._store_metrics(
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
                
                # Store interface stats
                for iface in interfaces:
                    iface_db = InterfaceStatsDB(
                        timestamp=iface.timestamp,
                        interface=iface.interface,
                        rx_bytes=iface.rx_bytes,
                        tx_bytes=iface.tx_bytes,
                        rx_packets=iface.rx_packets,
                        tx_packets=iface.tx_packets,
                        rx_errors=iface.rx_errors,
                        tx_errors=iface.tx_errors,
                        rx_dropped=iface.rx_dropped,
                        tx_dropped=iface.tx_dropped
                    )
                    session.add(iface_db)
                
                # Store service statuses
                for service in services:
                    service_db = ServiceStatusDB(
                        timestamp=service.timestamp,
                        service_name=service.service_name,
                        is_active=service.is_active,
                        is_enabled=service.is_enabled,
                        pid=service.pid,
                        memory_mb=service.memory_mb,
                        cpu_percent=service.cpu_percent
                    )
                    session.add(service_db)
                
                # Update DHCP leases (upsert based on MAC+network or IP+network)
                for lease in dhcp_leases:
                    # First check if device (MAC) exists in this network
                    result_mac = await session.execute(
                        select(DHCPLeaseDB).where(
                            DHCPLeaseDB.network == lease.network,
                            DHCPLeaseDB.mac_address == lease.mac_address
                        )
                    )
                    existing_by_mac = result_mac.scalar_one_or_none()
                    
                    # Also check if IP address exists in this network (IP may have been reassigned)
                    result_ip = await session.execute(
                        select(DHCPLeaseDB).where(
                            DHCPLeaseDB.network == lease.network,
                            DHCPLeaseDB.ip_address == lease.ip_address
                        )
                    )
                    existing_by_ip = result_ip.scalar_one_or_none()
                    
                    if existing_by_mac:
                        # Update existing device lease (IP may have changed)
                        # Check if the new IP is already assigned to a different device
                        if existing_by_mac.ip_address != lease.ip_address and existing_by_ip and existing_by_ip.id != existing_by_mac.id:
                            # IP was reassigned - delete the old IP assignment first
                            await session.delete(existing_by_ip)
                        
                        existing_by_mac.ip_address = lease.ip_address
                        existing_by_mac.hostname = lease.hostname
                        existing_by_mac.lease_start = lease.lease_start
                        existing_by_mac.lease_end = lease.lease_end
                        existing_by_mac.last_seen = lease.last_seen
                        existing_by_mac.is_static = lease.is_static
                    elif existing_by_ip:
                        # IP was reassigned to a different MAC
                        # Check if the new MAC already has a lease (to avoid MAC constraint violation)
                        result_new_mac = await session.execute(
                            select(DHCPLeaseDB).where(
                                DHCPLeaseDB.network == lease.network,
                                DHCPLeaseDB.mac_address == lease.mac_address
                            )
                        )
                        existing_new_mac = result_new_mac.scalar_one_or_none()
                        
                        if existing_new_mac:
                            # New MAC already has a lease - delete the old IP lease and update the MAC's lease
                            await session.delete(existing_by_ip)
                            existing_new_mac.ip_address = lease.ip_address
                            existing_new_mac.hostname = lease.hostname
                            existing_new_mac.lease_start = lease.lease_start
                            existing_new_mac.lease_end = lease.lease_end
                            existing_new_mac.last_seen = lease.last_seen
                            existing_new_mac.is_static = lease.is_static
                        else:
                            # Update the IP lease with the new MAC
                            existing_by_ip.mac_address = lease.mac_address
                            existing_by_ip.hostname = lease.hostname
                            existing_by_ip.lease_start = lease.lease_start
                            existing_by_ip.lease_end = lease.lease_end
                            existing_by_ip.last_seen = lease.last_seen
                            existing_by_ip.is_static = lease.is_static
                    else:
                        # Insert new device
                        lease_db = DHCPLeaseDB(
                            network=lease.network,
                            mac_address=lease.mac_address,
                            ip_address=lease.ip_address,
                            hostname=lease.hostname,
                            lease_start=lease.lease_start,
                            lease_end=lease.lease_end,
                            last_seen=lease.last_seen,
                            is_static=lease.is_static
                        )
                        session.add(lease_db)
                
                # Store disk I/O metrics
                for disk in disk_io:
                    disk_db = DiskIOMetricsDB(
                        timestamp=disk.timestamp,
                        device=disk.device,
                        read_bytes_per_sec=disk.read_bytes_per_sec,
                        write_bytes_per_sec=disk.write_bytes_per_sec,
                        read_ops_per_sec=disk.read_ops_per_sec,
                        write_ops_per_sec=disk.write_ops_per_sec
                    )
                    session.add(disk_db)
                
                # Store temperature metrics
                for temp in temperatures:
                    temp_db = TemperatureMetricsDB(
                        timestamp=temp.timestamp,
                        sensor_name=temp.sensor_name,
                        temperature_c=temp.temperature_c,
                        label=temp.label,
                        critical=temp.critical
                    )
                    session.add(temp_db)
                
                # Store client bandwidth statistics
                if client_bandwidth:
                    for bw_data in client_bandwidth:
                        bw_db = ClientBandwidthStatsDB(
                            timestamp=bw_data['timestamp'],
                            mac_address=bw_data['mac_address'],
                            ip_address=bw_data['ip_address'],
                            network=bw_data['network'],
                            rx_bytes=bw_data['rx_bytes'],
                            tx_bytes=bw_data['tx_bytes'],
                            rx_bytes_total=bw_data['rx_bytes_total'],
                            tx_bytes_total=bw_data['tx_bytes_total'],
                            aggregation_level='raw'
                        )
                        session.add(bw_db)
                
                # Store client connection statistics
                if client_connections:
                    for conn_data in client_connections:
                        conn_db = ClientConnectionStatsDB(
                            timestamp=conn_data['timestamp'],
                            client_ip=conn_data['client_ip'],
                            client_mac=conn_data['client_mac'],
                            remote_ip=conn_data['remote_ip'],
                            remote_port=conn_data['remote_port'],
                            rx_bytes=conn_data['rx_bytes'],
                            tx_bytes=conn_data['tx_bytes'],
                            rx_bytes_total=conn_data['rx_bytes_total'],
                            tx_bytes_total=conn_data['tx_bytes_total'],
                            aggregation_level='raw'
                        )
                        session.add(conn_db)
                
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
                
                await session.commit()
                
        except Exception as e:
            print(f"Error storing metrics: {e}")


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

