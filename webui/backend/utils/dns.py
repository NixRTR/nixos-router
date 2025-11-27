"""
DNS configuration utilities and migration functions
"""
import os
import logging
import re
from typing import Dict, List, Tuple, Optional
from sqlalchemy import select
from ..database import DnsZoneDB, DnsRecordDB
from ..config import settings

logger = logging.getLogger(__name__)


def extract_base_domain(hostname: str) -> str:
    """Extract base domain from a hostname
    
    Args:
        hostname: Full hostname (e.g., "hera.jeandr.net")
        
    Returns:
        Base domain (e.g., "jeandr.net")
    """
    parts = hostname.split('.')
    if len(parts) >= 2:
        return '.'.join(parts[-2:])
    return hostname


def parse_nix_config() -> Dict:
    """Parse router-config.nix file to extract DNS configuration
    
    Returns:
        Dictionary with 'homelab' and 'lan' keys, each containing:
        - a_records: dict of hostname -> {ip, comment}
        - cname_records: dict of hostname -> {target, comment}
    """
    config_path = settings.router_config_file
    
    if not os.path.exists(config_path):
        logger.warning(f"router-config.nix not found at {config_path}, skipping DNS migration")
        return {}
    
    logger.info(f"Parsing router-config.nix from {config_path}")
    
    config = {
        'homelab': {'a_records': {}, 'cname_records': {}},
        'lan': {'a_records': {}, 'cname_records': {}}
    }
    
    try:
        with open(config_path, 'r') as f:
            content = f.read()
        
        # Helper function to extract content between matching braces
        def extract_braced_content(text: str, start_pos: int) -> tuple[Optional[str], int]:
            """Extract content between matching braces, returning content and end position"""
            if start_pos >= len(text) or text[start_pos] != '{':
                return None, start_pos
            depth = 0
            start = start_pos + 1
            i = start_pos
            while i < len(text):
                if text[i] == '{':
                    depth += 1
                elif text[i] == '}':
                    depth -= 1
                    if depth == 0:
                        return text[start:i].strip(), i + 1
                i += 1
            return None, start_pos
        
        # Find homelab section
        homelab_start = content.find('homelab =')
        if homelab_start != -1:
            # Find dns = within homelab
            homelab_dns_start = content.find('dns =', homelab_start)
            if homelab_dns_start != -1:
                # Find a_records = within dns
                a_records_start = content.find('a_records =', homelab_dns_start)
                if a_records_start != -1:
                    brace_start = content.find('{', a_records_start)
                    if brace_start != -1:
                        a_content, _ = extract_braced_content(content, brace_start)
                        if a_content:
                            config['homelab']['a_records'] = _parse_a_records(a_content)
                
                # Find cname_records = within dns
                cname_records_start = content.find('cname_records =', homelab_dns_start)
                if cname_records_start != -1:
                    brace_start = content.find('{', cname_records_start)
                    if brace_start != -1:
                        cname_content, _ = extract_braced_content(content, brace_start)
                        if cname_content:
                            config['homelab']['cname_records'] = _parse_cname_records(cname_content)
        
        # Find lan section
        lan_start = content.find('lan =')
        if lan_start != -1:
            # Find dns = within lan
            lan_dns_start = content.find('dns =', lan_start)
            if lan_dns_start != -1:
                # Find a_records = within dns
                a_records_start = content.find('a_records =', lan_dns_start)
                if a_records_start != -1:
                    brace_start = content.find('{', a_records_start)
                    if brace_start != -1:
                        a_content, _ = extract_braced_content(content, brace_start)
                        if a_content:
                            config['lan']['a_records'] = _parse_a_records(a_content)
                
                # Find cname_records = within dns
                cname_records_start = content.find('cname_records =', lan_dns_start)
                if cname_records_start != -1:
                    brace_start = content.find('{', cname_records_start)
                    if brace_start != -1:
                        cname_content, _ = extract_braced_content(content, brace_start)
                        if cname_content:
                            config['lan']['cname_records'] = _parse_cname_records(cname_content)
        
        logger.info(f"Parsed DNS config: homelab={len(config['homelab']['a_records'])} A, {len(config['homelab']['cname_records'])} CNAME; "
                   f"lan={len(config['lan']['a_records'])} A, {len(config['lan']['cname_records'])} CNAME")
        
    except Exception as e:
        logger.error(f"Error parsing router-config.nix: {type(e).__name__}: {str(e)}", exc_info=True)
        return {}
    
    return config


def _parse_a_records(content: str) -> Dict[str, Dict[str, str]]:
    """Parse A records from Nix config content
    
    Args:
        content: Content between a_records = { ... }
        
    Returns:
        Dictionary mapping hostname -> {ip, comment}
    """
    records = {}
    # Match multiline format:
    # "hostname" = {
    #   ip = "192.168.1.1";
    #   comment = "description";
    # };
    # Also handles single-line format and records without comments
    pattern = r'"([^"]+)"\s*=\s*\{[^}]*ip\s*=\s*"([^"]+)";[^}]*(?:comment\s*=\s*"([^"]*)";)?[^}]*\}'
    
    for match in re.finditer(pattern, content, re.DOTALL):
        hostname = match.group(1)
        ip = match.group(2)
        comment = match.group(3) if match.group(3) else None
        records[hostname] = {'ip': ip, 'comment': comment}
    
    return records


