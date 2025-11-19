import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const s=`# Speedtest

![Speedtest Page](../screenshots/009-speedtest.webp)

## Overview

The Speedtest page allows you to run internet speed tests and view historical results with detailed charts and tables.

## Run Speedtest Button

**Purpose**: Manually trigger a new speed test.

**Features**:
- **One-Click Testing**: Start a speed test with a single click
- **Real-Time Progress**: See test progress with live updates
- **Automatic Storage**: Results are automatically saved to the database
- **Visual Feedback**: Metrics pulse with glow effects while waiting for results

**How to Use**: 
1. Click the "Run Speedtest" button at the top of the page
2. Watch the real-time progress as the test runs
3. Results are displayed immediately when complete
4. Results are automatically saved and appear in charts and tables

**What Happens**:
- The test measures ping (latency), download speed, and upload speed
- Progress is shown with pulsing indicators for each metric
- When complete, results are saved to the database
- All three metrics (Download, Upload, Ping) start as "--" and pulse until their values arrive

## Last Result Display

**Purpose**: Always show the most recent speedtest result prominently.

**Features**:
- **Large Display**: Easy-to-read large text showing download, upload, and ping
- **Timestamp**: Shows when the test was performed
- **Real-Time Updates**: Updates in real-time during active tests
- **Pulsing Indicators**: Metrics pulse with glow effects while waiting for results

**How to Use**: The last result is always visible at the top of the page. During a test, values update in real-time. When complete, the final results remain displayed.

## Time Range

**Purpose**: Control what time period of speedtest results is displayed.

**Features**:
- **Preset Ranges**: 1 hour, 3 hours, 6 hours, 12 hours, 1 day, 1 week, 2 weeks, 1 month, 3 months, 6 months, 1 year
- **Chart Filtering**: Charts show only results within the selected range
- **Table Filtering**: Table shows only results within the selected range

**How to Use**: Select a time range from the dropdown above the chart. Both the chart and table will update to show only results from that period.

## Chart

**Purpose**: Visualize speedtest results over time.

**Features**:
- **Three Metrics**: Download (green), Upload (purple), and Ping (yellow) on separate Y-axes
- **Interactive Tooltips**: Hover over data points to see exact values
- **Time-Based**: X-axis shows time, automatically scaled based on selected range

**How to Use**: 
- Hover over any point to see exact values with units
- Download and Upload use the left Y-axis (Mbps)
- Ping uses the right Y-axis (ms)
- Values are displayed with 2 decimal places

## Pagination

**Purpose**: Navigate through large result sets efficiently.

**Features**:
- **Results Per Page**: Choose 10, 25, 50, 100, or custom (1-200)
- **Page Navigation**: Previous/Next buttons to navigate pages
- **Page Indicator**: Shows current page and total pages

**How to Use**: 
1. Select how many results to show per page
2. Use Previous/Next buttons to navigate
3. The page indicator shows your current position

## Table

**Purpose**: View detailed speedtest results in a tabular format.

**Features**:
- **Sortable Columns**: Click headers to sort
- **Detailed Information**: Timestamp, Download, Upload, Ping, Server
- **Filtered by Time Range**: Only shows results within selected time period

**How to Use**: 
- Scroll through results to see historical data
- Use pagination to navigate through large result sets
- Results are sorted by timestamp (newest first)

## Data Source

Speedtest data is collected by:
- **Ookla Speedtest CLI**: Uses the official Ookla speedtest-cli tool
- **Real-Time Parsing**: Output is parsed line-by-line for live updates
- **Database Storage**: Results are stored in PostgreSQL with timestamp, download, upload, and ping values

Tests can be triggered:
- **Manually**: Via the "Run Speedtest" button
- **Automatically**: Via systemd timer (default: hourly)
- **On Boot**: After WAN connection is established

All results are stored in the database and available for historical analysis. The system automatically parses ping values from various output formats, including the "Hosted by" format.
`;function l(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:s})})})}export{l as Speedtest};
