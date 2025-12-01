"""
Notification evaluator worker
Periodically evaluates notification rules and sends alerts when thresholds are exceeded
"""
import asyncio
import logging

from ..database import AsyncSessionLocal
from ..collectors.notifications import NotificationEvaluator
from ..config import settings

logger = logging.getLogger(__name__)


class NotificationWorker:
    """Worker that periodically evaluates notification rules"""
    
    def __init__(self):
        self.running = False
        self._task: asyncio.Task = None
        self.evaluator = NotificationEvaluator(AsyncSessionLocal)
    
    async def start(self):
        """Start the notification worker"""
        if self.running:
            return
        
        self.running = True
        self._task = asyncio.create_task(self._evaluation_loop())
        logger.info("Notification worker started")
    
    async def stop(self):
        """Stop the notification worker"""
        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("Notification worker stopped")
    
    async def _evaluation_loop(self):
        """Main evaluation loop - runs periodically"""
        while self.running:
            try:
                await self.evaluator.evaluate_all()
                await asyncio.sleep(settings.notification_check_interval)
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.error(
                    "Notification evaluator error: %s", exc, exc_info=True
                )
                await asyncio.sleep(settings.notification_check_interval)


# Global notification worker instance
_notification_worker: NotificationWorker = None


async def start_notification_worker():
    """Start the notification worker"""
    global _notification_worker
    if _notification_worker is None:
        _notification_worker = NotificationWorker()
    await _notification_worker.start()


async def stop_notification_worker():
    """Stop the notification worker"""
    global _notification_worker
    if _notification_worker:
        await _notification_worker.stop()

