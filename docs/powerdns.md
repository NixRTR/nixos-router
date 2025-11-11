# PowerDNS Configuration

The router uses PowerDNS for DNS services, providing both recursive DNS resolution and authoritative DNS hosting with a web-based admin interface.

## Components

### 1. PowerDNS Recursor
- **Purpose**: Recursive DNS resolver with caching
- **Replaces**: Traditional DNS resolvers like Blocky/dnsmasq
- **Port**: 53 (DNS)
- **Listens on**: All bridge interfaces + localhost

### 2. PowerDNS Authoritative Server
- **Purpose**: Host authoritative DNS zones for local networks
- **Port**: 5300 (internal), 8081 (API/web server)
- **Backend**: SQLite database
- **Use case**: Local domain names, split-horizon DNS

### 3. PowerDNS Admin
- **Purpose**: Web interface for managing DNS zones and records
- **Port**: 9191
- **Implementation**: Native NixOS service
- **Access**: `http://router-ip:9191`

---

## Quick Start

### Accessing PowerDNS Admin

**Fully Automated Setup:**

After running `sudo nixos-rebuild switch`, the system automatically:
- ✅ Generates a secure random secret key
- ✅ Initializes the database
- ✅ Creates admin account using your system credentials
- ✅ Configures PowerDNS API connection
- ✅ Starts PowerDNS Admin on port 9191

**Everything is ready to use!**

**Login Credentials:**

```
URL:      http://192.168.2.1:9191 (or your router's IP)
Username: <your system username>  (e.g., routeradmin)
Password: <your system password>  (same as SSH/console)
```

**Same credentials as your system login!** No need to remember separate passwords.

**Password Synchronization:**

Your PowerDNS Admin password automatically stays in sync with your system password:
- Change your system password (update sops secret and rebuild)
- PowerDNS Admin password updates automatically on next `nixos-rebuild switch`
- Always use your current system password to log in

**First Login:**

1. Open your browser to `http://192.168.2.1:9191`
2. Log in with your system credentials (same as SSH)
3. Start creating DNS zones and records!

The PowerDNS API is already configured and connected - no additional setup needed!

### Testing DNS Resolution

```bash
# From a client on the network
dig @192.168.2.1 google.com

# Test DNSSEC
dig @192.168.2.1 +dnssec cloudflare.com

# Check response time (should be fast with caching)
dig @192.168.2.1 example.com
dig @192.168.2.1 example.com  # Second query should be instant
```

---

## Configuration

### Recursor Settings

Located in `/etc/nixos/configuration.nix`:

```nix
services.pdns-recursor = {
  enable = true;
  dns.address = [ "192.168.2.1:53" "192.168.3.1:53" "127.0.0.1:53" ];
  dns.allowFrom = [
    "127.0.0.0/8"
    "192.168.0.0/16"
    "10.0.0.0/8"
    "172.16.0.0/12"
  ];
  forwardZones = {
    "." = "1.1.1.1;8.8.8.8;9.9.9.9";
  };
  settings = {
    max-cache-entries = 1000000;
    max-cache-ttl = 7200;  # 2 hours
    threads = 2;
  };
};
```

### Authoritative Server Settings

```nix
services.powerdns = {
  enable = true;
  extraConfig = ''
    local-port=5300
    local-address=127.0.0.1
    
    # SQLite backend
    launch=gsqlite3
    gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
    
    # API for PowerDNS Admin
    api=yes
    api-key=changeme
    webserver=yes
    webserver-port=8081
  '';
};
```

---

## Common Tasks

### Change Upstream DNS Servers

Edit `/etc/nixos/configuration.nix`:

```nix
forwardZones = {
  "." = "1.1.1.1;8.8.8.8";  # Cloudflare and Google
};
```

Popular upstream options:
- **Cloudflare**: `1.1.1.1`, `1.0.0.1`
- **Google**: `8.8.8.8`, `8.8.4.4`
- **Quad9** (privacy-focused): `9.9.9.9`, `149.112.112.112`
- **OpenDNS**: `208.67.222.222`, `208.67.220.220`

