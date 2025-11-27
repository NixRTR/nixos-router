# DNS Management

Manage DNS zones and records for your router's networks using the WebUI.

## Overview

The DNS management system allows you to:

- **Configure DNS Zones**: Create and manage DNS zones per network (homelab/lan)
- **Manage Records**: Add, edit, and delete A and CNAME records
- **Control Services**: Start, stop, restart, and reload DNS services
- **Monitor Status**: View real-time status of Unbound DNS services
- **Authoritative Zones**: Serve zones locally (transparent local-zone)
- **Forwarding/Delegation**: Forward zones to specific DNS servers

## Accessing DNS Management

1. Navigate to the **DNS** page in the WebUI sidebar
2. View all configured zones and records
3. Filter by network (homelab/lan) or view all

## DNS Services

The router runs separate DNS services for each network:

- **unbound-homelab**: DNS service for the homelab network
- **unbound-lan**: DNS service for the LAN network

### Service Status

Each service displays its current status:

- **Running**: Service is active and serving DNS queries
- **Stopped**: Service is not running
- **Disabled**: Service is not enabled to start automatically

### Service Control

Control actions available for each service:

- **Start**: Start the DNS service
- **Stop**: Stop the DNS service
- **Restart**: Restart the service (stops and starts)
- **Reload**: Reload configuration without restarting

**Note**: Service control requires proper authentication and uses a secure socket-activated helper service.

## Zones

DNS zones are domain names that you want to manage. Each zone is associated with a network (homelab or lan).

### Creating a Zone

1. Click **New Zone** button
2. Enter the zone name (e.g., "example.com")
3. Select the network (homelab or lan)
4. Configure zone settings:
   - **Authoritative**: Serve the zone locally (transparent local-zone)
   - **Forward To**: Forward queries for this zone to a specific DNS server (e.g., "192.168.1.1")
   - **Delegate To**: Delegate the zone to a specific DNS server (NS records)
5. Enable or disable the zone
6. Click **Save**

### Zone Settings

- **Name**: Domain name for the zone (e.g., "example.com", "local")
- **Network**: Which network this zone applies to (homelab or lan)
- **Authoritative**: When enabled, the zone is served locally as a transparent local-zone
- **Forward To**: Optional DNS server IP to forward queries to
- **Delegate To**: Optional DNS server IP to delegate the zone to
- **Enabled**: Enable or disable the zone

### Editing Zones

1. Find the zone in the zones list
2. Click **Edit** next to the zone
3. Modify settings as needed
4. Click **Save**

### Deleting Zones

1. Click **Delete** next to a zone
2. Confirm the deletion
3. **Note**: Deleting a zone will also delete all records in that zone

## Records

DNS records define how hostnames resolve to IP addresses or other hostnames.

### Record Types

- **A Record**: Maps a hostname to an IPv4 address
- **CNAME Record**: Maps a hostname to another hostname (alias)

### Creating Records

1. Find the zone you want to add a record to
2. Click **View Records** or **Add Record**
3. Enter record details:
   - **Name**: Hostname (e.g., "www", "api", "*.example.com")
   - **Type**: A or CNAME
   - **Value**: 
     - For A records: IPv4 address (e.g., "192.168.1.10")
     - For CNAME records: Target hostname (e.g., "example.com")
   - **Comment**: Optional description
4. Enable or disable the record
5. Click **Save**

### Record Examples

**A Record:**
- Name: `www`
- Type: `A`
- Value: `192.168.1.10`
- Result: `www.example.com` → `192.168.1.10`

**CNAME Record:**
- Name: `api`
- Type: `CNAME`
- Value: `example.com`
- Result: `api.example.com` → `example.com`

**Wildcard A Record:**
- Name: `*.example.com`
- Type: `A`
- Value: `192.168.1.20`
- Result: Any subdomain of `example.com` → `192.168.1.20`

### Editing Records

1. Find the record in the records list
2. Click **Edit** next to the record
3. Modify settings as needed
4. Click **Save**

### Deleting Records

1. Click **Delete** next to a record
2. Confirm the deletion

## Network Filtering

The DNS page includes a network filter to view zones and records by network:

- **All Networks**: Show zones and records for both homelab and lan
- **HOMELAB**: Show only homelab network zones and records
- **LAN**: Show only lan network zones and records

## Automatic Migration

On first startup, the WebUI automatically migrates DNS configuration from `router-config.nix` to the database:

- Zones are extracted from `homelab.dns` and `lan.dns` configuration
- A and CNAME records are parsed and associated with zones
- Migration only occurs once (tracked by `original_config_path`)

After migration, DNS configuration is managed via the WebUI. Changes to `router-config.nix` will not affect the database configuration.

## Best Practices

### Zone Organization

- **Use Descriptive Names**: Choose clear zone names that reflect their purpose
- **Separate by Network**: Keep homelab and lan zones separate
- **Use Subdomains**: Organize services using subdomains (e.g., `api.example.com`, `www.example.com`)

### Record Management

- **Use Comments**: Add comments to records to document their purpose
- **Wildcards Carefully**: Use wildcard records (`*.example.com`) sparingly
- **Keep Records Updated**: Update records when IP addresses change

### Service Management

- **Reload After Changes**: Use "Reload" to apply configuration changes without restarting
- **Monitor Status**: Check service status regularly to ensure DNS is working
- **Test Queries**: Verify DNS resolution after making changes

## Troubleshooting

### Service Won't Start

1. **Check Service Status**: Verify the service exists and is enabled
2. **Check Logs**: Review service logs:
   ```bash
   journalctl -u unbound-homelab -f
   journalctl -u unbound-lan -f
   ```
3. **Verify Configuration**: Ensure zones and records are valid

### DNS Not Resolving

1. **Check Service Status**: Verify the DNS service is running
2. **Verify Records**: Check that records are correct and enabled
3. **Test Queries**: Use `dig` or `nslookup` to test resolution:
   ```bash
   dig @192.168.1.1 www.example.com
   ```

### Records Not Appearing

1. **Reload Service**: Use the "Reload" button to apply changes
2. **Check Zone**: Verify the record is in the correct zone
3. **Verify Enabled**: Ensure the record is enabled

### Migration Issues

1. **Check Logs**: Review migration logs in system logs:
   ```bash
   journalctl -u router-webui-backend | grep -i dns
   ```
2. **Verify Config**: Ensure `router-config.nix` has valid DNS configuration
3. **Manual Migration**: If needed, manually add zones and records via WebUI

## API Usage

You can also manage DNS zones and records programmatically via the REST API:

### List Zones

```bash
curl -X GET http://router-ip:8080/api/dns/zones?network=homelab \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Zone

```bash
curl -X POST http://router-ip:8080/api/dns/zones \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "example.com",
    "network": "homelab",
    "authoritative": true,
    "enabled": true
  }'
```

### List Records

```bash
curl -X GET http://router-ip:8080/api/dns/zones/1/records \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Record

```bash
curl -X POST http://router-ip:8080/api/dns/zones/1/records \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "www",
    "type": "A",
    "value": "192.168.1.10",
    "comment": "Web server",
    "enabled": true
  }'
```

### Control Service

```bash
curl -X POST http://router-ip:8080/api/dns/service/homelab/restart \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Get Service Status

```bash
curl -X GET http://router-ip:8080/api/dns/service-status/homelab \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Additional Resources

- [Unbound Documentation](https://nlnetlabs.nl/documentation/unbound/)
- [DNS Record Types](https://en.wikipedia.org/wiki/List_of_DNS_record_types)