def _parse_cname_records(content: str) -> Dict[str, Dict[str, str]]:
    """Parse CNAME records from Nix config content
    
    Args:
        content: Content between cname_records = { ... }
        
    Returns:
        Dictionary mapping hostname -> {target, comment}
    """
    records = {}
    # Match multiline format:
    # "hostname" = {
    #   target = "target.hostname";
    #   comment = "description";
    # };
    # Also handles single-line format and records without comments
    pattern = r'"([^"]+)"\s*=\s*\{[^}]*target\s*=\s*"([^"]+)";[^}]*(?:comment\s*=\s*"([^"]*)";)?[^}]*\}'
    
    for match in re.finditer(pattern, content, re.DOTALL):
        hostname = match.group(1)
        target = match.group(2)
        comment = match.group(3) if match.group(3) else None
        records[hostname] = {'target': target, 'comment': comment}
    
    return records


async def migrate_dns_config_to_database(session) -> None:
    """Migrate DNS configuration from router-config.nix to database
    
    Reads DNS zones and records from router-config.nix and adds them to the database
    if they don't already exist (checked by original_config_path).
    
    Args:
        session: Async database session
    """
    logger.info("Starting migration of DNS configuration from router-config.nix to database")
    
    config = parse_nix_config()
    if not config:
        logger.info("No DNS configuration found in router-config.nix, skipping migration")
        return
    
    migrated_zones = 0
    skipped_zones = 0
    migrated_records = 0
    skipped_records = 0
    
    try:
        for network in ['homelab', 'lan']:
            network_config = config.get(network, {})
            a_records = network_config.get('a_records', {})
            cname_records = network_config.get('cname_records', {})
            
            if not a_records and not cname_records:
                continue
            
            # Extract unique base domains (zones) from all records
            zones = set()
            for hostname in list(a_records.keys()) + list(cname_records.keys()):
                base_domain = extract_base_domain(hostname)
                zones.add(base_domain)
            
            # Create or get zones
            zone_map = {}  # base_domain -> zone_id
            for base_domain in zones:
                original_config_path = f"{network}.dns"
                
                # Check if zone already exists
                result = await session.execute(
                    select(DnsZoneDB).where(
                        DnsZoneDB.name == base_domain,
                        DnsZoneDB.network == network,
                        DnsZoneDB.original_config_path == original_config_path
                    )
                )
                existing_zone = result.scalar_one_or_none()
                
                if existing_zone:
                    logger.debug(f"Zone {base_domain} ({network}) already exists, skipping")
                    skipped_zones += 1
                    zone_map[base_domain] = existing_zone.id
                else:
                    # Create new zone
                    zone = DnsZoneDB(
                        name=base_domain,
                        network=network,
                        authoritative=True,  # Default to authoritative
                        enabled=True,
                        original_config_path=original_config_path
                    )
                    session.add(zone)
                    await session.flush()  # Get the ID
                    zone_map[base_domain] = zone.id
                    migrated_zones += 1
                    logger.info(f"Created zone: {base_domain} ({network})")
            
            # Create A records
            for hostname, record_data in a_records.items():
                base_domain = extract_base_domain(hostname)
                zone_id = zone_map.get(base_domain)
                
                if not zone_id:
                    logger.warning(f"No zone found for {hostname}, skipping")
                    continue
                
                original_config_path = f"{network}.dns.a_records.{hostname}"
                
                # Check if record already exists
                result = await session.execute(
                    select(DnsRecordDB).where(
                        DnsRecordDB.zone_id == zone_id,
                        DnsRecordDB.name == hostname,
                        DnsRecordDB.type == 'A',
                        DnsRecordDB.original_config_path == original_config_path
                    )
                )
                existing_record = result.scalar_one_or_none()
                
                if existing_record:
                    logger.debug(f"Record {hostname} (A) already exists, skipping")
                    skipped_records += 1
                    continue
                
                # Create new A record
                dns_record = DnsRecordDB(
                    zone_id=zone_id,
                    name=hostname,
                    type='A',
                    value=record_data['ip'],
                    comment=record_data.get('comment'),
                    enabled=True,
                    original_config_path=original_config_path
                )
                session.add(dns_record)
                migrated_records += 1
                logger.info(f"Created A record: {hostname} -> {record_data['ip']}")
            
            # Create CNAME records
            for hostname, record_data in cname_records.items():
                base_domain = extract_base_domain(hostname)
                zone_id = zone_map.get(base_domain)
                
                if not zone_id:
                    logger.warning(f"No zone found for {hostname}, skipping")
                    continue
                
                original_config_path = f"{network}.dns.cname_records.{hostname}"
                
                # Check if record already exists
                result = await session.execute(
                    select(DnsRecordDB).where(
                        DnsRecordDB.zone_id == zone_id,
                        DnsRecordDB.name == hostname,
                        DnsRecordDB.type == 'CNAME',
                        DnsRecordDB.original_config_path == original_config_path
                    )
                )
                existing_record = result.scalar_one_or_none()
                
                if existing_record:
                    logger.debug(f"Record {hostname} (CNAME) already exists, skipping")
                    skipped_records += 1
                    continue
                
                # Create new CNAME record
                dns_record = DnsRecordDB(
                    zone_id=zone_id,
                    name=hostname,
                    type='CNAME',
                    value=record_data['target'],
                    comment=record_data.get('comment'),
                    enabled=True,
                    original_config_path=original_config_path
                )
                session.add(dns_record)
                migrated_records += 1
                logger.info(f"Created CNAME record: {hostname} -> {record_data['target']}")
        
        await session.commit()
        logger.info(f"DNS migration complete: {migrated_zones} zones, {migrated_records} records migrated; "
                   f"{skipped_zones} zones, {skipped_records} records skipped")
        
    except Exception as e:
        logger.error(f"Error during DNS migration: {type(e).__name__}: {str(e)}", exc_info=True)
        await session.rollback()
        raise

