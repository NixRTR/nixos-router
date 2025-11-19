import { MarkdownContent } from '../../components/MarkdownContent';

const networkContent = `# Network

![Network Page](../screenshots/004-network.webp)

## Overview

The Network page provides detailed bandwidth monitoring with historical charts for all network interfaces.

## Time Range and Update Options

**Purpose**: Control what time period of data is displayed and how frequently it updates.

**Features**:
- **Time Range Selector**: Choose from preset ranges (1 hour, 6 hours, 12 hours, 1 day, 1 week, 1 month, 1 year)
- **Auto-Refresh**: Charts automatically update every 30 seconds
- **Manual Refresh**: Click the refresh button to update immediately

**How to Use**: 
- Select a time range from the dropdown at the top of the page
- The charts will automatically adjust to show data for the selected period
- Data refreshes automatically, but you can manually refresh at any time

## Charts

**Purpose**: Visualize network bandwidth trends over time.

**Features**:
- **Per-Interface Charts**: Separate charts for each network interface
- **Download/Upload Lines**: Shows both download (green) and upload (purple) speeds
- **Interactive Tooltips**: Hover over data points to see exact values with units
- **Y-Axis Labels**: Clear labels showing "Mbit/s" units

**What Each Chart Represents**:
- **X-Axis**: Time (automatically scaled based on selected range)
- **Y-Axis**: Bandwidth in Mbit/s
- **Green Line**: Download speed (data received)
- **Purple Line**: Upload speed (data sent)

**How to Use**: 
- Hover over any point on the chart to see exact values
- Values are displayed with 2 decimal places and units (e.g., "123.45 Mbit/s")
- Charts are responsive and adjust to your screen size

**Data Source**: Collected via \`psutil\` by reading network interface statistics from \`/proc/net/dev\`. Data is collected every 5 seconds, aggregated, and stored in the database. Charts query aggregated data for efficient rendering.
`;

export function Network() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={networkContent} />
      </div>
    </div>
  );
}

