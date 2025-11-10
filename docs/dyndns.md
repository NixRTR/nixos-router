# Dynamic DNS Configuration

The NixOS router supports automatic Dynamic DNS updates for Linode-hosted domains. When your WAN IP address changes, the router will automatically update your DNS record.

## Features

- **Automatic updates** when WAN IP changes
- **Periodic checks** to ensure DNS stays in sync
- **Boot-time update** to set DNS immediately after connection
- **Low TTL** (30 seconds) for fast propagation
- **State tracking** to avoid unnecessary API calls

## Setup

### 1. Get Linode API Credentials

First, you need to find your Linode domain and record IDs:

```bash
# Install linode-cli (on your local machine or the router)
pip install linode-cli

# Configure with your Linode API token
linode-cli configure

# List your domains to get the DOMAIN_ID
linode-cli domains list

# List DNS records for your domain to get the RECORD_ID
linode-cli domains records-list <DOMAIN_ID>
```

Look for the A record you want to update and note its ID.

### 2. Create Linode API Token

1. Log into the [Linode Cloud Manager](https://cloud.linode.com/)
2. Go to **Profile → API Tokens → Create a Personal Access Token**
3. Give it a label like "Router Dynamic DNS"
4. Set permissions:
   - **Domains**: Read/Write
   - All others can be "None"
5. Click **Create Token** and save it securely

### 3. Configure router-config.nix

Edit `/etc/nixos/router-config.nix` and update the `dyndns` section:

```nix
dyndns = {
  enable = true;  # Enable dynamic DNS
  provider = "linode";
  
  # Your domain configuration
  domain = "example.com";
  subdomain = "";  # Leave empty for root domain (example.com)
                   # Or set to "router" for router.example.com
  
  # From linode-cli commands above
  domainId = 1234567;  # Your domain ID
  recordId = 7654321;  # Your A record ID
  
  # How often to check for IP changes
  checkInterval = "5m";
};
```

### 4. Add API Token to Secrets

Edit your secrets file:

```bash
# Edit secrets with sops
sudo nix shell nixpkgs#sops --command sops /etc/nixos/secrets/secrets.yaml
```

Add the Linode API token:

```yaml
linode-api-token: your-linode-api-token-here
```

Save and exit (`:wq` in vim).

### 5. Rebuild the System

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

## Verification

Check that the service is running:

```bash
# Check service status
sudo systemctl status linode-dyndns.service

# Check timer status
sudo systemctl status linode-dyndns.timer
sudo systemctl list-timers linode-dyndns

# View logs
sudo journalctl -u linode-dyndns -f

# Manually trigger an update
sudo systemctl start linode-dyndns.service
```

## How It Works

The Dynamic DNS module creates three systemd units:

1. **linode-dyndns.service** - The main service that updates DNS
   - Fetches your current public IP from ipify.org
   - Compares with the cached IP and current DNS record
   - Updates DNS via Linode API if changed
   - Stores the IP in `/var/lib/linode-dyndns/last-ip`

2. **linode-dyndns.timer** - Periodic check timer
   - Runs 2 minutes after boot
   - Then runs every `checkInterval` (default: 5 minutes)

3. **linode-dyndns-on-wan-up.service** - Boot trigger
   - Runs when network comes online at boot
   - Ensures DNS is updated immediately

4. **linode-dyndns-wan-trigger.path** - Interface monitor
   - Watches WAN interface state changes
   - Triggers update when interface state changes

## Troubleshooting

### Service fails with "API token file not found"

Make sure you've added `linode-api-token` to your `secrets.yaml` file and rebuilt the system.

```bash
# Verify secret exists
sudo cat /run/secrets/linode-api-token
```

### Service fails with "Failed to get public IP"

The router may not have internet connectivity yet. Check your WAN connection:

```bash
# Test internet connectivity
ping -c 3 8.8.8.8

# Check WAN interface
ip addr show <your-wan-interface>
```

### DNS not updating

Check the service logs for errors:

```bash
sudo journalctl -u linode-dyndns -n 50
```

Manually trigger an update to see detailed output:

```bash
sudo systemctl start linode-dyndns.service
sudo journalctl -u linode-dyndns -f
```

### Wrong domain or record ID

Verify your IDs are correct:

```bash
# List domains
linode-cli domains list

# List records for your domain
linode-cli domains records-list <DOMAIN_ID>
```

Then update the values in `router-config.nix` and rebuild.

## API Rate Limits

Linode's API has rate limits, but with the default `checkInterval` of 5 minutes, you'll only make ~288 API calls per day, well within Linode's limits.

The service is smart about API calls:
- Only checks public IP every interval
- Only calls Linode API if public IP changed
- Caches the last known IP to avoid redundant updates

## Security

- The Linode API token is stored encrypted in `secrets.yaml`
- At runtime, it's available only to root at `/run/secrets/linode-api-token` with 0400 permissions
- The token has minimal permissions (only Domain Read/Write)
- The cached IP file is world-readable but contains no sensitive data

## Multiple Domains

Currently, the module supports one domain per router. If you need to update multiple domains or records, you can:

1. Create multiple A records pointing to the same IP in Linode DNS Manager
2. Use CNAME records to point other domains to your DynDNS domain
3. Or extend the module to support multiple domains (submit a PR!)

## Example Full Configuration

```nix
# router-config.nix
{
  hostname = "gateway";
  timezone = "America/New_York";
  username = "routeradmin";

  wan = {
    type = "dhcp";
    interface = "eno1";
  };

  lan = {
    interfaces = [ "enp1s0" "enp2s0" ];
    ip = "192.168.1.1";
    prefix = 24;
  };

  dhcp = {
    start = "192.168.1.100";
    end = "192.168.1.200";
    leaseTime = "24h";
  };

  portForwards = [ ];

  dyndns = {
    enable = true;
    provider = "linode";
    domain = "myhouse.com";
    subdomain = "router";  # Will update router.myhouse.com
    domainId = 1234567;
    recordId = 7654321;
    checkInterval = "5m";
  };
}
```

This will keep `router.myhouse.com` pointing to your current WAN IP.

## Disabling Dynamic DNS

To disable dynamic DNS, simply set `enable = false` in `router-config.nix`:

```nix
dyndns = {
  enable = false;
  # ... rest of config ...
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

