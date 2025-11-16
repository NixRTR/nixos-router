# System Page Redesign

**Date**: November 16, 2025  
**Status**: ✅ Ready to Deploy  
**Scope**: Complete redesign of System monitoring page

---

## What Changed

### Major Redesign
The System page has been completely redesigned based on user requirements for better clarity and organization.

### New Layout Order

1. **Time Range Selector** - At top of page (10m to 1d, plus custom)
2. **CPU Usage Chart** - Current value in footer
3. **Memory Usage Chart** - Current value + used/total in footer
4. **Load Average Chart** - Current 1m, 5m, 15m values in footer
5. **Disk I/O Charts** - One chart per physical disk with Read/Write lines
6. **Temperature Charts** - One chart per sensor with common names
7. **Network Clients** - Text display (not chart)

### Key Features

#### ⏱️ Adjustable Time Window
- **Default**: 30 minutes
- **Presets**: 10m, 30m, 1h, 3h, 6h, 12h, 1d
- **Custom**: User can enter any range (e.g., "45m", "2h", "1d")
- **Auto-cleanup**: Historical data automatically filtered to time range

#### 📊 Chart Design
- **Charts only for**: CPU, Memory, Load, Disk I/O, Temperatures
- **No animations**: `isAnimationActive={false}` for performance
- **Current values**: Displayed in chart footer
- **Clean lines**: No dots, smooth 2px lines
- **Y-axis labels**: Proper units (%, MB/s, °C)

#### 💾 Disk I/O
- **Physical disks only**: Filters out partitions (sda1, sda2, etc.)
- **Combined chart**: Read and Write on same chart
- **Separate charts**: One chart per physical disk
- **Friendly names**: "Disk SDA", "NVMe nvme0n1"
- **Current values**: Real-time read/write rates in MB/s

#### 🌡️ Temperature Sensors
- **Common names**: Maps technical names to friendly ones
  - `coretemp` → "CPU"
  - `k10temp` → "CPU"
  - `acpitz` → "Motherboard"
  - `nvme` → "NVMe SSD"
  - `drivetemp` → "HDD"
- **Color-coded**: 
  - Green: < 70°C
  - Yellow: 70-80°C
  - Red: > 80°C
- **Individual charts**: One chart per sensor
- **Current value**: Displayed in footer with color coding

#### 👥 Network Clients
- **Text display**: Not a chart
- **Per-network cards**: HOMELAB and LAN separate
- **Statistics shown**:
  - Total clients (badge)
  - DHCP clients
  - Static clients
  - Online (green)
  - Offline (gray)

---

## Removed Features

- ❌ System overview cards (CPU/Memory/Load/Uptime at top)
- ❌ Fan speed display
- ❌ Disk space usage
- ❌ Bar chart for network clients
- ❌ Disk I/O operation counts (only showing bytes/s now)

---

## Technical Details

### Data Storage
```typescript
// Historical data for charts
const [historicalData, setHistoricalData] = useState<HistoricalDataPoint[]>([]);
const [diskIOHistory, setDiskIOHistory] = useState<Map<string, DiskIODataPoint[]>>(new Map());
const [tempHistory, setTempHistory] = useState<Map<string, TempDataPoint[]>>(new Map());
```

### Time Range Filtering
- Stores timestamp with each data point
- Automatically filters old data on each update
- Retains only data within selected time range
- Example: 30 minutes at 2-second intervals = ~900 data points max

### Physical Disk Detection
```typescript
// Skip partitions (devices ending in numbers)
if (disk.device.match(/\d$/)) return;

// Examples:
// ✅ sda, sdb, nvme0n1
// ❌ sda1, sda2, nvme0n1p1
```

### Sensor Name Mapping
```typescript
const nameMap = {
  'coretemp': 'CPU',
  'k10temp': 'CPU',
  'acpitz': 'Motherboard',
  'pch_skylake': 'PCH',
  'iwlwifi_1': 'WiFi',
  'nvme': 'NVMe SSD',
  'drivetemp': 'HDD',
};
```

---

## Before vs After

### Before
```
┌─────────────────────────────────────────┐
│ System Monitoring                       │
├─────────┬─────────┬──────────┬─────────┤
│ CPU 25% │ Mem 45% │ Load 1.2 │ Up 5d2h │  ← Overview cards
├─────────┴─────────┴──────────┴─────────┤
│ CPU Chart       │ Memory Chart         │
├─────────────────┼──────────────────────┤
│ Load Chart      │ Clients Bar Chart    │  ← Bar chart
├─────────────────┴──────────────────────┤
│ Disk I/O: sda (5 MB/s R, 2 MB/s W)     │  ← Text only
│ Disk I/O: sda1 (1 MB/s R, 0.5 MB/s W)  │  ← Included partitions
├─────────────────────────────────────────┤
│ Disk Space: / [███████░░░] 75%         │  ← Removed
├─────────────────────────────────────────┤
│ Temperatures: CPU 55°C, SSD 42°C        │  ← Text only
├─────────────────────────────────────────┤
│ Fans: Chassis 2000 RPM, CPU 3500 RPM   │  ← Removed
└─────────────────────────────────────────┘
```

