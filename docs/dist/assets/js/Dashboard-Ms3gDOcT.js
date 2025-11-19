import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const a=`# Dashboard

![Dashboard](../screenshots/002-dashboard.webp)

## Overview

The Dashboard provides a comprehensive overview of your router's current status at a glance. It displays system resources, network interfaces, and service status in an easy-to-read format.

## System Resources

**Purpose**: Monitor the router's hardware utilization in real-time.

**Features**:
- **CPU Usage**: Current CPU utilization percentage
- **Memory Usage**: Current RAM usage with total and available memory
- **Disk Usage**: Storage utilization for the root filesystem
- **Load Average**: System load averages (1m, 5m, 15m)

**How to Use**: The metrics update automatically every few seconds. Values are color-coded:
- Green: Normal operation
- Yellow: Moderate usage
- Red: High usage (may indicate issues)

**Data Source**: Collected via \`psutil\` Python library, which reads directly from the Linux kernel's \`/proc\` filesystem. Data is collected every 5 seconds and stored in the database.

## Network Interfaces

**Purpose**: View real-time bandwidth statistics for all network interfaces.

**Features**:
- **Interface Status**: Shows which interfaces are up/down
- **Current Speed**: Real-time download and upload speeds
- **Total Traffic**: Cumulative bytes sent/received since interface came up

**How to Use**: Click on any interface to view detailed historical charts. The interface list updates automatically as network conditions change.

**Data Source**: Collected via \`psutil\` by reading network interface statistics from \`/proc/net/dev\`. Data is collected every 5 seconds and stored in the database.

## Services

**Purpose**: Monitor the status of critical router services.

**Features**:
- **Network Services**: DHCP, DNS, PPPoE, Dynamic DNS
- **WebUI Services**: Nginx, Backend API, PostgreSQL, Speedtest
- **Service Status**: Running, Stopped, Disabled, or Not Found
- **Resource Usage**: PID, CPU %, and Memory (MB) for each running service

**How to Use**: 
- Services are organized into two columns: "Network Services" and "WebUI Services"
- Status badges indicate the current state:
  - **Green (Running)**: Service is active
  - **Red (Stopped)**: Service is enabled but not running
  - **Gray (Disabled)**: Service is disabled
  - **Gray (Not Found)**: Service unit file doesn't exist
- For one-shot services like Speedtest, status can be "Running", "Waiting", or "Disabled"

**Data Source**: Collected via \`systemctl\` commands to check service status and \`psutil\` to get process resource usage. Data is collected every 5 seconds.
`;function n(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:a})})})}export{n as Dashboard};
