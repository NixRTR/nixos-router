import { MarkdownContent } from '../../components/MarkdownContent';

const devicesContent = `# Devices

![Devices Page](../screenshots/005-devices.webp)

## Overview

The Devices page shows all devices connected to your router's networks, allowing you to view, manage, and organize them.

## Filters

**Purpose**: Quickly find specific devices from potentially large lists.

**Features**:
- **Search by Name**: Filter devices by hostname or custom name
- **Search by IP**: Filter by IP address
- **Search by MAC**: Filter by MAC address
- **Network Filter**: Show devices from specific networks (LAN, Homelab, etc.)

**How to Use**: Type in any of the search boxes to filter the device list in real-time. Filters work together (AND logic) - you can combine multiple filters to narrow down results.

## Favorites

**Purpose**: Mark important devices for quick access.

**Features**:
- **Star Icon**: Click the star icon next to any device to favorite/unfavorite it
- **Favorites First**: Favorite devices appear at the top of the list
- **Persistent**: Favorites are saved in the database and persist across sessions

**How to Use**: Click the star icon (⭐) next to any device name to mark it as a favorite. Click again to unfavorite.

## Edit Name

**Purpose**: Assign custom names to devices for easier identification.

**Features**:
- **Custom Names**: Override the default hostname with a friendly name
- **Persistent Storage**: Custom names are saved in the database
- **Display Priority**: Custom names take precedence over hostnames

**How to Use**: 
1. Click the edit icon (pencil) next to a device name
2. Enter your desired name
3. Press Enter or click outside to save
4. The custom name will be displayed instead of the hostname

## Labels

**Purpose**: Add descriptive tags to devices for organization.

**Features**:
- **Multiple Labels**: Add multiple labels to a single device
- **Color-Coded**: Labels can have different colors for visual organization
- **Filter by Label**: Use labels to filter and organize devices

**How to Use**: 
1. Click the label icon or "Add Label" button
2. Enter a label name
3. Optionally select a color
4. Labels appear as badges next to the device name

## Actions

**Purpose**: Perform actions on devices.

**Features**:
- **View Details**: Navigate to detailed device usage page
- **View Charts**: See bandwidth charts for the device
- **Block Device**: Temporarily block a device from the network

## Data Source

Device information is collected from multiple sources:
- **DHCP Leases**: Active DHCP leases from Kea DHCP server
- **ARP Table**: MAC-to-IP mappings from the system ARP table
- **Network Scans**: Periodic network discovery scans
- **Manual Entries**: Devices you manually add or configure

Data is collected every 5 seconds and stored in the database. The system handles IP address changes and MAC address reassignments automatically.
`;

export function Devices() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={devicesContent} />
      </div>
    </div>
  );
}

