import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const a=`# Device Usage

![Device Usage Page](../screenshots/006-device-usage.webp)

## Overview

The Device Usage page shows bandwidth consumption per device, allowing you to identify which devices are using the most network resources.

## Filters

**Purpose**: Filter devices by various criteria to focus on specific subsets.

**Features**:
- **Network Filter**: Show devices from specific networks
- **Time Range**: Filter by last seen time
- **Traffic Filter**: Filter by minimum traffic threshold

**How to Use**: Use the filter dropdowns at the top of the page to narrow down the device list.

## Sorting

**Purpose**: Organize devices by different metrics.

**Features**:
- **Sortable Columns**: Click column headers to sort
- **Sort Directions**: Click again to reverse sort order
- **Sortable Fields**: Download, Upload, Total Traffic, Last Seen

**How to Use**: Click any column header to sort by that field. Click again to reverse the sort order.

## Fields

**What Each Field Means**:
- **Device Name**: Custom name or hostname of the device
- **IP Address**: Current IP address assigned to the device
- **MAC Address**: Hardware address of the device
- **Download**: Total data downloaded by the device in the selected time period
- **Upload**: Total data uploaded by the device in the selected time period
- **Total**: Combined download + upload traffic
- **Last Seen**: When the device was last active on the network

**How to Use**: Values are displayed in human-readable format (KB, MB, GB). Hover over values to see exact bytes.

## Chart / Details / Disable Buttons

**Purpose**: Access detailed views and controls for each device.

**Features**:
- **Chart Button**: View historical bandwidth charts for the device
- **Details Button**: Navigate to the detailed device page with full information
- **Disable Button**: Temporarily disable bandwidth tracking for the device

**How to Use**: 
- Click "Chart" to see bandwidth trends over time for that device
- Click "Details" to view the full device information page
- Click "Disable" to stop tracking bandwidth for that device (can be re-enabled later)

## Data Source

Device usage data is calculated from:
- **Network Interface Statistics**: Per-interface traffic from \`/proc/net/dev\`
- **Connection Tracking**: Netfilter connection tracking to associate traffic with devices
- **DHCP Lease Information**: To map IP addresses to devices

Data is collected every 5 seconds, aggregated by device, and stored in the database. Historical data is available for analysis and charting.
`;function d(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:a})})})}export{d as DeviceUsage};
