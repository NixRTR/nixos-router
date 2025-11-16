# System Page - Network-Style Implementation

**Date**: November 16, 2025  
**Status**: ✅ Ready to Deploy  
**Scope**: System page redesigned to match Network page behavior

---

## What Changed

### Complete Redesign
The System page now works exactly like the Network page:
- **Historical data from database** for CPU/Memory/Load
- **Per-chart controls** for time range and refresh interval
- **Smart updates** - only redraws when data changes
- **Responsive grid** - 2 columns desktop, 1 column mobile
- **Default 30 minutes** time range

### Backend Changes

**File**: `webui/backend/api/system.py`
- Added `SystemDataPoint` model
- Added `SystemHistory` model
- Added `parse_time_range()` function
- Added `GET /api/system/history` endpoint
  - Returns historical CPU/Memory/Load data from database
  - Accepts `range` parameter (e.g., "30m", "1h", "3h")
  - Queries `SystemMetricsDB` table

### Frontend Changes

**File**: `webui/frontend/src/pages/System.tsx`
- Complete rewrite (700+ lines)
- **Separate state** for each chart's time range and refresh interval
- **Historical data fetching** for CPU/Memory/Load from API
- **Real-time accumulation** for Disk I/O and Temperatures
- **Smart updates** using `useRef` to prevent unnecessary re-renders
- **Memoized chart data** using `useMemo` for performance
- **2-column grid** on desktop (lg:grid-cols-2)
- **1-column grid** on mobile
- **Chart controls**:
  - **Shared Time Range**: 10m, 30m, 1h, 3h, 6h, 12h, 1d, custom (changing on any chart updates all charts)
  - **Independent Update Interval**: 1, 5, 10, 30, 60 seconds per chart

---

## Features

### 📊 CPU Usage Chart
- Fetches historical data from database
- **Shared time range control** (default: 30m) - changes all charts
- Independent refresh interval control (default: 10s)
- Shows current value and data point count
- Smart updates - only refreshes when data changes

### 💾 Memory Usage Chart
- Fetches historical data from database
- **Shared time range control** - synced with all charts
- Independent refresh interval control
- Shows current percentage
- Displays data point count

### ⚖️ Load Average Chart
- Fetches historical data from database
- **Shared time range control** - synced with all charts
- Independent refresh interval control
- Shows 1-minute load average
- Displays data point count

### 💿 Disk I/O Charts
- **One chart per physical disk**
- Real-time data accumulation
- Combined read/write on same chart
- Filters out partitions (sda1, sda2, etc.)
- Shows current read/write in MB/s
- **Shared time range control** - synced with all charts
- Independent refresh interval control

### 🌡️ Temperature Charts
- **One chart per sensor**
- Real-time data accumulation
- Friendly sensor names (CPU, Motherboard, etc.)
- Color-coded current values (green/yellow/red)
- **Shared time range control** - synced with all charts
- Independent refresh interval control

### 👥 Network Clients
- Full-width card at bottom
- Text display (not chart)
- Separate cards for HOMELAB and LAN
- Shows DHCP/Static/Online/Offline counts

---

## Technical Details

### Historical Data Flow

```
Frontend Request
    ↓
GET /api/system/history?range=30m
    ↓
Backend queries SystemMetricsDB
    ↓
Returns array of data points
    ↓
Frontend stores in state
    ↓
useMemo transforms for chart
    ↓
Recharts renders (no animation)
```

### Smart Update Logic

```typescript
const cpuLastDataRef = useRef<string>('');

// In fetch effect:
const newDataString = JSON.stringify(data.data);
if (newDataString !== cpuLastDataRef.current) {
  setCpuHistoricalData(data.data);
  cpuLastDataRef.current = newDataString;
}
```

**Benefits**:
- Prevents unnecessary state updates
- Avoids chart redraws when data hasn't changed
- Reduces CPU usage
- Smoother UI experience

### Responsive Grid

