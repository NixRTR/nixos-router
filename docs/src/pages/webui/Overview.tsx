import { MarkdownContent } from '../../components/MarkdownContent';

const overviewContent = `# WebUI Overview

## Introduction

The NixOS Router includes a comprehensive web-based user interface (WebUI) for monitoring and managing your router. The WebUI provides real-time monitoring, historical data analysis, and device management capabilities through an intuitive, modern interface.

## Features

The WebUI provides the following key features:

### Real-Time Monitoring
- **System Resources**: CPU, memory, disk, and temperature monitoring
- **Network Bandwidth**: Per-interface bandwidth statistics and charts
- **Service Status**: Monitor critical router services
- **Device Tracking**: View all connected devices and their activity

### Historical Analysis
- **Time-Based Charts**: View trends over hours, days, weeks, or months
- **Data Aggregation**: Efficient storage and retrieval of historical metrics
- **Speedtest History**: Track internet speed over time

### Device Management
- **Device Organization**: Favorites, custom names, and labels
- **Bandwidth Tracking**: Per-device usage statistics
- **Network Filtering**: Filter devices by network segment

### User Experience
- **Dark Mode**: Comfortable viewing in any lighting condition
- **Responsive Design**: Works on desktop, tablet, and mobile devices
- **Fast Navigation**: Client-side routing for instant page transitions

## Architecture

### Data Collection

All WebUI data is collected using a unified architecture:

1. **Collectors**: Python modules that gather data from various sources:
   - \`psutil\` for system and network metrics
   - \`systemctl\` for service status
   - DHCP lease files for device information
   - Netfilter connection tracking for bandwidth per device

2. **WebSocket**: Real-time data is pushed to connected clients via WebSocket connections for live updates

3. **Database**: All metrics are stored in PostgreSQL for historical analysis:
   - Real-time data: 5-second intervals, retained for 24 hours
   - Aggregated data: 1-minute, 5-minute, and 1-hour aggregates for long-term storage
   - Speedtest results: Stored indefinitely

4. **API**: RESTful API provides access to historical and real-time data

### Update Frequency

- **Real-Time Metrics**: Collected every 5 seconds
- **Chart Updates**: Refreshed every 30 seconds
- **Service Status**: Checked every 5 seconds
- **Device Information**: Updated every 5 seconds

## Pages Overview

### [Login](/webui/login)
Authentication page using your router's system password.

### [Navigation](/webui/navigation)
Learn about the navbar, sidebar, and dark mode features.

### [Dashboard](/webui/dashboard)
Overview page showing system resources, network interfaces, and service status at a glance.

### [Network](/webui/network)
Detailed bandwidth monitoring with historical charts for all network interfaces.

### [Devices](/webui/devices)
View and manage all devices connected to your router's networks with filtering, favorites, and labels.

### [Device Usage](/webui/device-usage)
Per-device bandwidth consumption statistics with sorting and filtering options.

### [System](/webui/system)
System resource monitoring with historical charts for CPU, memory, disk I/O, and temperature.

### [Speedtest](/webui/speedtest)
Run internet speed tests and view historical results with charts and detailed tables.

### [System Info](/webui/system-info)
Detailed system information including OS version, hardware specs, network configuration, and service status.

### [Apprise](/webui/apprise)
Send notifications to 80+ services including email, Discord, Slack, Telegram, Home Assistant, and more.

### [Notifications](/webui/notifications)
Create automated alert rules based on monitored parameters. Set thresholds for CPU, memory, network, temperature, services, and disk usage with custom Jinja2 message templates.

## Getting Started

1. **Access the WebUI**: Navigate to your router's IP address (default: \`http://192.168.2.1:8080\`)
2. **Login**: Use your router's system password to authenticate
3. **Explore**: Start with the Dashboard to get an overview, then explore other pages as needed
4. **Customize**: Set up favorites, custom names, and labels for your devices
5. **Monitor**: Use the charts and historical data to understand your network usage patterns

## Data Privacy

All data collected by the WebUI is stored locally on your router:
- No data is sent to external servers
- All metrics are stored in a local PostgreSQL database
- Historical data can be purged by clearing the database if needed
- Device information is only stored for devices that connect to your networks

## Browser Compatibility

The WebUI is designed to work with modern browsers:
- Chrome/Edge (recommended)
- Firefox
- Safari
- Opera

JavaScript must be enabled for the WebUI to function properly.
`;

export function Overview() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={overviewContent} />
      </div>
    </div>
  );
}

