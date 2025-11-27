"""
DHCP configuration utilities and migration functions
"""
import os
import logging
import re
from typing import Dict, List, Optional
from sqlalchemy import select
from ..database import DhcpNetworkDB, DhcpReservationDB
from ..config import settings

logger = logging.getLogger(__name__)


def parse_router_config_dhcp() -> Dict:
    """Parse router-config.nix file to extract DHCP configuration
    
    Returns:
        Dictionary with 'homelab' and 'lan' keys, each containing:
        - enable: bool
        - start: str (IP address)
        - end: str (IP address)
        - leaseTime: str
        - dnsServers: list of IP addresses
        - dynamicDomain: str (optional)
        - reservations: list of {hostname, hwAddress, ipAddress}
    """
    config_path = settings.router_config_file
    
    if not os.path.exists(config_path):
        logger.warning(f"router-config.nix not found at {config_path}, skipping DHCP migration")
        return {}
    
    logger.info(f"Parsing router-config.nix from {config_path}")
    
    config = {
        'homelab': {'reservations': []},
        'lan': {'reservations': []}
    }
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract DHCP configuration for each network
        for network in ['homelab', 'lan']:
            # Pattern to match: network = { ... dhcp = { ... } ... }
            pattern = rf'{network}\s*=\s*\{{([^}}]+dhcp\s*=\s*\{{[^}}]+\}}[^}}]*)\}}'
            match = re.search(pattern, content, re.DOTALL)
            
            if not match:
                logger.debug(f"No DHCP config found for {network}")
                continue
            
            network_block = match.group(1)
            
            # Extract DHCP block
            dhcp_pattern = r'dhcp\s*=\s*\{(.+?)\}'
            dhcp_match = re.search(dhcp_pattern, network_block, re.DOTALL)
            
            if not dhcp_match:
                logger.debug(f"No DHCP block found for {network}")
                continue
            
            dhcp_block = dhcp_match.group(1)
            
            # Extract enable
            enable_match = re.search(r'enable\s*=\s*(true|false)', dhcp_block)
            if enable_match:
                config[network]['enable'] = enable_match.group(1) == 'true'
            else:
                config[network]['enable'] = True  # Default
            
            # Extract start
            start_match = re.search(r'start\s*=\s*"([^"]+)"', dhcp_block)
            if start_match:
                config[network]['start'] = start_match.group(1)
            
            # Extract end
            end_match = re.search(r'end\s*=\s*"([^"]+)"', dhcp_block)
            if end_match:
                config[network]['end'] = end_match.group(1)
            
            # Extract leaseTime
            lease_match = re.search(r'leaseTime\s*=\s*"([^"]+)"', dhcp_block)
            if lease_match:
                config[network]['leaseTime'] = lease_match.group(1)
            
            # Extract dnsServers (array)
            dns_match = re.search(r'dnsServers\s*=\s*\[([^\]]+)\]', dhcp_block)
            if dns_match:
                dns_servers_str = dns_match.group(1)
                # Extract IP addresses from the array
                ip_pattern = r'"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"'
                config[network]['dnsServers'] = re.findall(ip_pattern, dns_servers_str)
            
            # Extract dynamicDomain
            domain_match = re.search(r'dynamicDomain\s*=\s*"([^"]*)"', dhcp_block)
            if domain_match:
                domain = domain_match.group(1)
                if domain:  # Only set if not empty
                    config[network]['dynamicDomain'] = domain
            
            # Extract reservations
            reservations_match = re.search(r'reservations\s*=\s*\[([^\]]*)\]', dhcp_block, re.DOTALL)
            if reservations_match:
                reservations_str = reservations_match.group(1)
                # Extract individual reservation objects
                # Pattern: { hostname = "name"; hwAddress = "mac"; ipAddress = "ip"; }
                reservation_pattern = r'\{\s*hostname\s*=\s*"([^"]+)";\s*hwAddress\s*=\s*"([^"]+)";\s*ipAddress\s*=\s*"([^"]+)"'
                reservations = re.findall(reservation_pattern, reservations_str)
                
                for hostname, hw_address, ip_address in reservations:
                    config[network]['reservations'].append({
                        'hostname': hostname,
                        'hwAddress': hw_address,
                        'ipAddress': ip_address
                    })
        
        return config
        
    except Exception as e:
        logger.error(f"Error parsing router-config.nix: {type(e).__name__}: {str(e)}", exc_info=True)
        return {}


