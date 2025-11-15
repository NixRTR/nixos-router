"""
Basic tests for data collectors
"""
import pytest
from collectors.system import collect_system_metrics, get_cpu_usage, get_memory_stats
from collectors.network import collect_interface_stats


def test_system_metrics_collection():
    """Test system metrics collection"""
    metrics = collect_system_metrics()
    
    assert metrics.cpu_percent >= 0
    assert metrics.cpu_percent <= 100
    assert metrics.memory_percent >= 0
    assert metrics.memory_percent <= 100
    assert metrics.uptime_seconds > 0


def test_cpu_usage():
    """Test CPU usage collection"""
    cpu = get_cpu_usage()
    assert 0 <= cpu <= 100


def test_memory_stats():
    """Test memory statistics"""
    percent, used, total = get_memory_stats()
    assert 0 <= percent <= 100
    assert used > 0
    assert total > used


def test_interface_stats_collection():
    """Test network interface statistics"""
    stats = collect_interface_stats()
    
    assert isinstance(stats, list)
    assert len(stats) > 0
    
    for iface_stat in stats:
        assert iface_stat.rx_bytes >= 0
        assert iface_stat.tx_bytes >= 0
        assert len(iface_stat.interface) > 0