Apply changes:
```bash
sudo nixos-rebuild switch
```

### Create a Local DNS Zone

1. Open PowerDNS Admin: `http://192.168.2.1:9191`
2. Go to "Domain" → "Add Domain"
3. Enter domain name: `homelab.local`
4. Type: `Native`
5. Click "Create"

### Add DNS Records

1. Click on your domain (`homelab.local`)
2. Click "Add Record"
3. Fill in:
   - **Name**: `server1` (becomes `server1.homelab.local`)
   - **Type**: `A`
   - **Content**: `192.168.2.33`
   - **TTL**: `3600`
4. Click "Save"

Now `server1.homelab.local` resolves to `192.168.2.33` from any device on your network!

### Split-Horizon DNS

Serve different DNS responses to internal vs external clients:

1. Create zone `example.com` in PowerDNS Admin
2. Add A record:
   - **Name**: `@` (root domain)
   - **Content**: `192.168.2.33` (internal IP)
3. Configure recursor to use authoritative server for this zone:

```nix
forwardZones = {
  "example.com" = "127.0.0.1:5300";
  "." = "1.1.1.1;8.8.8.8";
};
```

Internal clients get `192.168.2.33`, external clients get the public DNS record.

---

## Security

### Change Your Password

Your PowerDNS Admin password is automatically synced with your system password:

1. Update your password in sops secrets:
   ```bash
   # Edit the secrets file
   sops /etc/nixos/secrets/secrets.yaml
   
   # Update the 'password' field
   ```

2. Rebuild the system:
   ```bash
   sudo nixos-rebuild switch
   ```

3. The PowerDNS Admin password automatically updates!

**No manual steps needed** - just rebuild and your new password works everywhere (SSH, console, and PowerDNS Admin).

### Change API Key

**Important**: Change the default API key!

1. Edit `/etc/nixos/configuration.nix`:
   ```nix
   services.powerdns = {
     extraConfig = ''
       api-key=your-secure-random-key-here
     '';
   };
   ```

2. Update PowerDNS Admin configuration to use the same key:
   - The API key is read from the environment variable `POWERDNS_API_KEY`
   - Both services are already configured to use the same key

3. Generate and store a secure key:
   ```bash
   # Generate secure API key
   openssl rand -hex 32 > /var/lib/powerdns-admin/api-key
   
   # Set proper permissions
   sudo chown powerdns-admin:powerdns-admin /var/lib/powerdns-admin/api-key
   sudo chmod 600 /var/lib/powerdns-admin/api-key
   ```

4. Rebuild and restart:
   ```bash
   sudo nixos-rebuild switch
   sudo systemctl restart powerdns powerdns-admin
   ```

5. Update in PowerDNS Admin web interface:
   - Settings → PowerDNS → API Key

### Restrict Access to Admin Interface

PowerDNS Admin should only be accessible from trusted networks.

**Option 1**: Firewall rule (recommended)
```nix
networking.firewall.interfaces."br0".allowedTCPPorts = [ 9191 ];
# Only accessible from br0 (HOMELAB), not br1 (LAN)
```

**Option 2**: VPN/SSH tunnel
```bash
# Access via SSH tunnel
ssh -L 9191:localhost:9191 routeradmin@router-ip
# Then open http://localhost:9191 on your local machine
```

---

## Monitoring

### Check Service Status

```bash
# Recursor
systemctl status pdns-recursor
journalctl -u pdns-recursor -f

# Authoritative
systemctl status powerdns
journalctl -u powerdns -f

# Admin interface
systemctl status powerdns-admin
docker logs -f powerdns-admin
```

### Performance Metrics

PowerDNS Recursor provides detailed statistics:

```bash
# View live stats
rec_control get-all

# Cache statistics
rec_control get cache-size
rec_control get cache-hits
rec_control get cache-misses

# Query statistics
rec_control get questions
rec_control get answers
```

### Grafana Dashboard

PowerDNS metrics are automatically collected by Prometheus and displayed in Grafana:

