"""
DNS (Unbound) statistics collector
"""
import subprocess
from datetime import datetime
from typing import List, Optional
from ..models import DNSMetrics


def get_unbound_stats(instance: str) -> Optional[DNSMetrics]:
    """Get statistics from Unbound control socket
    
    Args:
        instance: 'homelab' or 'lan'
        
    Returns:
        DNSMetrics or None if stats unavailable
    """
    try:
        # Run unbound-control stats command
        # Note: Socket path needs to be adjusted per instance
        control_socket = f"/run/unbound-{instance}/control"
        
        # Try to find unbound-control in common paths
        unbound_control_paths = [
            '/run/current-system/sw/bin/unbound-control',
            '/usr/bin/unbound-control',
            '/usr/local/bin/unbound-control',
            'unbound-control'  # Fallback to PATH
        ]
        
        unbound_control = None
        for path in unbound_control_paths:
            try:
                # Check if command exists
                test = subprocess.run(
                    [path, '-h'],
                    capture_output=True,
                    timeout=1
                )
                unbound_control = path
                break
            except (FileNotFoundError, subprocess.TimeoutExpired):
                continue
        
        if not unbound_control:
            return None  # unbound-control not available
        
        result = subprocess.run(
            [unbound_control, '-s', control_socket, 'stats_noreset'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return None
        
        # Parse stats output
        stats = {}
        for line in result.stdout.split('\n'):
            if '=' in line:
                key, value = line.split('=', 1)
                stats[key.strip()] = value.strip()
        
        # Extract relevant metrics
        total_queries = int(stats.get('total.num.queries', 0))
        cache_hits = int(stats.get('total.num.cachehits', 0))
        cache_misses = int(stats.get('total.num.cachemiss', 0))
        
        # Blocked queries (from blocklist)
        # This is an estimate - Unbound doesn't directly track this
        blocked = int(stats.get('total.num.blocked', 0))
        
        # Calculate derived metrics
        queries_per_second = float(stats.get('total.requestlist.avg', 0))
        
        cache_hit_rate = 0.0
        if total_queries > 0:
            cache_hit_rate = (cache_hits / total_queries) * 100
        
        return DNSMetrics(
            timestamp=datetime.now(),
            instance=instance,
            total_queries=total_queries,
            cache_hits=cache_hits,
            cache_misses=cache_misses,
            blocked_queries=blocked,
            queries_per_second=queries_per_second,
            cache_hit_rate=cache_hit_rate
        )
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError, KeyError):
        return None


def collect_dns_stats() -> List[DNSMetrics]:
    """Collect DNS statistics for all instances
    
    Returns:
        List[DNSMetrics]: Stats for homelab and lan instances
    """
    stats_list = []
    
    for instance in ['homelab', 'lan']:
        stats = get_unbound_stats(instance)
        if stats:
            stats_list.append(stats)
    
    return stats_list

