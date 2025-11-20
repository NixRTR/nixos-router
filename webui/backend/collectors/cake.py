"""
CAKE traffic shaping statistics collector
"""
import subprocess
import re
import json
import os
import shutil
from datetime import datetime, timezone
from typing import Optional, Dict
from ..models import CakeStats, CakeTrafficClass
from ..utils.cake import get_wan_interface, is_cake_enabled


def find_tc_binary() -> Optional[str]:
    """Find tc binary path - Nix way (check env var, then PATH, then common locations)
    
    Returns:
        Path to tc binary or None if not found
    """
    # Check environment variable first
    env_path = os.environ.get("TC_BIN")
    if env_path and os.path.isfile(env_path):
        return env_path
    
    # Try to find in PATH
    tc_path = shutil.which("tc")
    if tc_path:
        return tc_path
    
    # Check common Nix store locations
    # In NixOS, iproute2 is typically in /run/current-system/sw/bin or /nix/store/.../bin
    candidates = [
        "/run/current-system/sw/bin/tc",
        "/run/wrappers/bin/tc",
        "/usr/bin/tc",
        "/bin/tc",
    ]
    
    # Also check if we're in a nix-shell environment
    nix_profile = os.environ.get("NIX_PROFILES", "")
    for profile in nix_profile.split():
        candidates.append(f"{profile}/bin/tc")
    
    for path in candidates:
        if os.path.isfile(path):
            return path
    
    return None


def parse_tc_cake_output(output: str, interface: str) -> Optional[CakeStats]:
    """Parse tc -s qdisc show dev <interface> root cake output
    
    Args:
        output: Output from tc -s qdisc show command
        interface: Interface name
        
    Returns:
        CakeStats object or None if parsing fails
    """
    try:
        # Initialize stats
        rate_mbps = None
        target_ms = None
        interval_ms = None
        classes: Dict[str, CakeTrafficClass] = {}
        way_inds = None
        way_miss = None
        way_cols = None
        
        # Parse overall stats from first line
        # Example: qdisc cake 8001: root refcnt 2 bandwidth 200Mbit diffserv4 nat wash ...
        first_line_match = re.search(r'bandwidth\s+([\d.]+)([KMGT]?)bit', output, re.IGNORECASE)
        if first_line_match:
            rate_value = float(first_line_match.group(1))
            rate_unit = first_line_match.group(2).upper()
            # Convert to Mbps
            if rate_unit == 'K':
                rate_mbps = rate_value / 1000
            elif rate_unit == 'M':
                rate_mbps = rate_value
            elif rate_unit == 'G':
                rate_mbps = rate_value * 1000
            elif rate_unit == 'T':
                rate_mbps = rate_value * 1000000
            else:
                rate_mbps = rate_value / 1000000  # Assume bits if no unit
        
        # Parse target and interval
        target_match = re.search(r'target\s+([\d.]+)ms', output, re.IGNORECASE)
        if target_match:
            target_ms = float(target_match.group(1))
        
        interval_match = re.search(r'interval\s+([\d.]+)ms', output, re.IGNORECASE)
        if interval_match:
            interval_ms = float(interval_match.group(1))
        
        # Parse traffic class statistics
        # CAKE has 4 traffic classes: Bulk, Best Effort, Video, Voice
        # Example format:
        #   0: Bulk          pkts: 12345  bytes: 12345678  drops: 0  marks: 0
        #      pkts: 12345  bytes: 12345678  delays: 1.2ms avg, 2.3ms peak, 0.5ms sparse
        class_names = ['bulk', 'best.*effort', 'video', 'voice']
        class_labels = ['bulk', 'best-effort', 'video', 'voice']
        
        for class_name, class_label in zip(class_names, class_labels):
            # Find class section
            class_pattern = rf'(\d+):\s*{class_name}[^\n]*\n(.*?)(?=\n\s*\d+:|$)'
            class_match = re.search(class_pattern, output, re.IGNORECASE | re.DOTALL)
            
            if class_match:
                class_content = class_match.group(2)
                
                # Parse packet and byte counts
                pkts_match = re.search(r'pkts:\s*(\d+)', class_content, re.IGNORECASE)
                bytes_match = re.search(r'bytes:\s*(\d+)', class_content, re.IGNORECASE)
                drops_match = re.search(r'drops:\s*(\d+)', class_content, re.IGNORECASE)
                marks_match = re.search(r'marks:\s*(\d+)', class_content, re.IGNORECASE)
                
                # Parse delays
                pk_delay_match = re.search(r'peak[,\s]+([\d.]+)ms', class_content, re.IGNORECASE)
                av_delay_match = re.search(r'avg[,\s]+([\d.]+)ms', class_content, re.IGNORECASE)
                sp_delay_match = re.search(r'sparse[,\s]+([\d.]+)ms', class_content, re.IGNORECASE)
                
                # Alternative delay format: delays: X.Xms avg, Y.Yms peak, Z.Zms sparse
                delays_match = re.search(
                    r'delays:\s*([\d.]+)ms\s+avg[,\s]+([\d.]+)ms\s+peak[,\s]+([\d.]+)ms\s+sparse',
                    class_content,
                    re.IGNORECASE
                )
                
                pkts = int(pkts_match.group(1)) if pkts_match else None
                bytes_val = int(bytes_match.group(1)) if bytes_match else None
                drops = int(drops_match.group(1)) if drops_match else None
                marks = int(marks_match.group(1)) if marks_match else None
                
                if delays_match:
                    av_delay = float(delays_match.group(1))
                    pk_delay = float(delays_match.group(2))
                    sp_delay = float(delays_match.group(3))
                else:
                    pk_delay = float(pk_delay_match.group(1)) if pk_delay_match else None
                    av_delay = float(av_delay_match.group(1)) if av_delay_match else None
                    sp_delay = float(sp_delay_match.group(1)) if sp_delay_match else None
                
                classes[class_label] = CakeTrafficClass(
                    pk_delay_ms=pk_delay,
                    av_delay_ms=av_delay,
                    sp_delay_ms=sp_delay,
                    bytes=bytes_val,
                    packets=pkts,
                    drops=drops,
                    marks=marks
                )
        
        # Parse hash statistics
        way_inds_match = re.search(r'way_inds\s*=\s*(\d+)', output, re.IGNORECASE)
        if way_inds_match:
            way_inds = int(way_inds_match.group(1))
        
        way_miss_match = re.search(r'way_miss\s*=\s*(\d+)', output, re.IGNORECASE)
        if way_miss_match:
            way_miss = int(way_miss_match.group(1))
        
        way_cols_match = re.search(r'way_cols\s*=\s*(\d+)', output, re.IGNORECASE)
        if way_cols_match:
            way_cols = int(way_cols_match.group(1))
        
        return CakeStats(
            timestamp=datetime.now(timezone.utc),
            interface=interface,
            rate_mbps=rate_mbps,
            target_ms=target_ms,
            interval_ms=interval_ms,
            classes=classes,
            way_inds=way_inds,
            way_miss=way_miss,
            way_cols=way_cols
        )
    except Exception as e:
        print(f"Error parsing CAKE statistics: {e}")
        return None


