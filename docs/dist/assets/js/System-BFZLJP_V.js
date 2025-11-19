import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const s=`# System

![System Page](../screenshots/008-system.webp)

## Overview

The System page provides detailed system monitoring with historical charts for CPU, memory, disk, and temperature.

## Purpose of Each Chart

### CPU Usage Chart

**Purpose**: Monitor processor utilization over time.

**Features**:
- Shows CPU utilization percentage (0-100%)
- Y-axis: Percentage with label
- Interactive tooltips showing exact values with units

**How to Use**: 
- Hover over data points to see exact CPU percentage
- Useful for identifying CPU-intensive periods or processes
- Values are displayed with 2 decimal places (e.g., "45.67%")

**Data Source**: Collected via \`psutil\` from \`/proc/stat\` and \`/proc/cpuinfo\`. Data is collected every 5 seconds.

### Memory Usage Chart

**Purpose**: Monitor RAM usage trends.

**Features**:
- Shows memory utilization percentage (0-100%)
- Y-axis: Percentage with label
- Helps identify memory leaks or high memory usage periods

**How to Use**: 
- Hover over data points to see exact memory percentage
- Monitor for sustained high usage that might indicate issues
- Values are displayed with 2 decimal places (e.g., "78.23%")

**Data Source**: Collected via \`psutil\` from \`/proc/meminfo\`. Data is collected every 5 seconds.

### Load Average Chart

**Purpose**: Monitor system load and resource contention.

**Features**:
- Shows system load averages (1m, 5m, 15m)
- Y-axis: Load value (no unit)
- Indicates system stress and resource contention

**How to Use**: 
- Load average represents the average number of processes waiting for CPU time
- Values above the number of CPU cores indicate system overload
- Three lines show 1-minute, 5-minute, and 15-minute averages

**Data Source**: Collected via \`psutil\` from \`/proc/loadavg\`. Data is collected every 5 seconds.

### Disk I/O Chart

**Purpose**: Monitor disk read/write activity.

**Features**:
- Shows disk read and write speeds
- Y-axis: MB/s with label
- Helps identify disk-intensive operations

**How to Use**: 
- Hover over data points to see exact read/write speeds
- Monitor for high I/O that might slow down the system
- Values are displayed with 2 decimal places and units (e.g., "12.34 MB/s")

**Data Source**: Collected via \`psutil\` from \`/proc/diskstats\`. Data is collected every 5 seconds.

### Temperature Chart

**Purpose**: Monitor CPU/system temperature.

**Features**:
- Shows temperature over time
- Y-axis: Celsius (°C) with label
- Monitors thermal conditions

**How to Use**: 
- Hover over data points to see exact temperature
- Monitor for overheating conditions
- Values are displayed with 2 decimal places and units (e.g., "45.67 °C")

**Data Source**: Collected via \`psutil\` from \`/sys/class/thermal/\` (if available). Data is collected every 5 seconds.

## How to Use

- All charts support interactive tooltips showing exact values with units
- Hover over data points to see precise measurements
- Charts automatically update every 30 seconds
- Use the time range selector to view different periods
- Charts are responsive and adjust to your screen size

## Data Source

System metrics are collected via:
- **psutil Library**: Python library that reads from \`/proc\` filesystem
- **CPU**: \`/proc/stat\` and \`/proc/cpuinfo\`
- **Memory**: \`/proc/meminfo\`
- **Disk**: \`/proc/diskstats\` and filesystem statistics
- **Temperature**: \`/sys/class/thermal/\` (if available)

Data is collected every 5 seconds, stored in the database, and aggregated for efficient chart rendering. Historical data is retained for long-term analysis.
`;function n(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:s})})})}export{n as System};
