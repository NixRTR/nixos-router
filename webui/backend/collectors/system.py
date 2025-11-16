"""
System metrics collector using psutil
"""
import psutil
from datetime import datetime
from typing import List, Dict, Optional
from ..models import (
    SystemMetrics, DiskIOMetrics, DiskSpaceMetrics,
    TemperatureMetrics, FanMetrics
)


def get_cpu_usage() -> float:
    """Get current CPU usage percentage"""
    return psutil.cpu_percent(interval=0.1)


def get_memory_stats() -> tuple[float, int, int]:
    """Get memory statistics
    
    Returns:
        tuple: (percent, used_mb, total_mb)
    """
    mem = psutil.virtual_memory()
    return (
        mem.percent,
        mem.used // (1024 * 1024),
        mem.total // (1024 * 1024)
    )


def get_load_average() -> tuple[float, float, float]:
    """Get system load average
    
    Returns:
        tuple: (1min, 5min, 15min)
    """
    try:
        # Unix-like systems
        return psutil.getloadavg()
    except AttributeError:
        # Windows doesn't have load average, return CPU times instead
        cpu_count = psutil.cpu_count()
        cpu_percent = psutil.cpu_percent(interval=0.1) / 100.0
        load = cpu_percent * cpu_count
        return (load, load, load)


def get_uptime() -> int:
    """Get system uptime in seconds"""
    boot_time = psutil.boot_time()
    return int(datetime.now().timestamp() - boot_time)


def collect_system_metrics() -> SystemMetrics:
    """Collect all system metrics
    
    Returns:
        SystemMetrics: Current system metrics
    """
    cpu = get_cpu_usage()
    mem_percent, mem_used, mem_total = get_memory_stats()
    load_1, load_5, load_15 = get_load_average()
    uptime = get_uptime()
    
    return SystemMetrics(
        timestamp=datetime.now(),
        cpu_percent=cpu,
        memory_percent=mem_percent,
        memory_used_mb=mem_used,
        memory_total_mb=mem_total,
        load_avg_1m=load_1,
        load_avg_5m=load_5,
        load_avg_15m=load_15,
        uptime_seconds=uptime
    )


# Track previous disk I/O stats for rate calculation
_prev_disk_io: Dict[str, tuple[int, int, int, int, float]] = {}


def collect_disk_io() -> List[DiskIOMetrics]:
    """Collect disk I/O statistics for all physical devices
    
    Returns:
        List[DiskIOMetrics]: Disk I/O stats for each device
    """
    global _prev_disk_io
    
    now = datetime.now()
    current_time = now.timestamp()
    results = []
    
    try:
        disk_io = psutil.disk_io_counters(perdisk=True)
        
        for device, stats in disk_io.items():
            # Skip loop devices, partitions, and virtual devices
            if device.startswith(('loop', 'ram', 'dm-', 'sr')):
                continue
                
            read_bytes = stats.read_bytes
            write_bytes = stats.write_bytes
            read_count = stats.read_count
            write_count = stats.write_count
            
            # Calculate rates if we have previous data
            if device in _prev_disk_io:
                prev_read, prev_write, prev_read_ops, prev_write_ops, prev_time = _prev_disk_io[device]
                time_delta = current_time - prev_time
                
                if time_delta > 0:
                    read_rate = (read_bytes - prev_read) / time_delta
                    write_rate = (write_bytes - prev_write) / time_delta
                    read_ops_rate = (read_count - prev_read_ops) / time_delta
                    write_ops_rate = (write_count - prev_write_ops) / time_delta
                    
                    results.append(DiskIOMetrics(
                        timestamp=now,
                        device=device,
                        read_bytes_per_sec=max(0, read_rate),
                        write_bytes_per_sec=max(0, write_rate),
                        read_ops_per_sec=max(0, read_ops_rate),
                        write_ops_per_sec=max(0, write_ops_rate)
                    ))
            
            # Store current values for next iteration
            _prev_disk_io[device] = (read_bytes, write_bytes, read_count, write_count, current_time)
    
    except Exception as e:
        print(f"Error collecting disk I/O: {e}")
    
    return results


def collect_disk_space() -> List[DiskSpaceMetrics]:
    """Collect disk space usage for all mounted filesystems
    
    Returns:
        List[DiskSpaceMetrics]: Disk space stats for each filesystem
    """
    results = []
    now = datetime.now()
    
    try:
        partitions = psutil.disk_partitions(all=False)
        
        for partition in partitions:
            # Skip virtual filesystems
            if partition.fstype in ('tmpfs', 'devtmpfs', 'squashfs', 'overlay', 'proc', 'sysfs', 'devfs'):
                continue
            
            try:
                usage = psutil.disk_usage(partition.mountpoint)
                
                results.append(DiskSpaceMetrics(
                    timestamp=now,
                    mountpoint=partition.mountpoint,
                    device=partition.device,
                    total_gb=usage.total / (1024 ** 3),
                    used_gb=usage.used / (1024 ** 3),
                    free_gb=usage.free / (1024 ** 3),
                    percent_used=usage.percent
                ))
            except PermissionError:
                # Skip mountpoints we can't access
                continue
            except Exception as e:
                print(f"Error reading disk usage for {partition.mountpoint}: {e}")
                continue
    
    except Exception as e:
        print(f"Error collecting disk space: {e}")
    
    return results


def collect_temperatures() -> List[TemperatureMetrics]:
    """Collect temperature sensor readings
    
    Returns:
        List[TemperatureMetrics]: Temperature readings for all sensors
    """
    results = []
    now = datetime.now()
    
    try:
        temps = psutil.sensors_temperatures()
        
        for sensor_name, entries in temps.items():
            for entry in entries:
                results.append(TemperatureMetrics(
                    timestamp=now,
                    sensor_name=sensor_name,
                    temperature_c=entry.current,
                    label=entry.label if entry.label else None,
                    critical=entry.critical if hasattr(entry, 'critical') else None
                ))
    except AttributeError:
        # sensors_temperatures not available on this platform
        pass
    except Exception as e:
        print(f"Error collecting temperatures: {e}")
    
    return results


def collect_fan_speeds() -> List[FanMetrics]:
    """Collect fan speed readings
    
    Returns:
        List[FanMetrics]: Fan speed readings for all fans
    """
    results = []
    now = datetime.now()
    
    try:
        fans = psutil.sensors_fans()
        
        for fan_name, entries in fans.items():
            for entry in entries:
                results.append(FanMetrics(
                    timestamp=now,
                    fan_name=fan_name,
                    rpm=entry.current,
                    label=entry.label if entry.label else None
                ))
    except AttributeError:
        # sensors_fans not available on this platform
        pass
    except Exception as e:
        print(f"Error collecting fan speeds: {e}")
    
    return results