def collect_cake_stats(interface: Optional[str] = None) -> Optional[CakeStats]:
    """Collect CAKE statistics from tc command
    
    Args:
        interface: Interface name (defaults to WAN interface)
        
    Returns:
        CakeStats object or None if CAKE is not configured or collection fails
    """
    # Check if CAKE is enabled
    enabled, wan_interface = is_cake_enabled()
    if not enabled:
        return None
    
    # Use provided interface or WAN interface
    if interface is None:
        interface = wan_interface
    
    if interface is None:
        return None
    
    try:
        # Find tc binary
        tc_bin = find_tc_binary()
        if tc_bin is None:
            # tc not found, skip collection silently
            return None
        
        # Run tc command to get CAKE statistics
        result = subprocess.run(
            [tc_bin, '-s', 'qdisc', 'show', 'dev', interface, 'root'],
            capture_output=True,
            text=True,
            timeout=5,
            check=False
        )
        
        if result.returncode != 0:
            # CAKE might not be configured
            return None
        
        output = result.stdout
        
        # Check if CAKE qdisc exists
        if 'cake' not in output.lower():
            return None
        
        # Parse output
        return parse_tc_cake_output(output, interface)
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError) as e:
        print(f"Error collecting CAKE statistics: {e}")
        return None
    except Exception as e:
        print(f"Unexpected error collecting CAKE statistics: {e}")
        return None


def cake_stats_to_dict(cake_stats: CakeStats) -> Dict:
    """Convert CakeStats to dictionary suitable for JSONB storage
    
    Args:
        cake_stats: CakeStats object
        
    Returns:
        Dictionary representation
    """
    return {
        'timestamp': cake_stats.timestamp.isoformat(),
        'interface': cake_stats.interface,
        'rate_mbps': cake_stats.rate_mbps,
        'target_ms': cake_stats.target_ms,
        'interval_ms': cake_stats.interval_ms,
        'classes': {
            class_name: {
                'pk_delay_ms': class_stats.pk_delay_ms,
                'av_delay_ms': class_stats.av_delay_ms,
                'sp_delay_ms': class_stats.sp_delay_ms,
                'bytes': class_stats.bytes,
                'packets': class_stats.packets,
                'drops': class_stats.drops,
                'marks': class_stats.marks,
            }
            for class_name, class_stats in cake_stats.classes.items()
        },
        'way_inds': cake_stats.way_inds,
        'way_miss': cake_stats.way_miss,
        'way_cols': cake_stats.way_cols,
    }

