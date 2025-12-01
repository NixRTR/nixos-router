"""
Redis write buffer flush worker
Reads metrics from Redis buffers and writes them to PostgreSQL in batches
"""
import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, List, Any
from sqlalchemy import insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import AsyncSessionLocal, (
    SystemMetricsDB, InterfaceStatsDB, ServiceStatusDB,
    DiskIOMetricsDB, TemperatureMetricsDB,
    ClientBandwidthStatsDB, ClientConnectionStatsDB, DHCPLeaseDB
)
from ..utils.redis_client import (
    list_length, list_pop, is_redis_available
)
from ..config import settings

logger = logging.getLogger(__name__)


class RedisBufferFlusher:
    """Flushes metrics from Redis buffers to PostgreSQL"""
    
    def __init__(self):
        self.running = False
        self._task: asyncio.Task = None
    
    async def start(self):
        """Start the buffer flush worker"""
        if self.running:
            return
        
        self.running = True
        self._task = asyncio.create_task(self._flush_loop())
        logger.info("Redis buffer flush worker started")
    
    async def stop(self):
        """Stop the buffer flush worker"""
        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("Redis buffer flush worker stopped")
    
    async def _flush_loop(self):
        """Main flush loop - runs periodically"""
        while self.running:
            try:
                if not is_redis_available():
                    await asyncio.sleep(settings.redis_buffer_flush_interval)
                    continue
                
                # Flush all buffers
                await self._flush_all_buffers()
                
                # Wait for next flush interval
                await asyncio.sleep(settings.redis_buffer_flush_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in buffer flush loop: {e}", exc_info=True)
                await asyncio.sleep(settings.redis_buffer_flush_interval)
    
    async def _flush_all_buffers(self):
        """Flush all metric buffers to PostgreSQL"""
        buffers = [
            ("metrics:buffer:system", SystemMetricsDB),
            ("metrics:buffer:interfaces", InterfaceStatsDB),
            ("metrics:buffer:services", ServiceStatusDB),
            ("metrics:buffer:disk_io", DiskIOMetricsDB),
            ("metrics:buffer:temperatures", TemperatureMetricsDB),
            ("metrics:buffer:bandwidth", ClientBandwidthStatsDB),
            ("metrics:buffer:connections", ClientConnectionStatsDB),
            ("metrics:buffer:dhcp_leases", DHCPLeaseDB),
        ]
        
        for buffer_key, model_class in buffers:
            try:
                buffer_size = await list_length(buffer_key)
                if buffer_size == 0:
                    continue
                
                # Flush up to max_size items at a time
                items_to_flush = min(buffer_size, settings.redis_buffer_max_size)
                if items_to_flush > 0:
                    await self._flush_buffer(buffer_key, model_class, items_to_flush)
            except Exception as e:
                logger.error(f"Error flushing buffer {buffer_key}: {e}", exc_info=True)
    
    async def _flush_buffer(self, buffer_key: str, model_class: Any, count: int):
        """Flush a specific buffer to PostgreSQL"""
        # Pop items from Redis list
        items_json = await list_pop(buffer_key, count)
        
        if not items_json:
            return
        
        # Parse JSON items
        items = []
        for item_json in items_json:
            try:
                item = json.loads(item_json)
                items.append(item)
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse buffer item from {buffer_key}: {e}")
                continue
        
        if not items:
            return
        
        # Write to PostgreSQL using bulk insert
        async with AsyncSessionLocal() as session:
            try:
                await session.execute(
                    insert(model_class).values(items)
                )
                await session.commit()
                logger.debug(f"Flushed {len(items)} items from {buffer_key} to PostgreSQL")
            except Exception as e:
                logger.error(f"Failed to flush buffer {buffer_key} to PostgreSQL: {e}", exc_info=True)
                await session.rollback()


# Global buffer flusher instance
_buffer_flusher: RedisBufferFlusher = None


async def start_buffer_flusher():
    """Start the Redis buffer flush worker"""
    global _buffer_flusher
    if _buffer_flusher is None:
        _buffer_flusher = RedisBufferFlusher()
    await _buffer_flusher.start()


async def stop_buffer_flusher():
    """Stop the Redis buffer flush worker"""
    global _buffer_flusher
    if _buffer_flusher:
        await _buffer_flusher.stop()

