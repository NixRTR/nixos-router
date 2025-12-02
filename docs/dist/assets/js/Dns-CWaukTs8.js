import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as r}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const n=`# DNS Management\r
\r
Manage DNS zones and records for your router's networks using the WebUI.\r
\r
## Overview\r
\r
The DNS management system allows you to:\r
\r
- **Configure DNS Zones**: Create and manage DNS zones per network (homelab/lan)\r
- **Manage Records**: Add, edit, and delete A and CNAME records\r
- **Control Services**: Start, stop, restart, and reload DNS services\r
- **Monitor Status**: View real-time status of Unbound DNS services\r
- **Authoritative Zones**: Serve zones locally (transparent local-zone)\r
- **Forwarding/Delegation**: Forward zones to specific DNS servers\r
\r
## Accessing DNS Management\r
\r
1. Navigate to the **DNS** page in the WebUI sidebar\r
2. View all configured zones and records\r
3. Filter by network (homelab/lan) or view all\r
\r
## DNS Services\r
\r
The router runs separate DNS services for each network:\r
\r
- **unbound-homelab**: DNS service for the homelab network\r
- **unbound-lan**: DNS service for the LAN network\r
\r
### Service Status\r
\r
Each service displays its current status:\r
\r
- **Running**: Service is active and serving DNS queries\r
- **Stopped**: Service is not running\r
- **Disabled**: Service is not enabled to start automatically\r
\r
### Service Control\r
\r
Control actions available for each service:\r
\r
- **Start**: Start the DNS service\r
- **Stop**: Stop the DNS service\r
- **Restart**: Restart the service (stops and starts)\r
- **Reload**: Reload configuration without restarting\r
\r
**Note**: Service control requires proper authentication and uses a secure socket-activated helper service.\r
\r
## Zones\r
\r
DNS zones are domain names that you want to manage. Each zone is associated with a network (homelab or lan).\r
\r
### Creating a Zone\r
\r
1. Click **New Zone** button\r
2. Enter the zone name (e.g., "example.com")\r
3. Select the network (homelab or lan)\r
4. Configure zone settings:\r
   - **Authoritative**: Serve the zone locally (transparent local-zone)\r
   - **Forward To**: Forward queries for this zone to a specific DNS server (e.g., "192.168.1.1")\r
   - **Delegate To**: Delegate the zone to a specific DNS server (NS records)\r
5. Enable or disable the zone\r
6. Click **Save**\r
\r
### Zone Settings\r
\r
- **Name**: Domain name for the zone (e.g., "example.com", "local")\r
- **Network**: Which network this zone applies to (homelab or lan)\r
- **Authoritative**: When enabled, the zone is served locally as a transparent local-zone\r
- **Forward To**: Optional DNS server IP to forward queries to\r
- **Delegate To**: Optional DNS server IP to delegate the zone to\r
- **Enabled**: Enable or disable the zone\r
\r
### Editing Zones\r
\r
1. Find the zone in the zones list\r
2. Click **Edit** next to the zone\r
3. Modify settings as needed\r
4. Click **Save**\r
\r
### Deleting Zones\r
\r
1. Click **Delete** next to a zone\r
2. Confirm the deletion\r
3. **Note**: Deleting a zone will also delete all records in that zone\r
\r
## Records\r
\r
DNS records define how hostnames resolve to IP addresses or other hostnames.\r
\r
### Record Types\r
\r
- **A Record**: Maps a hostname to an IPv4 address\r
- **CNAME Record**: Maps a hostname to another hostname (alias)\r
\r
### Creating Records\r
\r
1. Find the zone you want to add a record to\r
2. Click **View Records** or **Add Record**\r
3. Enter record details:\r
   - **Name**: Hostname (e.g., "www", "api", "*.example.com")\r
   - **Type**: A or CNAME\r
   - **Value**: \r
     - For A records: IPv4 address (e.g., "192.168.1.10")\r
     - For CNAME records: Target hostname (e.g., "example.com")\r
   - **Comment**: Optional description\r
4. Enable or disable the record\r
5. Click **Save**\r
\r
### Record Examples\r
\r
**A Record:**\r
- Name: \`www\`\r
- Type: \`A\`\r
- Value: \`192.168.1.10\`\r
- Result: \`www.example.com\` → \`192.168.1.10\`\r
\r
**CNAME Record:**\r
- Name: \`api\`\r
- Type: \`CNAME\`\r
- Value: \`example.com\`\r
- Result: \`api.example.com\` → \`example.com\`\r
\r
**Wildcard A Record:**\r
- Name: \`*.example.com\`\r
- Type: \`A\`\r
- Value: \`192.168.1.20\`\r
- Result: Any subdomain of \`example.com\` → \`192.168.1.20\`\r
\r
### Editing Records\r
\r
1. Find the record in the records list\r
2. Click **Edit** next to the record\r
3. Modify settings as needed\r
4. Click **Save**\r
\r
### Deleting Records\r
\r
1. Click **Delete** next to a record\r
2. Confirm the deletion\r
\r
## Network Filtering\r
\r
The DNS page includes a network filter to view zones and records by network:\r
\r
- **All Networks**: Show zones and records for both homelab and lan\r
- **HOMELAB**: Show only homelab network zones and records\r
- **LAN**: Show only lan network zones and records\r
\r
## Automatic Migration\r
\r
On first startup, the WebUI automatically migrates DNS configuration from \`router-config.nix\` to the database:\r
\r
- Zones are extracted from \`homelab.dns\` and \`lan.dns\` configuration\r
- A and CNAME records are parsed and associated with zones\r
- Migration only occurs once (tracked by \`original_config_path\`)\r
\r
After migration, DNS configuration is managed via the WebUI. Changes to \`router-config.nix\` will not affect the database configuration.\r
\r
## Best Practices\r
\r
### Zone Organization\r
\r
- **Use Descriptive Names**: Choose clear zone names that reflect their purpose\r
- **Separate by Network**: Keep homelab and lan zones separate\r
- **Use Subdomains**: Organize services using subdomains (e.g., \`api.example.com\`, \`www.example.com\`)\r
\r
### Record Management\r
\r
- **Use Comments**: Add comments to records to document their purpose\r
- **Wildcards Carefully**: Use wildcard records (\`*.example.com\`) sparingly\r
- **Keep Records Updated**: Update records when IP addresses change\r
\r
### Service Management\r
\r
- **Reload After Changes**: Use "Reload" to apply configuration changes without restarting\r
- **Monitor Status**: Check service status regularly to ensure DNS is working\r
- **Test Queries**: Verify DNS resolution after making changes\r
\r
## Troubleshooting\r
\r
### Service Won't Start\r
\r
1. **Check Service Status**: Verify the service exists and is enabled\r
2. **Check Logs**: Review service logs:\r
   \`\`\`bash\r
   journalctl -u unbound-homelab -f\r
   journalctl -u unbound-lan -f\r
   \`\`\`\r
3. **Verify Configuration**: Ensure zones and records are valid\r
\r
### DNS Not Resolving\r
\r
1. **Check Service Status**: Verify the DNS service is running\r
2. **Verify Records**: Check that records are correct and enabled\r
3. **Test Queries**: Use \`dig\` or \`nslookup\` to test resolution:\r
   \`\`\`bash\r
   dig @192.168.1.1 www.example.com\r
   \`\`\`\r
\r
### Records Not Appearing\r
\r
1. **Reload Service**: Use the "Reload" button to apply changes\r
2. **Check Zone**: Verify the record is in the correct zone\r
3. **Verify Enabled**: Ensure the record is enabled\r
\r
### Migration Issues\r
\r
1. **Check Logs**: Review migration logs in system logs:\r
   \`\`\`bash\r
   journalctl -u router-webui-backend | grep -i dns\r
   \`\`\`\r
2. **Verify Config**: Ensure \`router-config.nix\` has valid DNS configuration\r
3. **Manual Migration**: If needed, manually add zones and records via WebUI\r
\r
## API Usage\r
\r
You can also manage DNS zones and records programmatically via the REST API:\r
\r
### List Zones\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dns/zones?network=homelab \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Create Zone\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dns/zones \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "name": "example.com",\r
    "network": "homelab",\r
    "authoritative": true,\r
    "enabled": true\r
  }'\r
\`\`\`\r
\r
### List Records\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dns/zones/1/records \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Create Record\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dns/zones/1/records \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "name": "www",\r
    "type": "A",\r
    "value": "192.168.1.10",\r
    "comment": "Web server",\r
    "enabled": true\r
  }'\r
\`\`\`\r
\r
### Control Service\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/dns/service/homelab/restart \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Get Service Status\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/dns/service-status/homelab \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
## Additional Resources\r
\r
- [Unbound Documentation](https://nlnetlabs.nl/documentation/unbound/)\r
- [DNS Record Types](https://en.wikipedia.org/wiki/List_of_DNS_record_types)\r
\r
`;function i(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(r,{content:n})})})}export{i as Dns};
