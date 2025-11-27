import{j as r}from"./ui-vendor-CtbJYEGA.js";import{M as e}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const n=`# DHCP Management\r
\r
Manage DHCP networks and static reservations for your router's networks using the WebUI.\r
\r
## Overview\r
\r
The DHCP management system allows you to:\r
\r
- **Configure DHCP Networks**: Set up DHCP for homelab and lan networks\r
- **Manage Static Reservations**: Assign fixed IP addresses to devices by MAC address\r
- **Control Service**: Start, stop, restart, and reload the DHCP server\r
- **Monitor Status**: View real-time status of the Kea DHCP server\r
\r
## Accessing DHCP Management\r
\r
1. Navigate to the **DHCP** page in the WebUI sidebar\r
2. View all configured networks and reservations\r
3. Filter by network (homelab/lan) or view all\r
\r
## DHCP Service\r
\r
The router runs a single DHCP server (Kea DHCP) that serves all networks:\r
\r
- **kea-dhcp4-server**: DHCP server for all networks\r
\r
### Service Status\r
\r
The service displays its current status:\r
\r
- **Running**: Service is active and serving DHCP requests\r
- **Stopped**: Service is not running\r
- **Disabled**: Service is not enabled to start automatically\r
\r
### Service Control\r
\r
Control actions available for the DHCP server:\r
\r
- **Start**: Start the DHCP server\r
- **Stop**: Stop the DHCP server\r
- **Restart**: Restart the service (stops and starts)\r
- **Reload**: Reload configuration without restarting\r
\r
**Note**: Service control requires proper authentication and uses a secure socket-activated helper service.\r
\r
## Networks\r
\r
DHCP networks define the IP address ranges and settings for each network (homelab or lan).\r
\r
### Creating a Network\r
\r
1. Click **New Network** button\r
2. Select the network (homelab or lan)\r
3. Configure network settings:\r
   - **Enabled**: Enable or disable DHCP for this network\r
   - **Start IP**: First IP address in the range (e.g., "192.168.1.100")\r
   - **End IP**: Last IP address in the range (e.g., "192.168.1.200")\r
   - **Lease Time**: How long IP addresses are leased (e.g., "1h", "12h", "1d")\r
   - **DNS Servers**: Comma-separated list of DNS server IPs (e.g., "192.168.1.1,8.8.8.8")\r
   - **Dynamic DNS Domain**: Optional domain name for dynamic DNS updates\r
4. Click **Save**\r
\r
### Network Settings\r
\r
- **Network**: Which network this configuration applies to (homelab or lan)\r
- **Enabled**: Enable or disable DHCP for this network\r
- **Start IP**: First IP address in the DHCP range\r
- **End IP**: Last IP address in the DHCP range\r
- **Lease Time**: Duration of IP address leases (format: "1h", "12h", "1d", etc.)\r
- **DNS Servers**: DNS servers to provide to clients (comma-separated)\r
- **Dynamic DNS Domain**: Domain name for dynamic DNS updates (optional)\r
\r
### Editing Networks\r
\r
1. Find the network in the networks list\r
2. Click **Edit** next to the network\r
3. Modify settings as needed\r
4. Click **Save**\r
\r
### Deleting Networks\r
\r
1. Click **Delete** next to a network\r
2. Confirm the deletion\r
3. **Note**: Deleting a network will also delete all static reservations for that network\r
\r
## Static Reservations\r
\r
Static reservations assign fixed IP addresses to specific devices based on their MAC address.\r
\r
### Creating a Reservation\r
\r
1. Find the network you want to add a reservation to\r
2. Click **View Reservations** or **Add Reservation**\r
3. Enter reservation details:\r
   - **Hostname**: Name for the device (e.g., "server-01", "printer")\r
   - **MAC Address**: Device MAC address (e.g., "aa:bb:cc:dd:ee:ff")\r
   - **IP Address**: Fixed IP address to assign (e.g., "192.168.1.10")\r
   - **Comment**: Optional description\r
4. Enable or disable the reservation\r
5. Click **Save**\r
\r
### Reservation Examples\r
\r
**Server Reservation:**\r
- Hostname: \`server-01\`\r
- MAC Address: \`aa:bb:cc:dd:ee:ff\`\r
- IP Address: \`192.168.1.10\`\r
- Result: Device with MAC \`aa:bb:cc:dd:ee:ff\` always gets \`192.168.1.10\`\r
\r
**Printer Reservation:**\r
- Hostname: \`printer-office\`\r
- MAC Address: \`11:22:33:44:55:66\`\r
- IP Address: \`192.168.1.50\`\r
- Result: Printer always gets \`192.168.1.50\`\r
\r
### Editing Reservations\r
\r
1. Find the reservation in the reservations list\r
2. Click **Edit** next to the reservation\r
3. Modify settings as needed\r
4. Click **Save**\r
\r
### Deleting Reservations\r
\r
1. Click **Delete** next to a reservation\r
2. Confirm the deletion\r
\r
## Network Filtering\r
\r
The DHCP page includes a network filter to view networks and reservations by network:\r
\r
- **All Networks**: Show networks and reservations for both homelab and lan\r
- **HOMELAB**: Show only homelab network configuration\r
- **LAN**: Show only lan network configuration\r
\r
## Automatic Migration\r
\r
On first startup, the WebUI automatically migrates DHCP configuration from \`router-config.nix\` to the database:\r
\r
- Networks are extracted from \`homelab.dhcp\` and \`lan.dhcp\` configuration\r
- Static reservations are parsed and associated with networks\r
- Migration only occurs once (tracked by \`original_config_path\`)\r
\r
After migration, DHCP configuration is managed via the WebUI. Changes to \`router-config.nix\` will not affect the database configuration.\r
\r
## Best Practices\r
\r
### Network Configuration\r
\r
- **IP Range Sizing**: Allocate enough IPs for your devices (consider growth)\r
- **Lease Times**: \r
  - Short leases (1h-6h) for networks with many transient devices\r
  - Long leases (12h-1d) for stable networks\r
- **DNS Servers**: Provide reliable DNS servers (router IP + upstream)\r
\r
### Static Reservations\r
\r
- **Use Descriptive Hostnames**: Choose clear names that identify the device\r
- **Document Reservations**: Use comments to document device purpose\r
- **Avoid Conflicts**: Ensure reserved IPs are outside the DHCP range\r
- **Keep Updated**: Update reservations when devices change\r
\r
### Service Management\r
\r
- **Reload After Changes**: Use "Reload" to apply configuration changes without restarting\r
- **Monitor Status**: Check service status regularly to ensure DHCP is working\r
- **Test Leases**: Verify devices receive IPs after making changes\r
\r
## Troubleshooting\r
\r
### Service Won't Start\r
\r
1. **Check Service Status**: Verify the service exists and is enabled\r
2. **Check Logs**: Review service logs:\r
   \`\`\`bash\r
   journalctl -u kea-dhcp4-server -f\r
   \`\`\`\r
3. **Verify Configuration**: Ensure networks and reservations are valid\r
\r
### Devices Not Getting IPs\r
\r
1. **Check Service Status**: Verify the DHCP server is running\r
2. **Verify Network Enabled**: Ensure the network is enabled\r
3. **Check IP Range**: Verify the IP range is correct and not exhausted\r
4. **Check Reservations**: Ensure static reservations don't conflict\r
\r
### Static Reservations Not Working\r
\r
1. **Verify MAC Address**: Ensure the MAC address is correct (format: \`aa:bb:cc:dd:ee:ff\`)\r
2. **Check IP Conflict**: Ensure the reserved IP is not in use\r
3. **Reload Service**: Use the "Reload" button to apply changes\r
4. **Verify Enabled**: Ensure the reservation is enabled\r
\r
### Migration Issues\r
\r
1. **Check Logs**: Review migration logs in system logs:\r
   \`\`\`bash\r
   journalctl -u router-webui-backend | grep -i dhcp\r
   \`\`\`\r
2. **Verify Config**: Ensure \`router-config.nix\` has valid DHCP configuration\r
3. **Manual Migration**: If needed, manually add networks and reservations via WebUI\r
\r
## API Usage\r
\r
You can also manage DHCP networks and reservations programmatically via the REST API:\r
\r
### List Networks\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dhcp/networks?network=homelab \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Create Network\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dhcp/networks \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "network": "homelab",\r
    "enabled": true,\r
    "start": "192.168.1.100",\r
    "end": "192.168.1.200",\r
    "lease_time": "12h",\r
    "dns_servers": "192.168.1.1,8.8.8.8"\r
  }'\r
\`\`\`\r
\r
### List Reservations\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dhcp/reservations?network=homelab \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Create Reservation\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dhcp/reservations \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "network": "homelab",\r
    "hostname": "server-01",\r
    "mac_address": "aa:bb:cc:dd:ee:ff",\r
    "ip_address": "192.168.1.10",\r
    "comment": "Main server",\r
    "enabled": true\r
  }'\r
\`\`\`\r
\r
### Control Service\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dhcp/service/restart \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Get Service Status\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dhcp/service-status \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
## Additional Resources\r
\r
- [Kea DHCP Documentation](https://kea.readthedocs.io/)\r
- [DHCP Protocol](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol)\r
\r
`;function i(){return r.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:r.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:r.jsx(e,{content:n})})})}export{i as Dhcp};
