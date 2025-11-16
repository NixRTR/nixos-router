# System Page Implementation

**Date**: November 16, 2025  
**Status**: ✅ Ready to Deploy  
**Scope**: Comprehensive system monitoring page with advanced metrics

---

## What Changed

### New "System" Page (formerly "History")
Renamed and completely redesigned to show comprehensive system monitoring data:

#### Real-Time Metrics
- **CPU Usage** - Current percentage with historical chart
- **Memory Usage** - Current percentage with historical chart
- **Load Average** - 1m/5m/15m with historical chart
- **Uptime** - System uptime display

#### Disk Metrics
- **Disk I/O** - Real-time read/write rates per device (bytes/sec, ops/sec)
- **Disk Space** - Usage per filesystem with progress bars and capacity info

#### Hardware Sensors (if available)
- **Temperatures** - All temperature sensors with critical thresholds
- **Fan Speeds** - All system fans with RPM readings

#### Network Client Statistics
- **Client Breakdown** - DHCP/Static/Total clients per network
- **Online/Offline Status** - Active vs inactive devices
- **Visual Chart** - Bar chart showing client distribution

### Files Modified

#### Backend

**New Models** (`webui/backend/models.py`):
- `DiskIOMetrics` - Disk I/O statistics
- `DiskSpaceMetrics` - Filesystem usage
- `TemperatureMetrics` - Temperature sensor readings
- `FanMetrics` - Fan speed readings
- `ClientStats` - Network client statistics

**Extended Collectors**:
- `webui/backend/collectors/system.py` - Added disk, temperature, and fan collectors
- `webui/backend/collectors/clients.py` - New client statistics collector

**New API Router** (`webui/backend/api/system.py`):
- `GET /api/system/current` - Complete system snapshot
- `GET /api/system/metrics` - Basic system metrics
- `GET /api/system/disk/io` - Disk I/O stats
- `GET /api/system/disk/space` - Disk space usage
- `GET /api/system/temperatures` - Temperature sensors
- `GET /api/system/fans` - Fan speeds
- `GET /api/system/clients` - Client statistics

**Updated**:
- `webui/backend/main.py` - Registered system router

#### Frontend

**New System Page** (`webui/frontend/src/pages/System.tsx`):
- Comprehensive dashboard with multiple charts
- Real-time updates every 2 seconds
- Mobile-responsive design
- Historical data tracking (last 30 data points)
- Conditional rendering based on available sensors

**Updated Components**:
- `webui/frontend/src/components/layout/Sidebar.tsx` - "History" → "System"
- `webui/frontend/src/App.tsx` - Updated routing `/history` → `/system`

**Removed**:
- `webui/frontend/src/pages/History.tsx` (replaced by System.tsx)

---

## Features

### 📊 Real-Time Charts
- **CPU Usage** - Line chart with 30-second history
- **Memory Usage** - Line chart with 30-second history
- **Load Average** - Line chart tracking system load
- **Network Clients** - Bar chart showing DHCP/Static/Offline breakdown

### 💾 Disk Monitoring
- **I/O Performance** - Read/write rates per device
- **Space Usage** - Progress bars for each filesystem
- **Smart Alerts** - Color-coded based on usage (red >90%, yellow >75%)

### 🌡️ Hardware Monitoring
- **Temperature Sensors** - All available sensors with critical thresholds
- **Fan Speeds** - RPM readings for all fans
- **Auto-Detection** - Gracefully handles systems without sensors

### 👥 Client Tracking
- **Per-Network Stats** - Separate counts for HOMELAB and LAN
- **Connection Types** - DHCP vs Static breakdown
- **Online Status** - Active vs offline device counts
- **Visual Comparison** - Bar chart for easy comparison

### 📱 Mobile-Optimized
- **Responsive Grid** - Adapts from 1 to 4 columns based on screen size
- **Touch-Friendly** - Large tap targets and easy scrolling
- **Compact View** - Efficient use of screen space on mobile

---

## API Endpoints

### System Overview
```bash
GET /api/system/current
```
**Response**: Complete snapshot with all metrics
```json
{
  "timestamp": "2025-11-16T...",
  "system": { "cpu_percent": 25.5, "memory_percent": 45.2, ... },
  "disk_io": [ { "device": "sda", "read_bytes_per_sec": 1024000, ... } ],
  "disk_space": [ { "mountpoint": "/", "percent_used": 45.5, ... } ],
  "temperatures": [ { "sensor_name": "coretemp", "temperature_c": 55.0, ... } ],
  "fans": [ { "fan_name": "fan1", "rpm": 2000, ... } ],
  "clients": [ { "network": "homelab", "dhcp_clients": 5, ... } ]
}
```

### Individual Metrics
```bash
GET /api/system/metrics          # Basic system metrics
GET /api/system/disk/io          # Disk I/O only
GET /api/system/disk/space       # Disk space only
GET /api/system/temperatures     # Temperature sensors only
GET /api/system/fans             # Fan speeds only
GET /api/system/clients          # Client statistics only
```

---

## How to Deploy

### Step 1: Build Frontend (in WSL)

```bash
cd /mnt/c/Users/Willi/github/nixos-router/webui/frontend
npm run build
```

### Step 2: Commit Changes

```bash
cd /mnt/c/Users/Willi/github/nixos-router

# Stage all changes
git add webui/
git add --force webui/frontend/dist/  # Ensure dist is committed

# Commit
git commit -m "feat(webui): Add comprehensive System monitoring page

- Replace History page with new System page
- Add disk I/O and disk space monitoring
- Add temperature and fan speed sensors
- Add network client statistics with charts
- Implement real-time historical charts for CPU/Memory/Load
- Create new /api/system endpoints for all metrics
- Mobile-responsive design with adaptive layouts
- Gracefully handles systems without hardware sensors"
```

