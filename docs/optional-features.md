# Optional Features

This router includes optional features for advanced use cases.

## Overview

- **Dynamic DNS (Linode)**: Keep a domain name pointed at your changing WAN IP
- **Custom Features**: Extend the router with your own services

---

## Dynamic DNS (Linode)

Automatically updates your Linode DNS records when your WAN IP changes.

### Use Cases

- Access your home network remotely via domain name
- Host services without static IP
- Integrate with Let's Encrypt for automatic SSL certificates

### Prerequisites

- **Linode account** (free tier works)
- **Domain name** managed by Linode DNS
- **Linode API token**

### Setup

#### 1. Create Linode API Token

1. Log in to [Linode Cloud Manager](https://cloud.linode.com)
2. Go to "API Tokens" (Profile → API Tokens)
3. Click "Create a Personal Access Token"
4. Label: `nixos-router-dyndns`
5. Expiration: Never (or choose expiration)
6. Scopes: Select **"Domains" → Read/Write**
7. Create token
8. **Copy the token** (you won't see it again!)

#### 2. Add Domain to Linode DNS

1. Go to "Domains" in Linode Cloud Manager
2. Click "Create Domain"
3. Enter your domain (e.g., `example.com`)
4. Add A record:
   - Hostname: `home` (creates `home.example.com`)
   - IP Address: `0.0.0.0` (will be auto-updated)
   - TTL: 300 (5 minutes)

#### 3. Configure Router

Edit `/etc/nixos/router-config.nix`:

```nix
dyndns = {
  enable = true;
  domain = "home.example.com";  # Full subdomain
};
```

#### 4. Add API Token to Secrets

```bash
cd /etc/nixos
sops secrets/secrets.yaml
```

Add the token:

```yaml
linode-api-token: "your-token-here"
```

Save and exit (Ctrl+X, Y, Enter).

#### 5. Apply Configuration

```bash
curl -fsSL https://beard.click/nixos-router-config | sudo bash
```

### How It Works

1. Timer runs every **5 minutes**
2. Fetches current WAN IP
3. Compares with DNS record
4. Updates Linode DNS if changed
5. Logs to systemd journal

### Verification

Check logs:

```bash
journalctl -u linode-dyndns -f
```

Expected output:

```
Started Linode Dynamic DNS Update
IP unchanged: 203.0.113.42
```

If IP changed:

```
Updated home.example.com to 203.0.113.43
```

Test DNS resolution:

```bash
# From external network
nslookup home.example.com
# Should return your current WAN IP
```

### Troubleshooting

#### Token Not Working

Error: `401 Unauthorized`

- Verify token has "Domains" read/write scope
- Token may be expired
- Regenerate token if needed

#### Domain Not Updating

1. **Check domain exists in Linode**:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.linode.com/v4/domains
   ```

2. **Check A record exists**:
   Must have A record for the subdomain in Linode DNS.

3. **Check service status**:
   ```bash
   systemctl status linode-dyndns.timer
   systemctl status linode-dyndns.service
   ```

4. **Manual trigger**:
   ```bash
   sudo systemctl start linode-dyndns.service
   journalctl -u linode-dyndns -n 20
   ```

#### Using with Let's Encrypt

Once DynDNS is working, you can use the domain for SSL certificates.

Example with Caddy (requires separate setup):

```
home.example.com {
  reverse_proxy localhost:8080
}
```

Caddy will automatically obtain SSL certificate via ACME.

---

## Custom Extensions

The router is built on NixOS, making it easy to add custom services.

### Adding a Service

Example: Add Pi-hole for enhanced ad blocking.

Edit `/etc/nixos/configuration.nix`:

```nix
{
  # ... existing config ...

  # Add Pi-hole Docker container
  virtualisation.docker.enable = true;
  
  systemd.services.pihole = {
    description = "Pi-hole DNS";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${pkgs.docker}/bin/docker run -d \
          --name pihole \
          --restart unless-stopped \
          -p 8080:80 \
          -e TZ=America/Anchorage \
          -v /var/lib/pihole:/etc/pihole \
          pihole/pihole:latest
      '';
      ExecStop = "${pkgs.docker}/bin/docker stop pihole";
    };
  };
}
```

Apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

Access Pi-hole: `http://192.168.2.1:8080`

### Adding Packages

Need a tool installed on the router?

Edit `/etc/nixos/configuration.nix`:

```nix
{
  environment.systemPackages = with pkgs; [
    # Existing packages...
    vim
    htop
    nmap
    tcpdump
    iftop
    mtr
    # Add yours here
  ];
}
```

### Custom Firewall Rules

For advanced firewall needs:

Edit `/etc/nixos/configuration.nix`:

```nix
{
  networking.firewall.extraCommands = ''
    # Rate limit SSH
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
    
    # Block specific IP
    iptables -A INPUT -s 203.0.113.100 -j DROP
    
    # Custom port forward with rate limiting
    iptables -A FORWARD -p tcp --dport 8080 -m limit --limit 100/sec -j ACCEPT
  '';
}
```

### Scheduling Tasks

Run custom tasks on a schedule:

```nix
{
  systemd.timers.custom-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Unit = "custom-backup.service";
    };
  };

  systemd.services.custom-backup = {
    description = "Custom Backup Task";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/path/to/backup-script.sh";
    };
  };
}
```

---

## Future Features

Planned additions (contributions welcome!):

- **Traffic Shaping**: QoS for prioritizing traffic
- **Suricata IDS**: Intrusion detection system
- **WireGuard VPN**: Native VPN server for secure remote access
- **Captive Portal**: Guest network with terms acceptance
- **VLAN Support**: 802.1Q VLAN tagging
- **IPv6 Support**: Full IPv6 routing and DHCPv6

---

## Next Steps

- **[Performance](performance.md)** - Optimize your router
- **[Updating](updating.md)** - Keep features up to date
- **[Troubleshooting](troubleshooting.md)** - Fix issues

