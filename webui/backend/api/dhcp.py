"""
DHCP management API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
import subprocess
import logging
import socket
import os

from ..database import get_db, DhcpNetworkDB, DhcpReservationDB
from ..models import (
    DhcpNetwork, DhcpNetworkCreate, DhcpNetworkUpdate,
    DhcpReservation, DhcpReservationCreate, DhcpReservationUpdate
)
from ..api.auth import get_current_user
from ..collectors.services import get_service_status

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dhcp", tags=["dhcp"])

# DHCP service name (single service for all networks)
DHCP_SERVICE_NAME = "kea-dhcp4-server"


def _control_service_via_systemctl(service_name: str, action: str) -> None:
    """Control a systemd service via socket-activated helper service (runs as root)
    
    Uses a socket-activated service that runs as root and accepts commands via
    a Unix socket. This follows NixOS best practices by avoiding direct sudo
    usage in systemd services.
    
    Args:
        service_name: Name of the service (e.g., "kea-dhcp4-server.service")
        action: Action to perform ("start", "stop", "restart", "reload")
        
    Raises:
        subprocess.CalledProcessError: If the command fails
    """
    # Validate action
    valid_actions = ['start', 'stop', 'restart', 'reload']
    if action.lower() not in valid_actions:
        logger.error(f"Invalid action: {action}")
        raise ValueError(f"Invalid action: {action}. Must be one of: {valid_actions}")
    
    socket_path = "/run/router-webui/service-control.sock"
    
    # Send command to socket (format: "ACTION SERVICE\n")
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(30)
        sock.connect(socket_path)
        command = f"{action.lower()} {service_name}\n"
        sock.sendall(command.encode('utf-8'))
        sock.shutdown(socket.SHUT_WR)
        
        # Read response
        response = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            response += data
        
        sock.close()
        
        # Check if there was an error in the response
        response_str = response.decode('utf-8', errors='ignore')
        if "Invalid" in response_str or "Failed" in response_str or "error" in response_str.lower():
            logger.error(f"Service control returned error: {response_str}")
            raise subprocess.CalledProcessError(1, f"socket command", stderr=response_str)
        
    except (socket.error, OSError) as e:
        logger.error(f"Failed to communicate with service control socket: {e}")
        raise subprocess.CalledProcessError(1, f"socket command", stderr=str(e))


@router.get("/networks", response_model=List[DhcpNetwork])
async def get_networks(
    network: Optional[str] = None,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> List[DhcpNetwork]:
    """Get list of DHCP networks
    
    Args:
        network: Optional filter by network ("homelab" or "lan")
        
    Returns:
        List of DHCP networks
    """
    query = select(DhcpNetworkDB)
    if network:
        if network not in ['homelab', 'lan']:
            raise HTTPException(status_code=400, detail="Network must be 'homelab' or 'lan'")
        query = query.where(DhcpNetworkDB.network == network)
    
    query = query.order_by(DhcpNetworkDB.network)
    result = await db.execute(query)
    networks = result.scalars().all()
    
    # Convert database models to Pydantic models, converting INET types to strings
    result_networks = []
    for net in networks:
        net_dict = {
            'id': net.id,
            'network': net.network,
            'enabled': net.enabled,
            'start': str(net.start) if net.start else '',
            'end': str(net.end) if net.end else '',
            'lease_time': net.lease_time,
            'dns_servers': [str(ip) for ip in net.dns_servers] if net.dns_servers else None,
            'dynamic_domain': net.dynamic_domain,
            'original_config_path': net.original_config_path,
            'created_at': net.created_at,
            'updated_at': net.updated_at,
        }
        result_networks.append(DhcpNetwork.model_validate(net_dict))
    
    return result_networks


@router.post("/networks", response_model=DhcpNetwork)
async def create_network(
    network: DhcpNetworkCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpNetwork:
    """Create a new DHCP network
    
    Args:
        network: Network creation data
        
    Returns:
        Created network
    """
    # Check if network already exists
    result = await db.execute(
        select(DhcpNetworkDB).where(
            DhcpNetworkDB.network == network.network
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"DHCP network {network.network} already exists"
        )
    
    db_network = DhcpNetworkDB(
        network=network.network,
        enabled=network.enabled,
        start=network.start,
        end=network.end,
        lease_time=network.lease_time,
        dns_servers=network.dns_servers,
        dynamic_domain=network.dynamic_domain,
        original_config_path=network.original_config_path
    )
    db.add(db_network)
    await db.commit()
    await db.refresh(db_network)
    
    # Convert INET types to strings
    net_dict = {
        'id': db_network.id,
        'network': db_network.network,
        'enabled': db_network.enabled,
        'start': str(db_network.start) if db_network.start else '',
        'end': str(db_network.end) if db_network.end else '',
        'lease_time': db_network.lease_time,
        'dns_servers': [str(ip) for ip in db_network.dns_servers] if db_network.dns_servers else None,
        'dynamic_domain': db_network.dynamic_domain,
        'original_config_path': db_network.original_config_path,
        'created_at': db_network.created_at,
        'updated_at': db_network.updated_at,
    }
    return DhcpNetwork.model_validate(net_dict)


@router.get("/networks/{network_id}", response_model=DhcpNetwork)
async def get_network(
    network_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpNetwork:
    """Get a specific DHCP network by ID
    
    Args:
        network_id: Network ID
        
    Returns:
        DHCP network
    """
    result = await db.execute(
        select(DhcpNetworkDB).where(DhcpNetworkDB.id == network_id)
    )
    network = result.scalar_one_or_none()
    if not network:
        raise HTTPException(status_code=404, detail="DHCP network not found")
    
    # Convert INET types to strings
    net_dict = {
        'id': network.id,
        'network': network.network,
        'enabled': network.enabled,
        'start': str(network.start) if network.start else '',
        'end': str(network.end) if network.end else '',
        'lease_time': network.lease_time,
        'dns_servers': [str(ip) for ip in network.dns_servers] if network.dns_servers else None,
        'dynamic_domain': network.dynamic_domain,
        'original_config_path': network.original_config_path,
        'created_at': network.created_at,
        'updated_at': network.updated_at,
    }
    return DhcpNetwork.model_validate(net_dict)


@router.put("/networks/{network_id}", response_model=DhcpNetwork)
async def update_network(
    network_id: int,
    network_update: DhcpNetworkUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpNetwork:
    """Update a DHCP network
    
    Args:
        network_id: Network ID
        network_update: Update data
        
    Returns:
        Updated network
    """
    result = await db.execute(
        select(DhcpNetworkDB).where(DhcpNetworkDB.id == network_id)
    )
    network = result.scalar_one_or_none()
    if not network:
        raise HTTPException(status_code=404, detail="DHCP network not found")
    
    # Update fields
    update_data = network_update.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(network, field, value)
    
    await db.commit()
    await db.refresh(network)
    
    # Convert INET types to strings
    net_dict = {
        'id': network.id,
        'network': network.network,
        'enabled': network.enabled,
        'start': str(network.start) if network.start else '',
        'end': str(network.end) if network.end else '',
        'lease_time': network.lease_time,
        'dns_servers': [str(ip) for ip in network.dns_servers] if network.dns_servers else None,
        'dynamic_domain': network.dynamic_domain,
        'original_config_path': network.original_config_path,
        'created_at': network.created_at,
        'updated_at': network.updated_at,
    }
    return DhcpNetwork.model_validate(net_dict)


@router.delete("/networks/{network_id}")
async def delete_network(
    network_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a DHCP network (cascades to reservations)
    
    Args:
        network_id: Network ID
    """
    result = await db.execute(
        select(DhcpNetworkDB).where(DhcpNetworkDB.id == network_id)
    )
    network = result.scalar_one_or_none()
    if not network:
        raise HTTPException(status_code=404, detail="DHCP network not found")
    
    await db.delete(network)
    await db.commit()
    
    return {"message": "DHCP network deleted"}


