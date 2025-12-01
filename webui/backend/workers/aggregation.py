"""
Daily aggregation worker
Runs data aggregation jobs daily at 2 AM UTC to reduce storage usage
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from ..collectors.aggregation import run_aggregation_job

logger = logging.getLogger(__name__)


class AggregationWorker:
    """Worker that runs aggregation job daily at 2 AM UTC"""
    
    def __init__(self):
        self.running = False
        self._task: asyncio.Task = None
    
    async def start(self):
        """Start the aggregation worker"""
        if self.running:
            return
        
        self.running = True
        self._task = asyncio.create_task(self._aggregation_loop())
        logger.info("Aggregation worker started")
    
    async def stop(self):
        """Stop the aggregation worker"""
        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("Aggregation worker stopped")
    
    async def _aggregation_loop(self):
        """Main aggregation loop - runs daily at 2 AM UTC"""
        while self.running:
            try:
                # Calculate time until next 2 AM UTC
                now = datetime.now(timezone.utc)
                target_hour = 2  # 2 AM UTC
                
                # If it's already past 2 AM today, schedule for tomorrow
                if now.hour >= target_hour:
                    next_run = datetime(now.year, now.month, now.day, target_hour, 0, 0, tzinfo=timezone.utc) + timedelta(days=1)
                else:
                    next_run = datetime(now.year, now.month, now.day, target_hour, 0, 0, tzinfo=timezone.utc)
                
                wait_seconds = (next_run - now).total_seconds()
                logger.info(f"Aggregation job scheduled for {next_run} (in {wait_seconds/3600:.1f} hours)")
                
                await asyncio.sleep(wait_seconds)
                
                # Run aggregation job
                await run_aggregation_job()
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in aggregation worker: {e}", exc_info=True)
                # Wait 1 hour before retrying on error
                await asyncio.sleep(3600)


# Global aggregation worker instance
_aggregation_worker: AggregationWorker = None


async def start_aggregation_worker():
    """Start the aggregation worker"""
    global _aggregation_worker
    if _aggregation_worker is None:
        _aggregation_worker = AggregationWorker()
    await _aggregation_worker.start()


async def stop_aggregation_worker():
    """Stop the aggregation worker"""
    global _aggregation_worker
    if _aggregation_worker:
        await _aggregation_worker.stop()

