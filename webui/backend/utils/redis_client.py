"""
Redis client utility for caching and write buffering
"""
import json
import logging
from typing import Optional, Any, Dict, List
from datetime import timedelta
import redis.asyncio as redis
from ..config import settings

logger = logging.getLogger(__name__)

# Global Redis client instance (initialized on first use)
_redis_client: Optional[redis.Redis] = None
_redis_available = False


async def get_redis_client() -> Optional[redis.Redis]:
    """Get or create Redis client instance with connection pooling
    
    Returns:
        Redis client instance or None if Redis is unavailable
    """
    global _redis_client, _redis_available
    
    if _redis_client is None:
        try:
            _redis_client = redis.Redis(
                host=settings.redis_host,
                port=settings.redis_port,
                db=settings.redis_db,
                password=settings.redis_password,
                decode_responses=True,  # Automatically decode responses to strings
                socket_connect_timeout=2,  # 2 second connection timeout
                socket_timeout=2,  # 2 second socket timeout
                retry_on_timeout=True,
                health_check_interval=30,  # Check connection health every 30 seconds
            )
            
            # Test connection
            await _redis_client.ping()
            _redis_available = True
            logger.info(f"Connected to Redis at {settings.redis_host}:{settings.redis_port}")
        except Exception as e:
            logger.warning(f"Redis unavailable, falling back to database: {e}")
            _redis_available = False
            _redis_client = None
            return None
    
    # Test connection on each request (health check)
    if _redis_client and _redis_available:
        try:
            await _redis_client.ping()
            return _redis_client
        except Exception as e:
            logger.warning(f"Redis connection lost, falling back to database: {e}")
            _redis_available = False
            try:
                await _redis_client.close()
            except Exception:
                pass
            _redis_client = None
            return None
    
    return None


async def close_redis_client():
    """Close Redis client connection"""
    global _redis_client, _redis_available
    
    if _redis_client:
        try:
            await _redis_client.close()
        except Exception as e:
            logger.warning(f"Error closing Redis client: {e}")
        finally:
            _redis_client = None
            _redis_available = False


def is_redis_available() -> bool:
    """Check if Redis is available"""
    return _redis_available


async def get(key: str) -> Optional[str]:
    """Get value from Redis
    
    Args:
        key: Redis key
        
    Returns:
        Value as string or None if not found/unavailable
    """
    client = await get_redis_client()
    if not client:
        return None
    
    try:
        return await client.get(key)
    except Exception as e:
        logger.warning(f"Redis GET error for key {key}: {e}")
        return None


async def set(key: str, value: str, ttl: Optional[int] = None) -> bool:
    """Set value in Redis with optional TTL
    
    Args:
        key: Redis key
        value: Value to store
        ttl: Time to live in seconds (None = no expiration)
        
    Returns:
        True if successful, False otherwise
    """
    client = await get_redis_client()
    if not client:
        return False
    
    try:
        if ttl:
            await client.setex(key, ttl, value)
        else:
            await client.set(key, value)
        return True
    except Exception as e:
        logger.warning(f"Redis SET error for key {key}: {e}")
        return False


async def get_json(key: str) -> Optional[Any]:
    """Get JSON value from Redis
    
    Args:
        key: Redis key
        
    Returns:
        Parsed JSON value or None if not found/unavailable
    """
    value = await get(key)
    if value is None:
        return None
    
    try:
        return json.loads(value)
    except json.JSONDecodeError as e:
        logger.warning(f"Redis JSON decode error for key {key}: {e}")
        return None


async def set_json(key: str, value: Any, ttl: Optional[int] = None) -> bool:
    """Set JSON value in Redis
    
    Args:
        key: Redis key
        value: JSON-serializable value
        ttl: Time to live in seconds (None = no expiration)
        
    Returns:
        True if successful, False otherwise
    """
    try:
        json_str = json.dumps(value)
        return await set(key, json_str, ttl)
    except (TypeError, ValueError) as e:
        logger.warning(f"Redis JSON encode error for key {key}: {e}")
        return False


async def delete(key: str) -> bool:
    """Delete key from Redis
    
    Args:
        key: Redis key
        
    Returns:
        True if successful, False otherwise
    """
    client = await get_redis_client()
    if not client:
        return False
    
    try:
        await client.delete(key)
        return True
    except Exception as e:
        logger.warning(f"Redis DELETE error for key {key}: {e}")
        return False


async def exists(key: str) -> bool:
    """Check if key exists in Redis
    
    Args:
        key: Redis key
        
    Returns:
        True if key exists, False otherwise
    """
    client = await get_redis_client()
    if not client:
        return False
    
    try:
        result = await client.exists(key)
        return result > 0
    except Exception as e:
        logger.warning(f"Redis EXISTS error for key {key}: {e}")
        return False


async def list_push(key: str, *values: str) -> bool:
    """Push values to Redis list (right push)
    
    Args:
        key: Redis list key
        *values: Values to push
        
    Returns:
        True if successful, False otherwise
    """
    client = await get_redis_client()
    if not client:
        return False
    
    try:
        await client.rpush(key, *values)
        return True
    except Exception as e:
        logger.warning(f"Redis RPUSH error for key {key}: {e}")
        return False


async def list_pop(key: str, count: int = 1) -> List[str]:
    """Pop values from Redis list (left pop)
    
    Args:
        key: Redis list key
        count: Number of values to pop
        
    Returns:
        List of popped values (may be empty)
    """
    client = await get_redis_client()
    if not client:
        return []
    
    try:
        if count == 1:
            value = await client.lpop(key)
            return [value] if value else []
        else:
            # Use pipeline for multiple pops
            pipe = client.pipeline()
            for _ in range(count):
                pipe.lpop(key)
            results = await pipe.execute()
            return [v for v in results if v is not None]
    except Exception as e:
        logger.warning(f"Redis LPOP error for key {key}: {e}")
        return []


async def list_length(key: str) -> int:
    """Get length of Redis list
    
    Args:
        key: Redis list key
        
    Returns:
        Length of list or 0 if unavailable
    """
    client = await get_redis_client()
    if not client:
        return 0
    
    try:
        return await client.llen(key)
    except Exception as e:
        logger.warning(f"Redis LLEN error for key {key}: {e}")
        return 0


async def hash_set(key: str, field: str, value: str) -> bool:
    """Set field in Redis hash
    
    Args:
        key: Redis hash key
        field: Hash field name
        value: Value to store
        
    Returns:
        True if successful, False otherwise
    """
    client = await get_redis_client()
    if not client:
        return False
    
    try:
        await client.hset(key, field, value)
        return True
    except Exception as e:
        logger.warning(f"Redis HSET error for key {key}, field {field}: {e}")
        return False


async def hash_get(key: str, field: str) -> Optional[str]:
    """Get field from Redis hash
    
    Args:
        key: Redis hash key
        field: Hash field name
        
    Returns:
        Field value or None if not found/unavailable
    """
    client = await get_redis_client()
    if not client:
        return None
    
    try:
        return await client.hget(key, field)
    except Exception as e:
        logger.warning(f"Redis HGET error for key {key}, field {field}: {e}")
        return None


async def hash_get_all(key: str) -> Dict[str, str]:
    """Get all fields from Redis hash
    
    Args:
        key: Redis hash key
        
    Returns:
        Dictionary of all fields and values
    """
    client = await get_redis_client()
    if not client:
        return {}
    
    try:
        return await client.hgetall(key)
    except Exception as e:
        logger.warning(f"Redis HGETALL error for key {key}: {e}")
        return {}