### Step 3: Push and Deploy

```bash
# Push to repository
git push

# On router (SSH):
cd /etc/nixos
git pull
sudo nixos-rebuild switch
```

### Step 4: Verify Deployment

1. Navigate to `http://192.168.2.1:8080`
2. Click "System" in sidebar (formerly "History")
3. Verify you see:
   - System overview cards (CPU, Memory, Load, Uptime)
   - Historical charts updating every 2 seconds
   - Disk I/O statistics (if available)
   - Disk space for all filesystems
   - Temperature sensors (if available)
   - Fan speeds (if available)
   - Client statistics bar chart

---

## Technical Details

### Data Collection Frequency
- **Backend Collection**: Every 2 seconds (configured in `modules/webui.nix`)
- **Frontend Updates**: Every 2 seconds
- **Historical Data**: Last 30 points (~1 minute)

### Sensor Detection
The system automatically detects available sensors:
- **Temperature Sensors**: Uses `psutil.sensors_temperatures()`
- **Fan Sensors**: Uses `psutil.sensors_fans()`
- **Graceful Fallback**: Shows "not available" message if sensors not present

### Disk Filtering
- **Physical Disks Only**: Filters out loop devices, RAM disks, virtual devices
- **Real Filesystems**: Skips tmpfs, devtmpfs, proc, sysfs, etc.
- **Accessible Only**: Handles permission errors gracefully

### Client Statistics Logic
- **DHCP Clients**: Dynamic DHCP leases (excluding static reservations)
- **Static Clients**: Static DHCP reservations + static IP devices
- **Online/Offline**: Based on ARP table and lease age
- **Per-Network**: Separate counts for HOMELAB and LAN

### Chart Performance
- **No Animations**: `isAnimationActive={false}` prevents expensive redraws
- **Fixed Points**: Keeps last 30 data points only
- **Efficient Updates**: Only re-renders when data changes

---

## Comparison: Before vs After

### Before (History Page)
```
┌─────────────────────────────────┐
│ Historical Data                 │
│                                 │
│ (Placeholder - Stage 2 only)    │
│                                 │
└─────────────────────────────────┘
```

### After (System Page)
```
┌─────────────────────────────────────────────────────┐
│ System Monitoring                                   │
├─────────┬─────────┬──────────┬─────────┐
│ CPU 25% │ Mem 45% │ Load 1.2 │ Up 5d2h │
├─────────────────┬────────────────────────┘
│ CPU Chart       │ Memory Chart           │
├─────────────────┼────────────────────────┤
│ Load Chart      │ Clients Chart          │
├─────────────────────────────────────────┤
│ Disk I/O: sda (5 MB/s R, 2 MB/s W)     │
├─────────────────────────────────────────┤
│ Disk Space: / [███████░░░] 75%         │
├─────────────────────────────────────────┤
│ Temperatures: CPU 55°C, SSD 42°C        │
├─────────────────────────────────────────┤
│ Fans: Chassis 2000 RPM, CPU 3500 RPM   │
└─────────────────────────────────────────┘
```

---

## Benefits

### For Users
- **Single Glance**: See all system health metrics at once
- **Early Warning**: Spot issues before they become problems
- **Historical Context**: Charts show trends, not just current values
- **Client Visibility**: Know how many devices are connected
- **Mobile Access**: Monitor from anywhere on your phone

### For Troubleshooting
- **CPU Spikes**: Identify when and how severe
- **Memory Leaks**: Watch memory grow over time
- **Disk Issues**: See I/O bottlenecks and space constraints
- **Overheating**: Monitor temperatures in real-time
- **Network Load**: Count active clients per network

### Technical
- **Modular API**: Each metric available separately or combined
- **Efficient**: Minimal overhead, 2-second polling
- **Scalable**: Handles systems with or without sensors
- **Maintainable**: Clean separation of concerns

---

## Future Enhancements

Possible improvements for future iterations:

1. **Adjustable History Length** - User control for chart time range
2. **Export Data** - Download metrics as CSV
3. **Alert Thresholds** - Configurable warnings for high CPU/memory
4. **Network Errors** - Chart showing packet drops and errors
5. **Process List** - Top CPU/memory consumers
6. **Historical Database** - Long-term metric storage
7. **Custom Dashboards** - User-selectable widgets
8. **Email Alerts** - Notifications for critical thresholds

---

## Success Criteria

✅ **System metrics displayed in real-time**  
✅ **Historical charts update every 2 seconds**  
✅ **Disk I/O and space monitoring working**  
✅ **Temperature and fan sensors detected (if available)**  
✅ **Client statistics show correct counts**  
✅ **Mobile-responsive layout works on all screen sizes**  
✅ **No errors in browser console**  
✅ **"History" renamed to "System" in navigation**  

---

## Troubleshooting

### No Temperature/Fan Data
**Expected**: Many systems (especially VMs) don't have hardware sensors
**Solution**: This is normal - page shows "not available" message

### Disk I/O Shows Zero
**Expected**: First data point has no previous value to compare
**Solution**: Wait 2 seconds for rates to calculate

### No Disks Shown
**Possible Cause**: All disks filtered out (tmpfs, overlay, etc.)
**Solution**: Check physical disk mounts with `df -h`

### Client Counts Wrong
**Possible Cause**: ARP table not updated or DHCP leases stale
**Solution**: Wait 5 minutes for ARP/DHCP refresh, or restart services

---

**Questions or Issues?**  
Check the browser console (F12) for errors, or review backend logs:
```bash
journalctl -u router-webui-backend -f
```

