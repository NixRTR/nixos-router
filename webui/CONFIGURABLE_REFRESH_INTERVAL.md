# Configurable Refresh Interval Feature

## Overview

Added user-configurable refresh interval to the Network Bandwidth page, allowing users to choose how frequently the chart updates (1, 5, 10, 30, or 60 seconds).

## Feature Details

### UI Changes

**New Dropdown**: "Update Every"
- Location: Third column in the filter controls
- Default: 10 seconds
- Options:
  - 1 second - Real-time monitoring
  - 5 seconds - Frequent updates
  - 10 seconds - Balanced (default)
  - 30 seconds - Low traffic monitoring
  - 60 seconds - Historical overview

### Layout

```
+----------------+----------------+----------------+
| Select         | Time Range     | Update Every   |
| Interface      |                |                |
+----------------+----------------+----------------+
| WAN (ppp0)     | 1 hour         | 10 seconds     |
| HOMELAB (br0)  | 10 minutes     | 1 second       |
| LAN (br1)      | 30 minutes     | 5 seconds      |
|                | 3 hours        | 30 seconds     |
|                | ...            | 1 minute       |
+----------------+----------------+----------------+
```

## Use Cases

### 1. Real-time Troubleshooting (1 second)
**Scenario**: Diagnosing network issues, testing speed changes
```
User: "Is the VPN affecting my speed?"
Action: Set to 1-second updates, monitor real-time impact
Result: Immediate feedback on network performance
```

### 2. Active Monitoring (5-10 seconds)
**Scenario**: Normal usage, keeping an eye on bandwidth
```
User: Regular monitoring during work hours
Action: Use default 10-second updates
Result: Good balance between freshness and resource usage
```

### 3. Passive Monitoring (30-60 seconds)
**Scenario**: Background monitoring, low-resource systems
```
User: Dashboard running 24/7 on a low-power device
Action: Set to 60-second updates
Result: Minimal server/client load, still useful data
```

## Technical Implementation

### State Management

```typescript
const [refreshInterval, setRefreshInterval] = useState(10); // seconds
```

### Dynamic Interval

```typescript
// Refresh based on user-selected interval
const interval = setInterval(fetchHistory, refreshInterval * 1000);
return () => clearInterval(interval);
```

### Dependencies

```typescript
useEffect(() => {
  // ...
}, [selectedInterface, timeRange, customRange, refreshInterval, token]);
```

**Key**: When `refreshInterval` changes, the effect re-runs, clearing the old interval and starting a new one with the updated frequency.

### Status Display

```typescript
Auto-refreshing every {refreshInterval === 1 ? '1 second' : `${refreshInterval} seconds`}
```

## Performance Considerations

### Server Load

| Interval | Requests/Hour | Relative Load |
|----------|---------------|---------------|
| 1 second | 3,600 | 36x |
| 5 seconds | 720 | 7.2x |
| 10 seconds | 360 | 3.6x (default) |
| 30 seconds | 120 | 1.2x |
| 60 seconds | 60 | 1x (baseline) |

### Recommendations

**For typical use:**
- ✅ 10 seconds (default) - Good balance
- ✅ 5 seconds - If you need more responsiveness
- ❌ 1 second - Only for active troubleshooting (not 24/7)

**Server impact:**
- 1-second intervals with multiple users can increase server load significantly
- Backend is optimized (smart caching, efficient queries) but be mindful
- Consider your server resources when choosing fast intervals

### Smart Caching Still Works

The data comparison optimization (`lastDataRef`) ensures that even with 1-second polling:
- If data hasn't changed, component doesn't re-render
- Chart stays stable
- Only real changes trigger visual updates

This means 1-second polling is viable for troubleshooting without performance degradation from unnecessary re-renders.

## User Experience

### Before This Feature
```
User: "The chart updates too slowly for troubleshooting"
      or
      "The chart updates too often, it's using too much bandwidth"
```
Fixed refresh rate = Can't satisfy both needs

### After This Feature
```
Power User: Set to 1s for real-time debugging
Casual User: Keep at 10s for normal monitoring
Resource-Conscious User: Set to 60s for minimal load
```
Everyone gets exactly what they need ✅

