"""
CAKE traffic shaping statistics collector
"""
import subprocess
import re
import json
import os
from datetime import datetime, timezone
from typing import Optional, Dict
from ..models import CakeStats, CakeTrafficClass
from ..utils.cake import get_wan_interface, is_cake_enabled


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
        # When using autorate-ingress, CAKE reports "capacity estimate: XXXbit" which is the detected bandwidth
        # Prefer capacity estimate (detected) over configured bandwidth
        
        # First, try to find the capacity estimate (detected bandwidth with autorate-ingress)
        capacity_match = re.search(r'capacity\s+estimate:\s+([\d.]+)([KMGT]?)bit', output, re.IGNORECASE)
        if capacity_match:
            rate_value = float(capacity_match.group(1))
            rate_unit = capacity_match.group(2).upper() if capacity_match.group(2) else ''
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
        else:
            # Fall back to configured bandwidth if capacity estimate not found
            first_line_match = re.search(r'bandwidth\s+([\d.]+)([KMGT]?)bit', output, re.IGNORECASE)
            if first_line_match:
                rate_value = float(first_line_match.group(1))
                rate_unit = first_line_match.group(2).upper() if first_line_match.group(2) else ''
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
        
        # Parse target and interval from table format
        # These are in the table rows: "  target          334ms       20.9ms       41.8ms       83.6ms"
        target_match = re.search(r'target\s+([\d.]+)ms', output, re.IGNORECASE)
        if target_match:
            target_ms = float(target_match.group(1))
        
        interval_match = re.search(r'interval\s+([\d.]+)ms', output, re.IGNORECASE)
        if interval_match:
            interval_ms = float(interval_match.group(1))
        
        # Parse traffic class statistics from table format
        # CAKE uses a table with columns: Bulk | Best Effort | Video | Voice
        # Example:
        #                   Bulk  Best Effort        Video        Voice
        #   pk_delay       4.42ms       15.4ms          2us       46.4ms
        #   av_delay         76us       3.53ms          0us       8.93ms
        #   sp_delay          9us          6us          0us        337us
        #   pkts               16       585580            3         3654
        #   bytes             640    131174092          188      1089043
        #   drops               0         3110            0            0
        #   marks               0            0            0            0
        
        # Find the table section (after the header row)
        table_start = re.search(r'(?:Bulk|bulk)\s+(?:Best\s+Effort|best.*effort)\s+(?:Video|video)\s+(?:Voice|voice)', output, re.IGNORECASE)
        if table_start:
            # Extract table content starting from after the header
            table_content = output[table_start.end():]
            
            # Helper function to parse a table row and extract column values
            def parse_table_row(row_name: str, content: str) -> list:
                """Parse a table row and return list of 4 values (one per traffic class)"""
                # Match row name followed by values (until next row or end)
                # Pattern: row_name followed by whitespace, then values until newline with next row start
                pattern = rf'{row_name}\s+([^\n]+)'
                match = re.search(pattern, content, re.IGNORECASE)
                if not match:
                    return [None, None, None, None]
                
                row_text = match.group(1).strip()
                # Extract values - they can be numbers with units (ms, us, bit, b) or just numbers
                # Pattern: number, optional decimal, optional unit
                values = []
                # Extract all numbers (with or without units) from the row
                # This regex finds numbers that might have units or are standalone
                parts = re.findall(r'([\d.]+)\s*(ms|us|ns|bit|b|pkt)?', row_text)
                
                for val_str, unit in parts[:4]:  # Take first 4 columns
                    try:
                        val = float(val_str)
                        # Store value and unit (even if unit is empty string)
                        values.append((val, unit.lower() if unit else ''))
                    except ValueError:
                        values.append((None, ''))
                
                # Pad if needed
                while len(values) < 4:
                    values.append((None, ''))
                
                return values[:4]
            
            # Helper to convert delay values to milliseconds
            def convert_to_ms(value: float, unit: str) -> Optional[float]:
                """Convert delay value to milliseconds"""
                if value is None:
                    return None
                unit_lower = unit.lower()
                if unit_lower == 'us':
                    return value / 1000.0
                elif unit_lower == 'ns':
                    return value / 1000000.0
                elif unit_lower == 'ms' or unit_lower == '':
                    return value
                else:
                    return value  # Default to assuming ms
            
            # Parse delay rows
            pk_delay_row = parse_table_row('pk_delay', table_content)
            av_delay_row = parse_table_row('av_delay', table_content)
            sp_delay_row = parse_table_row('sp_delay', table_content)
            
            # Parse packet/byte/drop rows
            pkts_row = parse_table_row('pkts', table_content)
            bytes_row = parse_table_row('bytes', table_content)
            drops_row = parse_table_row('drops', table_content)
            marks_row = parse_table_row('marks', table_content)
            
            # Map columns to class labels: [Bulk, Best Effort, Video, Voice]
            class_labels = ['bulk', 'best-effort', 'video', 'voice']
            
            for i, class_label in enumerate(class_labels):
                # Get values for this column (index i)
                pk_delay_val, pk_delay_unit = pk_delay_row[i] if i < len(pk_delay_row) else (None, '')
                av_delay_val, av_delay_unit = av_delay_row[i] if i < len(av_delay_row) else (None, '')
                sp_delay_val, sp_delay_unit = sp_delay_row[i] if i < len(sp_delay_row) else (None, '')
                
                # Convert delays to milliseconds
                pk_delay = convert_to_ms(pk_delay_val, pk_delay_unit) if pk_delay_val is not None else None
                av_delay = convert_to_ms(av_delay_val, av_delay_unit) if av_delay_val is not None else None
                sp_delay = convert_to_ms(sp_delay_val, sp_delay_unit) if sp_delay_val is not None else None
                
                # Get packet/byte/drop/mark values (integers, no unit conversion needed)
                pkts_val, _ = pkts_row[i] if i < len(pkts_row) else (None, '')
                bytes_val, bytes_unit = bytes_row[i] if i < len(bytes_row) else (None, '')
                drops_val, _ = drops_row[i] if i < len(drops_row) else (None, '')
                marks_val, _ = marks_row[i] if i < len(marks_row) else (None, '')
                
                # Convert bytes (handle bit/b unit)
                bytes_int = None
                if bytes_val is not None:
                    if bytes_unit == 'bit':
                        bytes_int = int(bytes_val / 8)  # Convert bits to bytes
                    else:
                        bytes_int = int(bytes_val)
                
                pkts = int(pkts_val) if pkts_val is not None else None
                drops = int(drops_val) if drops_val is not None else None
                marks = int(marks_val) if marks_val is not None else None
                
                # Only create class entry if we have at least some data
                if pkts is not None or bytes_int is not None or drops is not None or pk_delay is not None:
                    classes[class_label] = CakeTrafficClass(
                        pk_delay_ms=pk_delay,
                        av_delay_ms=av_delay,
                        sp_delay_ms=sp_delay,
                        bytes=bytes_int,
                        packets=pkts,
                        drops=drops,
                        marks=marks
                    )
            
            # Parse hash statistics from table
            way_inds_row = parse_table_row('way_inds', table_content)
            way_miss_row = parse_table_row('way_miss', table_content)
            way_cols_row = parse_table_row('way_cols', table_content)
            
            # Sum hash stats across all classes (0 is valid, so include all values)
            # Check if row was found (not all None) before processing
            if way_inds_row and any(val is not None for val, _ in way_inds_row):
                way_inds_sum = sum(int(val) if val is not None else 0 for val, _ in way_inds_row)
                way_inds = way_inds_sum
            elif way_inds_row and not any(val is not None for val, _ in way_inds_row):
                # Row exists but all values are None - this shouldn't happen, but handle it
                way_inds = 0
            
            if way_miss_row and any(val is not None for val, _ in way_miss_row):
                way_miss_sum = sum(int(val) if val is not None else 0 for val, _ in way_miss_row)
                way_miss = way_miss_sum
            elif way_miss_row and not any(val is not None for val, _ in way_miss_row):
                way_miss = 0
            
            if way_cols_row and any(val is not None for val, _ in way_cols_row):
                way_cols_sum = sum(int(val) if val is not None else 0 for val, _ in way_cols_row)
                way_cols = way_cols_sum  # 0 is valid, store it
            elif way_cols_row and not any(val is not None for val, _ in way_cols_row):
                way_cols = 0
        
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
        import traceback
        traceback.print_exc()
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
        # Get tc binary path (from environment variable if set)
        tc_bin = os.environ.get("TC_BIN", "tc")
        
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
        import traceback
        traceback.print_exc()
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