```tsx
<div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
  {/* Charts here */}
</div>
```

**Breakpoints**:
- `< 1024px`: 1 column (mobile/tablet)
- `≥ 1024px`: 2 columns (desktop)

### Shared Time Range + Independent Refresh

All charts share the same time range but have independent refresh intervals:
```typescript
// Shared across all charts
const [timeRange, setTimeRange] = useState('30m');
const [customRange, setCustomRange] = useState('');

// Independent per chart
const [cpuRefreshInterval, setCpuRefreshInterval] = useState(10);
const [memRefreshInterval, setMemRefreshInterval] = useState(10);
const [loadRefreshInterval, setLoadRefreshInterval] = useState(10);
```

**Benefits**:
- **Unified view**: All charts show the same time period
- **Easy comparison**: See correlations across metrics
- **One control**: Change time range once, affects all charts
- **Independent updates**: CPU at 1s, Disk at 10s, etc.
- **Flexible**: Each chart can refresh at its own rate

---

## API Endpoints

### Get Historical System Metrics
```bash
GET /api/system/history?range=30m
```

**Query Parameters**:
- `range` (string): Time range (e.g., "10m", "1h", "3h")

**Response**:
```json
{
  "data": [
    {
      "timestamp": "2025-11-16T12:00:00Z",
      "cpu_percent": 25.3,
      "memory_percent": 45.2,
      "load_avg_1m": 1.20
    },
    ...
  ]
}
```

### Get Current System Metrics
```bash
GET /api/system/current
```

**Response**: Full snapshot including disk I/O, temperatures, etc.

---

## Before vs After

### Before
```
System Monitoring

┌─────────────────────────────────────┐
│ CPU Usage                           │ ← Single time range at top
│ [Chart]                             │ ← No controls per chart
├─────────────────────────────────────┤ ← 1 column (mobile-like)
│ Memory Usage                        │
│ [Chart]                             │
├─────────────────────────────────────┤
│ Load Average                        │
│ [Chart]                             │
└─────────────────────────────────────┘
```

### After
```
System Monitoring

┌──────────────────────┬──────────────────────┐ ← 2 columns desktop
│ CPU Usage            │ Memory Usage         │
│ [Range▼] [Update▼]  │ [Range▼] [Update▼]  │ ← Per-chart controls
│ [Chart]              │ [Chart]              │
│ Current: 25.3%       │ Current: 45.2%       │ ← Current values
│ 180 points           │ 180 points           │ ← Data point count
├──────────────────────┼──────────────────────┤
│ Load Average         │ Disk I/O - SDA       │
│ [Range▼] [Update▼]  │ [Range▼] [Update▼]  │
│ [Chart]              │ [Read/Write Chart]   │
│ Current: 1.20        │ ↓5.2 MB/s ↑2.1 MB/s │
│ 180 points           │ 900 points           │
├──────────────────────┴──────────────────────┤
│ Network Clients                             │ ← Full width
│ [HOMELAB]  [LAN]                           │
└─────────────────────────────────────────────┘
```

---

## Benefits

### For Users
- **Independent controls**: Set different ranges/intervals per chart
- **More screen space**: 2 charts side-by-side on desktop
- **Mobile optimized**: Stacks to 1 column on phones
- **Current values**: Always visible in footer
- **Data points count**: Know how much history is shown

### For Performance
- **Smart updates**: Only redraws when data changes
- **Memoized data**: Chart transformations cached
- **No animations**: Disabled for smooth updates
- **Database queries**: Efficient historical data fetching

### For Troubleshooting
- **Long history**: Can set charts to hours or days
- **Quick updates**: Can set 1-second refresh for debugging
- **Independent views**: CPU at 1 hour, Load at 1 day, etc.
- **Point counts**: See data density (more points = more detail)

---

## Deploy

### Step 1: Build Frontend

```bash
# In WSL
cd /mnt/c/Users/Willi/github/nixos-router/webui/frontend
npm run build
```

