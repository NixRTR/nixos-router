# DHCP Management

Manage DHCP networks and static reservations for your router's networks using the WebUI.

## Overview

The DHCP management system allows you to:

- **Configure DHCP Networks**: Set up DHCP for homelab and lan networks
- **Manage Static Reservations**: Assign fixed IP addresses to devices by MAC address
- **Control Service**: Start, stop, restart, and reload the DHCP server
- **Monitor Status**: View real-time status of the Kea DHCP server

## Accessing DHCP Management

1. Navigate to the **DHCP** page in the WebUI sidebar
2. View all configured networks and reservations
3. Filter by network (homelab/lan) or view all

## DHCP Service

The router runs a single DHCP server (Kea DHCP) that serves all networks:

- **kea-dhcp4-server**: DHCP server for all networks

### Service Status

The service displays its current status:

- **Running**: Service is active and serving DHCP requests
- **Stopped**: Service is not running
- **Disabled**: Service is not enabled to start automatically

### Service Control

Control actions available for the DHCP server:

- **Start**: Start the DHCP server
- **Stop**: Stop the DHCP server
- **Restart**: Restart the service (stops and starts)
- **Reload**: Reload configuration without restarting

**Note**: Service control requires proper authentication and uses a secure socket-activated helper service.

## Networks

DHCP networks define the IP address ranges and settings for each network (homelab or lan).

### Creating a Network

1. Click **New Network** button
2. Select the network (homelab or lan)
3. Configure network settings:
   - **Enabled**: Enable or disable DHCP for this network
   - **Start IP**: First IP address in the range (e.g., "192.168.1.100")
   - **End IP**: Last IP address in the range (e.g., "192.168.1.200")
   - **Lease Time**: How long IP addresses are leased (e.g., "1h", "12h", "1d")
   - **DNS Servers**: Comma-separated list of DNS server IPs (e.g., "192.168.1.1,8.8.8.8")
   - **Dynamic DNS Domain**: Optional domain name for dynamic DNS updates
4. Click **Save**

### Network Settings

- **Network**: Which network this configuration applies to (homelab or lan)
- **Enabled**: Enable or disable DHCP for this network
- **Start IP**: First IP address in the DHCP range
- **End IP**: Last IP address in the DHCP range
- **Lease Time**: Duration of IP address leases (format: "1h", "12h", "1d", etc.)
- **DNS Servers**: DNS servers to provide to clients (comma-separated)
- **Dynamic DNS Domain**: Domain name for dynamic DNS updates (optional)

### Editing Networks

1. Find the network in the networks list
2. Click **Edit** next to the network
3. Modify settings as needed
4. Click **Save**

### Deleting Networks

1. Click **Delete** next to a network
2. Confirm the deletion
3. **Note**: Deleting a network will also delete all static reservations for that network

## Static Reservations

Static reservations assign fixed IP addresses to specific devices based on their MAC address.

### Creating a Reservation

1. Find the network you want to add a reservation to
2. Click **View Reservations** or **Add Reservation**
3. Enter reservation details:
   - **Hostname**: Name for the device (e.g., "server-01", "printer")
   - **MAC Address**: Device MAC address (e.g., "aa:bb:cc:dd:ee:ff")
   - **IP Address**: Fixed IP address to assign (e.g., "192.168.1.10")
   - **Comment**: Optional description
4. Enable or disable the reservation
5. Click **Save**

### Reservation Examples

**Server Reservation:**
- Hostname: `server-01`
- MAC Address: `aa:bb:cc:dd:ee:ff`
- IP Address: `192.168.1.10`
- Result: Device with MAC `aa:bb:cc:dd:ee:ff` always gets `192.168.1.10`

**Printer Reservation:**
- Hostname: `printer-office`
- MAC Address: `11:22:33:44:55:66`
- IP Address: `192.168.1.50`
- Result: Printer always gets `192.168.1.50`

### Editing Reservations

1. Find the reservation in the reservations list
2. Click **Edit** next to the reservation
3. Modify settings as needed
4. Click **Save**

### Deleting Reservations

