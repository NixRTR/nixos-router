"""
Data aggregation module for tiered retention strategy
Aggregates raw data into 1m, 5m, 1h, and 1d intervals to reduce storage
"""
import asyncio
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Tuple
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import AsyncSessionLocal, ClientBandwidthStatsDB, ClientConnectionStatsDB


async def aggregate_client_bandwidth_stats():
    """Aggregate client bandwidth stats according to tiered retention strategy"""
    async with AsyncSessionLocal() as session:
        now = datetime.now(timezone.utc)
        
        # 1. Aggregate raw → 1-minute: Data older than 2 days
        cutoff_2d = now - timedelta(days=2)
        await _aggregate_to_interval(
            session,
            ClientBandwidthStatsDB,
            source_level='raw',
            target_level='1m',
            interval_seconds=60,
            cutoff_time=cutoff_2d,
            group_by=['mac_address', 'ip_address', 'network']
        )
        
        # 2. Aggregate 1-minute → 5-minute: Data older than 7 days
        cutoff_7d = now - timedelta(days=7)
        await _aggregate_to_interval(
            session,
            ClientBandwidthStatsDB,
            source_level='1m',
            target_level='5m',
            interval_seconds=300,
            cutoff_time=cutoff_7d,
            group_by=['mac_address', 'ip_address', 'network']
        )
        
        # 3. Aggregate 5-minute → 1-hour: Data older than 30 days
        cutoff_30d = now - timedelta(days=30)
        await _aggregate_to_interval(
            session,
            ClientBandwidthStatsDB,
            source_level='5m',
            target_level='1h',
            interval_seconds=3600,
            cutoff_time=cutoff_30d,
            group_by=['mac_address', 'ip_address', 'network']
        )
        
        # 4. Aggregate 1-hour → 1-day: Data older than 90 days
        cutoff_90d = now - timedelta(days=90)
        await _aggregate_to_interval(
            session,
            ClientBandwidthStatsDB,
            source_level='1h',
            target_level='1d',
            interval_seconds=86400,
            cutoff_time=cutoff_90d,
            group_by=['mac_address', 'ip_address', 'network']
        )
        
        # 5. Delete data older than retention period (1 year)
        cutoff_1y = now - timedelta(days=365)
        await session.execute(
            delete(ClientBandwidthStatsDB).where(
                ClientBandwidthStatsDB.timestamp < cutoff_1y
            )
        )
        
        await session.commit()


async def aggregate_client_connection_stats():
    """Aggregate client connection stats according to tiered retention strategy"""
    async with AsyncSessionLocal() as session:
        now = datetime.now(timezone.utc)
        
        # 1. Aggregate raw → 1-minute: Data older than 2 days
        cutoff_2d = now - timedelta(days=2)
        await _aggregate_to_interval(
            session,
            ClientConnectionStatsDB,
            source_level='raw',
            target_level='1m',
            interval_seconds=60,
            cutoff_time=cutoff_2d,
            group_by=['client_ip', 'client_mac', 'remote_ip', 'remote_port']
        )
        
        # 2. Aggregate 1-minute → 5-minute: Data older than 7 days
        cutoff_7d = now - timedelta(days=7)
        await _aggregate_to_interval(
            session,
            ClientConnectionStatsDB,
            source_level='1m',
            target_level='5m',
            interval_seconds=300,
            cutoff_time=cutoff_7d,
            group_by=['client_ip', 'client_mac', 'remote_ip', 'remote_port']
        )
        
        # 3. Aggregate 5-minute → 1-hour: Data older than 30 days
        cutoff_30d = now - timedelta(days=30)
        await _aggregate_to_interval(
            session,
            ClientConnectionStatsDB,
            source_level='5m',
            target_level='1h',
            interval_seconds=3600,
            cutoff_time=cutoff_30d,
            group_by=['client_ip', 'client_mac', 'remote_ip', 'remote_port']
        )
        
        # 4. Aggregate 1-hour → 1-day: Data older than 90 days
        cutoff_90d = now - timedelta(days=90)
        await _aggregate_to_interval(
            session,
            ClientConnectionStatsDB,
            source_level='1h',
            target_level='1d',
            interval_seconds=86400,
            cutoff_time=cutoff_90d,
            group_by=['client_ip', 'client_mac', 'remote_ip', 'remote_port']
        )
        
        # 5. Delete data older than retention period (1 year)
        cutoff_1y = now - timedelta(days=365)
        await session.execute(
            delete(ClientConnectionStatsDB).where(
                ClientConnectionStatsDB.timestamp < cutoff_1y
            )
        )
        
        await session.commit()