### Step 2: Commit and Deploy

```bash
cd /mnt/c/Users/Willi/github/nixos-router

# Add changes
git add webui/backend/api/system.py
git add webui/frontend/src/pages/System.tsx
git add webui/frontend/dist/
git add webui/SYSTEM_PAGE_FINAL.md

# Commit
git commit -m "feat(webui): Redesign System page with shared time range

- Add historical data API endpoint for CPU/Memory/Load
- Fetch historical data from database (not real-time accumulation)
- Use SHARED time range across all charts
- Use INDEPENDENT refresh intervals per chart
- Use 2-column grid on desktop, 1-column on mobile
- Implement smart updates (only redraw when data changes)
- Use useMemo for chart data transformation
- Default to 30 minutes time range
- Show current values and data point counts
- Changing time range on any chart updates all charts
- Disable animations for smooth updates"

git push

# On router
cd /etc/nixos && git pull && sudo nixos-rebuild switch
```

### Step 3: Verify

Navigate to `http://192.168.2.1:8080`, click "System":

✅ 2 charts per row on desktop  
✅ 1 chart per row on mobile  
✅ **Shared time range controls** (changing any chart updates all)  
✅ **Independent refresh interval controls** per chart  
✅ Default 30 minutes time range  
✅ Historical data loads from database (CPU/Mem/Load)  
✅ Current values shown in footers  
✅ Data point counts displayed  
✅ Smart updates (no unnecessary redraws)  
✅ All charts sync when time range changes  

---

## Troubleshooting

### No Historical Data
**Cause**: Database doesn't have enough data yet  
**Solution**: Wait for data to accumulate (2-second collection interval)  
**Check**: `SELECT COUNT(*) FROM system_metrics WHERE timestamp > NOW() - INTERVAL '30 minutes';`

### Charts Not Updating
**Cause**: Refresh interval too high or backend down  
**Solution**: Check backend status: `systemctl status router-webui-backend`  
**Check**: Browser console for errors (F12)

### Different Ranges Not Working
**Cause**: Custom range format incorrect  
**Solution**: Use format: "10m", "1h", "3h" (number + unit)  
**Valid units**: m (minutes), h (hours), d (days)

### Too Many/Too Few Points
**Expected**: Points = (time_range_seconds / collection_interval)  
**Example**: 30 minutes / 2 seconds = 900 points  
**Adjust**: Use different time range or wait for more data

### Mobile Layout Broken
**Cause**: CSS breakpoint issue  
**Solution**: Check browser width, should stack at < 1024px  
**Test**: Use browser DevTools responsive mode

---

## Success Criteria

✅ **2 charts per row on desktop** (≥1024px width)  
✅ **1 chart per row on mobile** (<1024px width)  
✅ **Shared time range controls** (changing any chart updates all)  
✅ **Independent refresh interval controls** per chart  
✅ **Default 30 minutes** time range  
✅ **Historical data loaded** from database (CPU/Mem/Load)  
✅ **Smart updates** (no redraw if data unchanged)  
✅ **Current values displayed** in chart footers  
✅ **Data point counts shown**  
✅ **All charts sync** when time range changes  
✅ **No TypeScript errors**  
✅ **No console errors**  
✅ **Smooth performance** (no lag or stuttering)  

---

## Future Enhancements

Possible improvements:

1. **Persistent Settings**: Save time ranges in localStorage
2. **Export Data**: Download chart data as CSV
3. **Zoom/Pan**: Interactive chart navigation
4. **Alert Thresholds**: Visual indicators for high values
5. **Historical Disk I/O**: Store in database for long-term history
6. **Historical Temps**: Store in database for long-term history
7. **Comparison Mode**: Compare current vs previous time period
8. **Custom Chart Colors**: User-selectable color schemes

---

**Questions or Issues?**  
Check browser console (F12) or backend logs:
```bash
journalctl -u router-webui-backend -f
```

