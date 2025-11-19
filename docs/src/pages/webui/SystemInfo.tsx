import { MarkdownContent } from '../../components/MarkdownContent';

const systemInfoContent = `# System Info

![System Info Page](../screenshots/010-system-info.webp)

## Overview

The System Info page displays detailed system information about your router, including OS details, hardware specifications, network configuration, and service status.  It is displayed to mimic the output of fastfetch.

## What's Displayed

### OS Information
- **NixOS Version**: Current NixOS release version
- **Kernel Version**: Linux kernel version and build information
- **System Architecture**: CPU architecture (x86_64, ARM, etc.)
- **Build Date**: When the system was built

### Hardware Information
- **CPU Model**: Processor model and specifications
- **CPU Cores**: Number of CPU cores and threads
- **Memory**: Total installed RAM
- **Disk Information**: Storage devices and their capacities

### Network Configuration
- **Interface Configurations**: All network interfaces and their settings
- **IP Addresses**: Assigned IP addresses for each interface
- **Routing Tables**: Current routing table entries
- **Network Statistics**: Interface statistics and counters

### Service Status
- **All Services**: Status of all configured router services
- **Service Details**: Configuration and runtime information for each service

## How to Use

The System Info page is read-only and displays current system state. Information updates automatically when the page is refreshed.

**Use Cases**:
- **Troubleshooting**: Check system configuration and service status
- **Documentation**: Reference system specifications
- **Verification**: Verify that services are configured correctly

## Data Source

System information is collected from:
- **System Files**: \`/etc/os-release\`, \`/proc/version\`, etc.
- **Hardware Info**: \`/proc/cpuinfo\`, \`/sys/class/dmi/id/\`
- **Network Config**: Current network configuration from systemd-networkd
- **Service Status**: Status of all router services via systemctl

Data is collected on-demand when the page is loaded and represents the current system state at that moment.
`;

export function SystemInfo() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={systemInfoContent} />
      </div>
    </div>
  );
}

