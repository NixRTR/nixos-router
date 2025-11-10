# Defined Networking (Nebula VPN) Configuration

The NixOS router includes support for [Defined Networking](https://defined.net/), a managed Nebula overlay network service. This allows you to securely connect your router to other hosts across the internet with zero-configuration mesh VPN.

## What is Defined Networking?

Defined Networking is a managed service built on [Nebula](https://github.com/slackhq/nebula), Slack's open-source overlay networking tool. It provides:

- **Zero-trust mesh VPN** - Direct encrypted connections between hosts
- **Automatic hole-punching** - Works through NAT and firewalls
- **Web-based management** - Configure networks via admin.defined.net
- **Cross-platform** - Connect Linux, Windows, macOS, iOS, and Android devices
- **Low overhead** - Minimal performance impact

## Prerequisites

1. Create a free account at [https://defined.net](https://defined.net)
2. Create a network in the Defined Networking admin panel
3. Get an enrollment code for your router

## Setup

### 1. Get Enrollment Code

1. Log into [https://admin.defined.net](https://admin.defined.net)
2. Select your network
3. Click **"Add Host"**
4. Give it a name like `nixos-router`
5. Copy the enrollment code (looks like: `Y8roup2AAOyaZCeiio1ElGBVfH8M--iHf1DU_O6P86c`)

### 2. Option A: Direct Configuration (Simple)

Edit `/etc/nixos/router-config.nix`:

```nix
dnclient = {
  enable = true;
  enrollmentCode = "Y8roup2AAOyaZCeiio1ElGBVfH8M--iHf1DU_O6P86c";
  port = 4242;  # Optional: change if you need a different UDP port
};
```

**Note**: The enrollment code is only needed for the initial enrollment. After the first successful connection, you can remove it from the configuration.

### 2. Option B: Using Secrets (Recommended)

For better security, store the enrollment code in sops:

```bash
# Edit secrets
sudo nix shell nixpkgs#sops --command sops /etc/nixos/secrets/secrets.yaml
```

Add:
```yaml
dn-enrollment-code: Y8roup2AAOyaZCeiio1ElGBVfH8M--iHf1DU_O6P86c
```

Then in `configuration.nix`, add the secret:

```nix
sops.secrets."dn-enrollment-code" = {
  path = "/run/secrets/dn-enrollment-code";
  owner = "root";
  group = "root";
  mode = "0400";
};
```

And in `router-config.nix`:

```nix
dnclient = {
  enable = true;
  enrollmentCodeFile = "/run/secrets/dn-enrollment-code";
  port = 4242;  # Optional: change if needed
};
```

### 3. Rebuild the System

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

### 4. Verify Connection

```bash
# Check service status
sudo systemctl status dnclient

# View logs
sudo journalctl -u dnclient -f

# Check network interfaces
ip addr show | grep nebula
```

You should see a new `nebula1` interface with an IP address from your Defined Network (typically `100.64.x.x`).

## How It Works

The module creates two systemd services:

1. **dnclient-enroll.service** (oneshot)
   - Runs on first boot if enrollment code is provided
   - Enrolls the host with Defined Networking
   - Creates `/var/lib/dnclient/config.yml`
   - Only runs once (skips if already enrolled)

2. **dnclient.service** (persistent)
   - Runs the dnclient daemon
   - Maintains VPN connections
   - Auto-restarts on failure
   - Requires enrollment to be completed first

## Configuration Files

The dnclient configuration is stored in `/var/lib/dnclient/`:

```bash
# View configuration
sudo cat /var/lib/dnclient/config.yml

# View certificate
sudo cat /var/lib/dnclient/nebula.crt

# View private key (sensitive!)
sudo cat /var/lib/dnclient/nebula.key
```

## Post-Enrollment

After the initial enrollment, you can:

1. **Remove the enrollment code** from your configuration:
   ```nix
   dnclient = {
     enable = true;
     # enrollmentCode removed - no longer needed!
   };
   ```

2. **Manage the host** from the web interface at [https://admin.defined.net](https://admin.defined.net)
   - View connection status
   - Update firewall rules
   - Rotate certificates
   - Monitor traffic

## Firewall

The module automatically opens the configured UDP port for Nebula traffic (default: 4242).

### Using a Custom Port

If you need to use a different port (e.g., to avoid conflicts or for firewall requirements):

1. **Update `router-config.nix`**:
   ```nix
   dnclient = {
     enable = true;
     port = 51820;  # Use your custom port
     enrollmentCode = "...";
   };
   ```

2. **Update in Defined Networking admin panel**:
   - Log into [admin.defined.net](https://admin.defined.net)
   - Go to your network settings
   - Update the lighthouse port to match (51820 in this example)
   - Update host settings if needed

3. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#router
   ```

The module will:
- Automatically update the port in `/var/lib/dnclient/config.yml`
- Open the correct firewall port
- Apply changes on service start

## Accessing Services

Once connected, you can access services on other hosts in your Defined Network using their Nebula IPs:

```bash
# Ping another host in the network
ping 100.64.0.2

# SSH to another host
ssh user@100.64.0.2

# Access web services
curl http://100.64.0.2:8080
```

## Troubleshooting

### Service fails with "not enrolled yet"

The enrollment didn't complete. Check:

```bash
# Check if enrollment ran
sudo systemctl status dnclient-enroll

# View enrollment logs
sudo journalctl -u dnclient-enroll

# Check if config exists
ls -la /var/lib/dnclient/
```

If enrollment failed, try running it manually:

```bash
cd /var/lib/dnclient
sudo dnclient enroll -code YOUR_ENROLLMENT_CODE
```

### Service keeps restarting

Check the logs:

```bash
sudo journalctl -u dnclient -n 100
```

Common issues:
- **Network connectivity** - Ensure the router has internet access
- **Invalid certificate** - Certificate may have expired, re-enroll
- **Firewall blocking** - Check that UDP 4242 is allowed

### Can't reach other hosts

1. **Verify connection** in the Defined Networking admin panel
2. **Check firewall rules** on both ends
3. **Test connectivity**:
   ```bash
   # Check if nebula interface exists
   ip addr show nebula1
   
   # Check routing
   ip route | grep nebula
   
   # Test lighthouse connectivity
   sudo journalctl -u dnclient | grep lighthouse
   ```

### Re-enrollment

If you need to re-enroll (new network, certificate rotation, etc.):

```bash
# Stop the service
sudo systemctl stop dnclient

# Remove old configuration
sudo rm -rf /var/lib/dnclient/*

# Get a new enrollment code from admin.defined.net
# Update your configuration with the new code
# Rebuild
sudo nixos-rebuild switch --flake /etc/nixos#router
```

## Updating dnclient

The module pins dnclient to version 0.8.4. To update:

1. Check for new versions at [https://defined.net/changelog](https://defined.net/changelog)
2. Update the version in `dnclient.nix`:
   ```nix
   version = "0.8.5";  # new version
   ```
3. Get the new hash:
   ```bash
   ./scripts/get-dnclient-hash.sh 0.8.5
   ```
4. Update the hash in `dnclient.nix`
5. Rebuild

## Security Considerations

- **Enrollment code** - Only needed once, can be removed after enrollment
- **Private key** - Stored in `/var/lib/dnclient/nebula.key` with 0600 permissions
- **Certificate** - Valid for 1 year by default, can be rotated in admin panel
- **Firewall** - Only Nebula IPs can access services, still protected by router firewall
- **Zero-trust** - Each connection is mutually authenticated with certificates

## Integration with Router Services

You can configure services to listen on the Nebula interface:

```nix
# Example: Make Grafana accessible via Nebula
services.grafana.settings.server.http_addr = "100.64.0.1";  # Your router's Nebula IP
```

Or use firewall rules to allow access from Nebula network:

```nix
# Allow SSH from Nebula network
networking.firewall.interfaces."nebula1".allowedTCPPorts = [ 22 ];
```

## Disabling Defined Networking

To disable:

```nix
dnclient = {
  enable = false;
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

The configuration in `/var/lib/dnclient` will be preserved in case you want to re-enable it later.

## Advanced: Manual Installation Hash

If you need to get the SHA256 hash for a specific version:

```bash
# Download and get hash
./scripts/get-dnclient-hash.sh 0.8.4

# Or manually:
curl -fsSL https://dl.defined.net/290ff4b6/v0.8.4/linux/amd64/dnclient -o dnclient
nix hash file dnclient
```

Update the hash in `dnclient.nix`:

```nix
src = pkgs.fetchurl {
  url = "https://dl.defined.net/290ff4b6/v${version}/linux/amd64/dnclient";
  sha256 = "NEW_HASH_HERE";
};
```

## Resources

- [Defined Networking Documentation](https://docs.defined.net/)
- [Nebula GitHub](https://github.com/slackhq/nebula)
- [Defined Networking Admin Panel](https://admin.defined.net)
- [Community Support](https://defined.net/discord)