## Code Changes

### File Modified
`webui/frontend/src/pages/Network.tsx`

### Changes Made
1. Added `refreshInterval` state (default: 10)
2. Added dropdown selector for refresh interval
3. Updated `setInterval` to use dynamic interval
4. Added `refreshInterval` to useEffect dependencies
5. Updated status text to show current interval
6. Changed grid layout from 3 to 4 columns

### Lines Changed
- Line 31: Added `refreshInterval` state
- Line 94: Dynamic interval calculation
- Line 96: Added `refreshInterval` to dependencies
- Line 122: Changed grid to 4 columns
- Lines 159-173: New refresh interval selector
- Line 240: Dynamic status text

## Testing

### Test Cases

1. **Default Behavior**
   - Should start with 10-second updates
   - Status should show "Auto-refreshing every 10 seconds"

2. **Change Interval**
   - Change to 1 second → Updates every 1 second
   - Change to 60 seconds → Updates every 60 seconds
   - Status text updates correctly

3. **Interval Timing**
   - Use browser DevTools Network tab
   - Verify requests occur at correct intervals
   - Confirm no overlapping requests

4. **State Persistence**
   - Set to custom interval (e.g., 5 seconds)
   - Change interface → Interval persists
   - Change time range → Interval persists
   - Refresh page → Resets to default (10s)

5. **Visual Feedback**
   - Fast interval (1s) → Chart updates frequently
   - Slow interval (60s) → Chart updates slowly
   - No animation/redraw on any interval

## Deployment

### Build Frontend

```bash
# In WSL
cd /mnt/c/Users/Willi/github/nixos-router/webui/frontend
npm run build

# Verify build
ls -la dist/
```

### Commit Changes

```bash
cd /mnt/c/Users/Willi/github/nixos-router
git add webui/frontend/src/pages/Network.tsx
git add webui/frontend/dist/
git commit -m "feat: Add configurable refresh interval for bandwidth charts (1-60s)"
```

### Deploy to Router

```bash
# On router
cd /etc/nixos
git pull
sudo nixos-rebuild switch
```

### Verify Deployment

1. Open http://192.168.2.1:8080/network
2. Check for "Update Every" dropdown
3. Test changing intervals
4. Verify chart updates at selected frequency

## Future Enhancements

### Potential Additions

1. **Persist Preference**
   ```typescript
   // Save to localStorage
   useEffect(() => {
     localStorage.setItem('refreshInterval', String(refreshInterval));
   }, [refreshInterval]);
   
   // Load on mount
   const saved = localStorage.getItem('refreshInterval');
   const [refreshInterval, setRefreshInterval] = useState(saved ? Number(saved) : 10);
   ```

2. **Auto-Adjust Based on Activity**
   ```typescript
   // Faster updates when user is actively viewing
   // Slower updates when tab is backgrounded
   useEffect(() => {
     const handleVisibilityChange = () => {
       if (document.hidden) {
         // Slow down to 60s when backgrounded
       } else {
         // Resume user-selected interval
       }
     };
     document.addEventListener('visibilitychange', handleVisibilityChange);
   }, []);
   ```

3. **Smart Recommendations**
   ```typescript
   // Suggest interval based on time range
   if (timeRange === '10m' || timeRange === '30m') {
     // Recommend 5s for short ranges
   } else if (timeRange === '1M' || timeRange === '1y') {
     // Recommend 60s for long ranges
   }
   ```

4. **Bandwidth Indicator**
   ```typescript
   // Show estimated bandwidth usage
   "Estimated: ~{requestsPerHour * avgResponseSize} MB/hour"
   ```

## Documentation Updates

- ✅ Updated `CHART_PERFORMANCE_FIX.md` with new feature
- ✅ Created this document (`CONFIGURABLE_REFRESH_INTERVAL.md`)
- ✅ Code comments added to `Network.tsx`

## Conclusion

This feature gives users control over the refresh frequency, making the bandwidth monitoring tool more flexible and suitable for different use cases - from real-time troubleshooting to long-term passive monitoring.

**Result**: 🎯 Users can now optimize their experience for their specific needs without compromising functionality.