async def migrate_dhcp_config_to_database(session):
    """Migrate DHCP configuration from router-config.nix to database
    
    This function:
    1. Reads DHCP config from router-config.nix
    2. Creates DHCP network entries for homelab/lan
    3. Creates DHCP reservation entries
    4. Skips entries that have already been migrated (based on original_config_path)
    """
    config = parse_router_config_dhcp()
    
    if not config:
        logger.info("No DHCP configuration found in router-config.nix, skipping migration")
        return
    
    migrated_networks = 0
    skipped_networks = 0
    migrated_reservations = 0
    skipped_reservations = 0
    
    try:
        for network in ['homelab', 'lan']:
            network_config = config.get(network, {})
            
            if not network_config.get('enable', True):
                logger.debug(f"DHCP disabled for {network}, skipping")
                continue
            
            # Check if required fields are present
            if 'start' not in network_config or 'end' not in network_config:
                logger.warning(f"Incomplete DHCP config for {network}, skipping")
                continue
            
            original_config_path = f"{network}.dhcp"
            
            # Check if network already exists
            result = await session.execute(
                select(DhcpNetworkDB).where(
                    DhcpNetworkDB.network == network,
                    DhcpNetworkDB.original_config_path == original_config_path
                )
            )
            existing_network = result.scalar_one_or_none()
            
            if existing_network:
                logger.debug(f"DHCP network {network} already exists, skipping")
                skipped_networks += 1
                network_id = existing_network.id
            else:
                # Create new DHCP network
                dhcp_network = DhcpNetworkDB(
                    network=network,
                    enabled=network_config.get('enable', True),
                    start=network_config['start'],
                    end=network_config['end'],
                    lease_time=network_config.get('leaseTime', '1h'),
                    dns_servers=network_config.get('dnsServers', []),
                    dynamic_domain=network_config.get('dynamicDomain'),
                    original_config_path=original_config_path
                )
                session.add(dhcp_network)
                await session.flush()  # Get the ID
                network_id = dhcp_network.id
                migrated_networks += 1
                logger.info(f"Created DHCP network: {network}")
            
            # Create reservations
            reservations = network_config.get('reservations', [])
            for res in reservations:
                original_res_path = f"{network}.dhcp.reservations.{res['hostname']}"
                
                # Check if reservation already exists
                result = await session.execute(
                    select(DhcpReservationDB).where(
                        DhcpReservationDB.network_id == network_id,
                        DhcpReservationDB.hw_address == res['hwAddress'],
                        DhcpReservationDB.original_config_path == original_res_path
                    )
                )
                existing_reservation = result.scalar_one_or_none()
                
                if existing_reservation:
                    logger.debug(f"Reservation {res['hostname']} ({network}) already exists, skipping")
                    skipped_reservations += 1
                    continue
                
                # Create new reservation
                reservation = DhcpReservationDB(
                    network_id=network_id,
                    hostname=res['hostname'],
                    hw_address=res['hwAddress'],
                    ip_address=res['ipAddress'],
                    enabled=True,
                    original_config_path=original_res_path
                )
                session.add(reservation)
                migrated_reservations += 1
                logger.info(f"Created DHCP reservation: {res['hostname']} -> {res['ipAddress']} ({network})")
        
        await session.commit()
        logger.info(f"DHCP migration complete: {migrated_networks} networks, {migrated_reservations} reservations migrated; "
                   f"{skipped_networks} networks, {skipped_reservations} reservations skipped")
        
    except Exception as e:
        logger.error(f"Error during DHCP migration: {type(e).__name__}: {str(e)}", exc_info=True)
        await session.rollback()
        raise