### After
```
┌─────────────────────────────────────────┐
│ System Monitoring      [30 minutes ▼]   │  ← Time selector
├─────────────────────────────────────────┤
│ CPU Usage                               │
│ [Line Chart]                            │
│ Current: 25.3%                          │  ← Current value
├─────────────────────────────────────────┤
│ Memory Usage                            │
│ [Line Chart]                            │
│ Current: 45.2% (3.6 / 8.0 GB)          │
├─────────────────────────────────────────┤
│ Load Average (1 minute)                 │
│ [Line Chart]                            │
│ Current: 1.20 (5m: 1.15, 15m: 1.10)   │
├─────────────────────────────────────────┤
│ Disk I/O - Disk SDA                     │  ← Physical disk only
│ [Read/Write Line Chart]                 │
│ Current: ↓ 5.23 MB/s / ↑ 2.10 MB/s     │
├─────────────────────────────────────────┤
│ Temperature - CPU                       │  ← Friendly name
│ [Line Chart]                            │
│ Current: 55.0°C                         │  ← Color-coded
├─────────────────────────────────────────┤
│ Temperature - NVMe SSD                  │
│ [Line Chart]                            │
│ Current: 42.0°C                         │
├─────────────────────────────────────────┤
│ Network Clients                         │
│ ┌──────────────┬──────────────┐        │
│ │ HOMELAB      │ LAN          │        │
│ │ 12 Total     │ 8 Total      │        │
│ │              │              │        │
│ │ DHCP: 8      │ DHCP: 5      │        │
│ │ Static: 4    │ Static: 3    │        │
│ │ Online: 10   │ Online: 7    │        │
│ │ Offline: 2   │ Offline: 1   │        │
│ └──────────────┴──────────────┘        │
└─────────────────────────────────────────┘
```

---

## Benefits

### For Monitoring
- **Better Focus**: Charts for what matters most
- **Time Context**: See trends over meaningful time periods
- **Per-Disk View**: Identify bottlenecks on specific disks
- **Temperature Tracking**: Watch for overheating trends
- **Quick Client Count**: See network usage at a glance

### For Troubleshooting
- **Historical Context**: See what happened before the problem
- **Disk Isolation**: Which disk is causing slowdown?
- **Temperature Correlation**: Did issue coincide with high temps?
- **Load Patterns**: Identify usage spikes
- **Network Load**: How many devices were active?

### Technical
- **Memory Efficient**: Auto-cleanup of old data
- **Performance**: No animations, smart updates
- **Scalable**: Works with 0 to many disks/sensors
- **Mobile-Ready**: All charts responsive

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
git add webui/frontend/src/pages/System.tsx
git add webui/frontend/dist/
git add webui/SYSTEM_PAGE_REDESIGN.md

# Commit
git commit -m "feat(webui): Redesign System page with time-based charts

- Add adjustable time window (10m to 1d)
- Show current values in chart footers
- Create separate Disk I/O chart per physical disk (read/write combined)
- Add temperature charts with common sensor names
- Convert network clients to text display (not chart)
- Filter out disk partitions (sda1, etc), show only physical disks
- Auto-filter historical data to selected time range
- Improve chart readability with proper Y-axis labels
- Color-code temperature values (green/yellow/red)
- Order: CPU → Memory → Load → Disk I/O → Temps → Clients"

git push

# On router
cd /etc/nixos && git pull && sudo nixos-rebuild switch
```

### Step 3: Verify

Navigate to `http://192.168.2.1:8080`, click "System":

✅ Time range selector at top  
✅ CPU chart with current value  
✅ Memory chart with current value  
✅ Load chart with current value  
✅ Disk I/O charts (one per physical disk)  
✅ Temperature charts (one per sensor)  
✅ Network clients as text cards  
✅ Charts update every 2 seconds  
✅ Historical data filtered to selected time range  

---

## Success Criteria

✅ **Charts show meaningful history** (not just 30 points)  
✅ **Current values displayed** in chart footers  
✅ **Physical disks only** (no partitions)  
✅ **Friendly sensor names** (CPU, not coretemp)  
✅ **Network clients as text** (not chart)  
✅ **Correct order** (CPU → Mem → Load → Disk → Temp → Clients)  
✅ **Time range adjustable** (10m to 1d)  
✅ **No performance issues** (disabled animations)  
✅ **Mobile responsive** (all charts adapt)  

---

## Troubleshooting

### No Disk I/O Charts
**Cause**: All disks are partitions (sda1, sda2)  
**Solution**: System filters partitions. Check `/proc/diskstats` for physical devices

### Temperature Sensor Names Wrong
**Cause**: Unknown sensor type  
**Solution**: Add mapping in `getSensorName()` function

### Data Not Showing Full Time Range
**Cause**: Not enough data collected yet  
**Solution**: Wait for data to accumulate (e.g., wait 30 min for 30m range)

### Charts Look Cramped on Mobile
**Expected**: Charts are responsive and adapt to screen width  
**Solution**: Use landscape mode for better view on phones

---

**Questions or Issues?**  
Check browser console (F12) for errors, or review backend logs:
```bash
journalctl -u router-webui-backend -f
```