- **Dashboard**: `http://router-ip:3000`
- **Metrics include**:
  - Query rate
  - Cache hit ratio
  - Response times
  - Upstream query times

---

## Troubleshooting

### DNS Not Resolving

```bash
# Check if recursor is running
systemctl status pdns-recursor

# Test locally on router
dig @127.0.0.1 google.com

# Check logs
journalctl -u pdns-recursor -n 50

# Test upstream connectivity
ping 1.1.1.1
```

### PowerDNS Admin Won't Start

```bash
# Check service status
systemctl status powerdns-admin

# View logs
journalctl -u powerdns-admin -n 50

# Restart
sudo systemctl restart powerdns-admin
```

### Can't Access Admin Interface

1. Check firewall:
   ```bash
   sudo nft list ruleset | grep 9191
   ```

2. Test from router:
   ```bash
   curl http://localhost:9191
   ```

3. Check if service is listening:
   ```bash
   sudo ss -tlnp | grep 9191
   ```

### Slow DNS Queries

```bash
# Check cache hit ratio
rec_control get cache-hits
rec_control get cache-misses

# Test upstream latency
dig @1.1.1.1 example.com
dig @8.8.8.8 example.com

# Increase cache size if needed
# Edit configuration.nix:
settings = {
  max-cache-entries = 2000000;  # Double the cache
};
```

---

## Advanced Configuration

### Enable DNSSEC Validation

```nix
services.pdns-recursor = {
  settings = {
    dnssec = "validate";  # Enable full DNSSEC validation
  };
};
```

### Increase Performance

```nix
services.pdns-recursor = {
  settings = {
    threads = 4;  # More threads for high-traffic networks
    max-cache-entries = 2000000;
    max-tcp-clients = 128;
    max-tcp-per-client = 10;
  };
};
```

### Custom Lua Scripting

PowerDNS supports Lua scripts for advanced filtering/manipulation:

```nix
services.pdns-recursor = {
  settings = {
    lua-config-file = "/etc/powerdns/recursor.lua";
  };
};
```

Create `/etc/powerdns/recursor.lua`:
```lua
function preresolve(dq)
  if dq.qname:equal("badsite.com") then
    dq.rcode = pdns.NXDOMAIN
    return true
  end
  return false
end
```

---

## Backup and Restore

### Backup DNS Zones

```bash
# Backup PowerDNS database
sudo cp /var/lib/powerdns/pdns.sqlite3 /backup/pdns-$(date +%Y%m%d).sqlite3

# Backup PowerDNS Admin database
sudo cp /var/lib/powerdns-admin/powerdns-admin.db /backup/powerdns-admin-$(date +%Y%m%d).db
```

### Restore DNS Zones

```bash
# Stop services
sudo systemctl stop powerdns powerdns-admin

# Restore PowerDNS database
sudo cp /backup/pdns-20250111.sqlite3 /var/lib/powerdns/pdns.sqlite3
sudo chown powerdns:powerdns /var/lib/powerdns/pdns.sqlite3

# Restore PowerDNS Admin database
sudo cp /backup/powerdns-admin-20250111.db /var/lib/powerdns-admin/powerdns-admin.db
sudo chown powerdns-admin:powerdns-admin /var/lib/powerdns-admin/powerdns-admin.db

# Start services
sudo systemctl start powerdns powerdns-admin
```

---

## Migration from Blocky

If you're upgrading from a Blocky configuration:

1. **Automatic**: The recursor is configured with the same upstream servers (1.1.1.1, 8.8.8.8, 9.9.9.9)
2. **Cache**: PowerDNS cache starts empty but fills quickly
3. **No configuration changes needed**: DHCP already points clients to the router's IP for DNS

The transition should be seamless!

---

## See Also

- [PowerDNS Recursor Documentation](https://doc.powerdns.com/recursor/)
- [PowerDNS Authoritative Documentation](https://doc.powerdns.com/authoritative/)
- [PowerDNS Admin GitHub](https://github.com/PowerDNS-Admin/PowerDNS-Admin)
- [Monitoring Guide](monitoring.md)
- [Troubleshooting Guide](troubleshooting.md)


