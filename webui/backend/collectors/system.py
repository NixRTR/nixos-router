"""
System metrics collector using psutil
"""
import psutil
from datetime import datetime
from ..models import SystemMetrics


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