async def _aggregate_to_interval(
    session: AsyncSession,
    model_class,
    source_level: str,
    target_level: str,
    interval_seconds: int,
    cutoff_time: datetime,
    group_by: List[str]
):
    """Aggregate data from source_level to target_level
    
    Args:
        session: Database session
        model_class: Model class (ClientBandwidthStatsDB or ClientConnectionStatsDB)
        source_level: Source aggregation level ('raw', '1m', '5m', '1h')
        target_level: Target aggregation level ('1m', '5m', '1h', '1d')
        interval_seconds: Interval in seconds for bucketing
        cutoff_time: Only aggregate data older than this time
        group_by: List of column names to group by
    """
    # Query source data in batches to avoid loading everything into memory
    # Process in chunks of 10000 records at a time
    batch_size = 10000
    offset = 0
    buckets: Dict[Tuple, Dict] = {}
    
    while True:
        query = select(model_class).where(
            model_class.aggregation_level == source_level,
            model_class.timestamp < cutoff_time
        ).order_by(*[getattr(model_class, col) for col in group_by], model_class.timestamp.asc()).limit(batch_size).offset(offset)
        
        result = await session.execute(query)
        source_stats = result.scalars().all()
        
        if not source_stats:
            break
        
        # Group by time buckets and group_by columns
        for stat in source_stats:
            # Round timestamp to interval boundary
            timestamp_seconds = int(stat.timestamp.timestamp())
            rounded_seconds = (timestamp_seconds // interval_seconds) * interval_seconds
            bucket_time = datetime.fromtimestamp(rounded_seconds, tz=timezone.utc).replace(microsecond=0)
            
            # Create group key from group_by columns
            group_key = tuple(getattr(stat, col) for col in group_by)
            bucket_key = (bucket_time, group_key)
            
            if bucket_key not in buckets:
                buckets[bucket_key] = {
                    'rx_bytes_sum': 0,
                    'tx_bytes_sum': 0,
                    'rx_bytes_total_max': 0,
                    'tx_bytes_total_max': 0,
                    'count': 0
                }
            
            # Sum interval bytes
            buckets[bucket_key]['rx_bytes_sum'] += stat.rx_bytes
            buckets[bucket_key]['tx_bytes_sum'] += stat.tx_bytes
            
            # Track max cumulative totals (latest value in bucket)
            if stat.rx_bytes_total > buckets[bucket_key]['rx_bytes_total_max']:
                buckets[bucket_key]['rx_bytes_total_max'] = stat.rx_bytes_total
            if stat.tx_bytes_total > buckets[bucket_key]['tx_bytes_total_max']:
                buckets[bucket_key]['tx_bytes_total_max'] = stat.tx_bytes_total
            
            buckets[bucket_key]['count'] += 1
        
        # If we got fewer records than batch_size, we're done
        if len(source_stats) < batch_size:
            break
        
        offset += batch_size
    
    if not buckets:
        return
    
    # Create aggregated records
    aggregated_records = []
    
    for (bucket_time, group_key), bucket_data in buckets.items():
        
        # Create aggregated record
        agg_data = {
            'timestamp': bucket_time,
            'rx_bytes': bucket_data['rx_bytes_sum'],
            'tx_bytes': bucket_data['tx_bytes_sum'],
            'rx_bytes_total': bucket_data['rx_bytes_total_max'],
            'tx_bytes_total': bucket_data['tx_bytes_total_max'],
            'aggregation_level': target_level
        }
        
        # Add group_by fields
        for i, col in enumerate(group_by):
            agg_data[col] = group_key[i]
        
        # Create model instance
        if model_class == ClientBandwidthStatsDB:
            agg_record = ClientBandwidthStatsDB(**agg_data)
        else:  # ClientConnectionStatsDB
            agg_record = ClientConnectionStatsDB(**agg_data)
        
        aggregated_records.append(agg_record)
    
    # Insert aggregated records
    for record in aggregated_records:
        session.add(record)
    
    # Delete source records
    await session.execute(
        delete(model_class).where(
            model_class.aggregation_level == source_level,
            model_class.timestamp < cutoff_time
        )
    )
    
    await session.commit()


async def run_aggregation_job():
    """Run the daily aggregation job"""
    try:
        print("Starting data aggregation job...")
        await aggregate_client_bandwidth_stats()
        await aggregate_client_connection_stats()
        print("Data aggregation job completed successfully")
    except Exception as e:
        print(f"Error in aggregation job: {e}")
        import traceback
        traceback.print_exc()