1. Click **Delete** next to a reservation
2. Confirm the deletion

## Network Filtering

The DHCP page includes a network filter to view networks and reservations by network:

- **All Networks**: Show networks and reservations for both homelab and lan
- **HOMELAB**: Show only homelab network configuration
- **LAN**: Show only lan network configuration

## Automatic Migration

On first startup, the WebUI automatically migrates DHCP configuration from `router-config.nix` to the database:

- Networks are extracted from `homelab.dhcp` and `lan.dhcp` configuration
- Static reservations are parsed and associated with networks
- Migration only occurs once (tracked by `original_config_path`)

After migration, DHCP configuration is managed via the WebUI. Changes to `router-config.nix` will not affect the database configuration.

## Best Practices

### Network Configuration

- **IP Range Sizing**: Allocate enough IPs for your devices (consider growth)
- **Lease Times**: 
  - Short leases (1h-6h) for networks with many transient devices
  - Long leases (12h-1d) for stable networks
- **DNS Servers**: Provide reliable DNS servers (router IP + upstream)

### Static Reservations

- **Use Descriptive Hostnames**: Choose clear names that identify the device
- **Document Reservations**: Use comments to document device purpose
- **Avoid Conflicts**: Ensure reserved IPs are outside the DHCP range
- **Keep Updated**: Update reservations when devices change

### Service Management

- **Reload After Changes**: Use "Reload" to apply configuration changes without restarting
- **Monitor Status**: Check service status regularly to ensure DHCP is working
- **Test Leases**: Verify devices receive IPs after making changes

## Troubleshooting

### Service Won't Start

1. **Check Service Status**: Verify the service exists and is enabled
2. **Check Logs**: Review service logs:
   ```bash
   journalctl -u kea-dhcp4-server -f
   ```
3. **Verify Configuration**: Ensure networks and reservations are valid

### Devices Not Getting IPs

1. **Check Service Status**: Verify the DHCP server is running
2. **Verify Network Enabled**: Ensure the network is enabled
3. **Check IP Range**: Verify the IP range is correct and not exhausted
4. **Check Reservations**: Ensure static reservations don't conflict

### Static Reservations Not Working

1. **Verify MAC Address**: Ensure the MAC address is correct (format: `aa:bb:cc:dd:ee:ff`)
2. **Check IP Conflict**: Ensure the reserved IP is not in use
3. **Reload Service**: Use the "Reload" button to apply changes
4. **Verify Enabled**: Ensure the reservation is enabled

### Migration Issues

1. **Check Logs**: Review migration logs in system logs:
   ```bash
   journalctl -u router-webui-backend | grep -i dhcp
   ```
2. **Verify Config**: Ensure `router-config.nix` has valid DHCP configuration
3. **Manual Migration**: If needed, manually add networks and reservations via WebUI

## API Usage

You can also manage DHCP networks and reservations programmatically via the REST API:

### List Networks

```bash
curl -X GET http://router-ip:8080/api/dhcp/networks?network=homelab \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Network

```bash
curl -X POST http://router-ip:8080/api/dhcp/networks \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "network": "homelab",
    "enabled": true,
    "start": "192.168.1.100",
    "end": "192.168.1.200",
    "lease_time": "12h",
    "dns_servers": "192.168.1.1,8.8.8.8"
  }'
```

### List Reservations

```bash
curl -X GET http://router-ip:8080/api/dhcp/reservations?network=homelab \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Reservation

```bash
curl -X POST http://router-ip:8080/api/dhcp/reservations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "network": "homelab",
    "hostname": "server-01",
    "mac_address": "aa:bb:cc:dd:ee:ff",
    "ip_address": "192.168.1.10",
    "comment": "Main server",
    "enabled": true
  }'
```

### Control Service

```bash
curl -X POST http://router-ip:8080/api/dhcp/service/restart \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Get Service Status

```bash
curl -X GET http://router-ip:8080/api/dhcp/service-status \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Additional Resources

- [Kea DHCP Documentation](https://kea.readthedocs.io/)
- [DHCP Protocol](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol)