@router.get("/networks/{network_id}/reservations", response_model=List[DhcpReservation])
async def get_reservations(
    network_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> List[DhcpReservation]:
    """Get list of DHCP reservations for a network
    
    Args:
        network_id: Network ID
        
    Returns:
        List of DHCP reservations
    """
    # Verify network exists
    result = await db.execute(
        select(DhcpNetworkDB).where(DhcpNetworkDB.id == network_id)
    )
    network = result.scalar_one_or_none()
    if not network:
        raise HTTPException(status_code=404, detail="DHCP network not found")
    
    result = await db.execute(
        select(DhcpReservationDB)
        .where(DhcpReservationDB.network_id == network_id)
        .order_by(DhcpReservationDB.hostname)
    )
    reservations = result.scalars().all()
    
    # Convert database models to Pydantic models, converting MACADDR and INET types to strings
    result_reservations = []
    for res in reservations:
        res_dict = {
            'id': res.id,
            'network_id': res.network_id,
            'hostname': res.hostname,
            'hw_address': str(res.hw_address) if res.hw_address else '',
            'ip_address': str(res.ip_address) if res.ip_address else '',
            'comment': res.comment,
            'enabled': res.enabled,
            'original_config_path': res.original_config_path,
            'created_at': res.created_at,
            'updated_at': res.updated_at,
        }
        result_reservations.append(DhcpReservation.model_validate(res_dict))
    
    return result_reservations


@router.post("/networks/{network_id}/reservations", response_model=DhcpReservation)
async def create_reservation(
    network_id: int,
    reservation: DhcpReservationCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpReservation:
    """Create a new DHCP reservation
    
    Args:
        network_id: Network ID
        reservation: Reservation creation data (network_id will be overridden)
        
    Returns:
        Created reservation
    """
    # Verify network exists
    result = await db.execute(
        select(DhcpNetworkDB).where(DhcpNetworkDB.id == network_id)
    )
    network = result.scalar_one_or_none()
    if not network:
        raise HTTPException(status_code=404, detail="DHCP network not found")
    
    # Check if reservation with same MAC already exists in this network
    result = await db.execute(
        select(DhcpReservationDB).where(
            DhcpReservationDB.network_id == network_id,
            DhcpReservationDB.hw_address == reservation.hw_address
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Reservation with MAC {reservation.hw_address} already exists for this network"
        )
    
    # Check if IP address is already reserved in this network
    result = await db.execute(
        select(DhcpReservationDB).where(
            DhcpReservationDB.network_id == network_id,
            DhcpReservationDB.ip_address == reservation.ip_address
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"IP address {reservation.ip_address} is already reserved in this network"
        )
    
    db_reservation = DhcpReservationDB(
        network_id=network_id,
        hostname=reservation.hostname,
        hw_address=reservation.hw_address,
        ip_address=reservation.ip_address,
        comment=reservation.comment,
        enabled=reservation.enabled,
        original_config_path=reservation.original_config_path
    )
    db.add(db_reservation)
    await db.commit()
    await db.refresh(db_reservation)
    
    # Convert MACADDR and INET types to strings
    res_dict = {
        'id': db_reservation.id,
        'network_id': db_reservation.network_id,
        'hostname': db_reservation.hostname,
        'hw_address': str(db_reservation.hw_address) if db_reservation.hw_address else '',
        'ip_address': str(db_reservation.ip_address) if db_reservation.ip_address else '',
        'comment': db_reservation.comment,
        'enabled': db_reservation.enabled,
        'original_config_path': db_reservation.original_config_path,
        'created_at': db_reservation.created_at,
        'updated_at': db_reservation.updated_at,
    }
    return DhcpReservation.model_validate(res_dict)


@router.get("/reservations/{reservation_id}", response_model=DhcpReservation)
async def get_reservation(
    reservation_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpReservation:
    """Get a specific DHCP reservation by ID
    
    Args:
        reservation_id: Reservation ID
        
    Returns:
        DHCP reservation
    """
    result = await db.execute(
        select(DhcpReservationDB).where(DhcpReservationDB.id == reservation_id)
    )
    reservation = result.scalar_one_or_none()
    if not reservation:
        raise HTTPException(status_code=404, detail="DHCP reservation not found")
    
    # Convert MACADDR and INET types to strings
    res_dict = {
        'id': reservation.id,
        'network_id': reservation.network_id,
        'hostname': reservation.hostname,
        'hw_address': str(reservation.hw_address) if reservation.hw_address else '',
        'ip_address': str(reservation.ip_address) if reservation.ip_address else '',
        'comment': reservation.comment,
        'enabled': reservation.enabled,
        'original_config_path': reservation.original_config_path,
        'created_at': reservation.created_at,
        'updated_at': reservation.updated_at,
    }
    return DhcpReservation.model_validate(res_dict)


@router.put("/reservations/{reservation_id}", response_model=DhcpReservation)
async def update_reservation(
    reservation_id: int,
    reservation_update: DhcpReservationUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DhcpReservation:
    """Update a DHCP reservation
    
    Args:
        reservation_id: Reservation ID
        reservation_update: Update data
        
    Returns:
        Updated reservation
    """
    result = await db.execute(
        select(DhcpReservationDB).where(DhcpReservationDB.id == reservation_id)
    )
    reservation = result.scalar_one_or_none()
    if not reservation:
        raise HTTPException(status_code=404, detail="DHCP reservation not found")
    
    # If network_id is being changed, verify new network exists
    if reservation_update.network_id is not None and reservation_update.network_id != reservation.network_id:
        result = await db.execute(
            select(DhcpNetworkDB).where(DhcpNetworkDB.id == reservation_update.network_id)
        )
        new_network = result.scalar_one_or_none()
        if not new_network:
            raise HTTPException(status_code=404, detail="Target DHCP network not found")
        
        # Check for conflicts in new network
        if reservation_update.hw_address:
            result = await db.execute(
                select(DhcpReservationDB).where(
                    DhcpReservationDB.network_id == reservation_update.network_id,
                    DhcpReservationDB.hw_address == reservation_update.hw_address,
                    DhcpReservationDB.id != reservation_id
                )
            )
            if result.scalar_one_or_none():
                raise HTTPException(
                    status_code=400,
                    detail=f"MAC address {reservation_update.hw_address} already reserved in target network"
                )
        
        if reservation_update.ip_address:
            result = await db.execute(
                select(DhcpReservationDB).where(
                    DhcpReservationDB.network_id == reservation_update.network_id,
                    DhcpReservationDB.ip_address == reservation_update.ip_address,
                    DhcpReservationDB.id != reservation_id
                )
            )
            if result.scalar_one_or_none():
                raise HTTPException(
                    status_code=400,
                    detail=f"IP address {reservation_update.ip_address} already reserved in target network"
                )
    
    # Check for conflicts in current network if MAC or IP is being updated
    if reservation_update.hw_address and reservation_update.hw_address != reservation.hw_address:
        result = await db.execute(
            select(DhcpReservationDB).where(
                DhcpReservationDB.network_id == reservation.network_id,
                DhcpReservationDB.hw_address == reservation_update.hw_address,
                DhcpReservationDB.id != reservation_id
            )
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=400,
                detail=f"MAC address {reservation_update.hw_address} already reserved in this network"
            )
    
    if reservation_update.ip_address and reservation_update.ip_address != reservation.ip_address:
        result = await db.execute(
            select(DhcpReservationDB).where(
                DhcpReservationDB.network_id == reservation.network_id,
                DhcpReservationDB.ip_address == reservation_update.ip_address,
                DhcpReservationDB.id != reservation_id
            )
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=400,
                detail=f"IP address {reservation_update.ip_address} already reserved in this network"
            )
    
    # Update fields
    update_data = reservation_update.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(reservation, field, value)
    
    await db.commit()
    await db.refresh(reservation)
    
    # Convert MACADDR and INET types to strings
    res_dict = {
        'id': reservation.id,
        'network_id': reservation.network_id,
        'hostname': reservation.hostname,
        'hw_address': str(reservation.hw_address) if reservation.hw_address else '',
        'ip_address': str(reservation.ip_address) if reservation.ip_address else '',
        'comment': reservation.comment,
        'enabled': reservation.enabled,
        'original_config_path': reservation.original_config_path,
        'created_at': reservation.created_at,
        'updated_at': reservation.updated_at,
    }
    return DhcpReservation.model_validate(res_dict)


@router.delete("/reservations/{reservation_id}")
async def delete_reservation(
    reservation_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a DHCP reservation
    
    Args:
        reservation_id: Reservation ID
    """
    result = await db.execute(
        select(DhcpReservationDB).where(DhcpReservationDB.id == reservation_id)
    )
    reservation = result.scalar_one_or_none()
    if not reservation:
        raise HTTPException(status_code=404, detail="DHCP reservation not found")
    
    await db.delete(reservation)
    await db.commit()
    
    return {"message": "DHCP reservation deleted"}


@router.get("/service-status")
async def get_dhcp_service_status(
    _: str = Depends(get_current_user)
):
    """Get DHCP service status
    
    Uses systemctl to retrieve status (same approach as other services).
    Reading status doesn't require sudo, only control operations do.
    
    Returns:
        Service status information
    """
    # Use the same get_service_status function that other services use
    status = get_service_status(DHCP_SERVICE_NAME)
    
    if status is None:
        return {
            "service_name": DHCP_SERVICE_NAME,
            "is_active": False,
            "is_enabled": False,
            "exists": False
        }
    
    return {
        "service_name": DHCP_SERVICE_NAME,
        "is_active": status.is_active,
        "is_enabled": status.is_enabled,
        "exists": True,
        "pid": status.pid,
        "memory_mb": status.memory_mb,
        "cpu_percent": status.cpu_percent
    }


@router.post("/service/{action}")
async def control_dhcp_service(
    action: str,
    _: str = Depends(get_current_user)
):
    """Control DHCP service
    
    Args:
        action: Action to perform ("start", "stop", "restart", "reload")
        
    Returns:
        Success message
    """
    if action not in ['start', 'stop', 'restart', 'reload']:
        logger.warning(f"Invalid action requested: {action}")
        raise HTTPException(status_code=400, detail="Action must be 'start', 'stop', 'restart', or 'reload'")
    
    full_service_name = f"{DHCP_SERVICE_NAME}.service"
    
    try:
        # Use socket-based service control
        _control_service_via_systemctl(full_service_name, action)
        logger.info(f"Successfully {action}ed service {DHCP_SERVICE_NAME}")
        
        return {
            "message": f"Service {DHCP_SERVICE_NAME} {action}ed successfully",
            "action": action,
            "service_name": DHCP_SERVICE_NAME
        }
    except subprocess.CalledProcessError as e:
        error_msg = e.stderr or e.stdout or str(e)
        logger.error(f"Failed to {action} service {DHCP_SERVICE_NAME}: returncode={e.returncode}, stderr={e.stderr[:500] if e.stderr else None}, stdout={e.stdout[:500] if e.stdout else None}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to {action} service {DHCP_SERVICE_NAME}: {error_msg}"
        )
    except (subprocess.TimeoutExpired, ValueError, RuntimeError) as e:
        logger.error(f"Error while trying to {action} service {DHCP_SERVICE_NAME}: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error while trying to {action} service {DHCP_SERVICE_NAME}: {str(e)}"
        )

