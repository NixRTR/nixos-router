# Documentation

This project is a NixOS router configuration. Everything is controlled through `router-config.nix`` in the repository root.

## Installation

### Using the custom ISO
1. Build the ISO:
   ```
   cd iso
   ./build-iso.sh
   ```
   The script fetches everything via Nix; expect a large download on the first run.
2. Write `result/iso/*.iso` to a USB drive.
3. (Optional) Place your `router-config.nix` inside the USB `config/` folder for unattended installs.
4. Boot the router from USB and follow the menu. Pick install or upgrade.
5. After completion, reboot and remove the USB stick.

### Using the install script
Run from a vanilla NixOS installer shell:
```
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```
The script clones this repo, copies `router-config.nix`, and triggers `nixos-install`. Keep your `router-config.nix` nearby; the script will prompt for its path.

## Upgrading

### With the ISO
1. Build or download the latest ISO (same steps as installation).
2. Boot from the USB.
3. Select the upgrade entry in the menu; it reuses your existing `router-config.nix`.
4. Reboot when finished.

### With the script
1. Boot any Linux shell with internet access on the router (local console or SSH).
2. Re-run the script:
   ```
   curl -fsSL https://beard.click/nixos-router > install.sh
   chmod +x install.sh
   sudo ./install.sh
   ```
   Choose the upgrade option when prompted. The script pulls the latest commits and rebuilds the system.

Whichever path you pick, verify with:
```
sudo nixos-version
sudo systemctl status router-webui-backend.service
```
and ensure LAN clients retrieve leases after the reboot.



## Editing `router-config.nix`

The file is plain Nix. Adjust the attributes below and rebuild.

### System
- `hostname` – router host name.
- `domain` – search domain appended to `/etc/resolv.conf`.
- `timezone` – Olson timezone string.
- `username` – local admin account.
- `nameservers` – list of upstream DNS servers the router itself uses.
- `sshKeys` – optional list of authorized keys for the admin user.

### WAN
```
wan = {
  type = "dhcp" | "pppoe";
  interface = "eno1";
};
```
Pick the correct interface and protocol for your ISP.

### LAN bridges
```
lan.bridges = [
  {
    name = "br0";
    interfaces = [ "enp4s0" "enp5s0" ];
    ipv4.address = "192.168.2.1";
    ipv4.prefixLength = 24;
    ipv6.enable = false;
  }
];
```
- `name` – bridge name.
- `interfaces` – physical NICs attached to the bridge.
- `ipv4` – router IP and prefix per bridge.
- `ipv6.enable` – disable if you only run IPv4.

`lan.isolation = true` blocks routing between bridges unless you add entries to `lan.isolationExceptions` (each entry needs `source`, `sourceBridge`, `destBridge`, and a short description).

### Network sections
There are two per-network blocks: `homelab { ... }` and `lan { ... }`. Both support the same keys:

- `ipAddress` / `subnet` – router address and subnet for that VLAN.
- `dhcp.enable` – toggle Kea DHCP.
- `dhcp.start` / `dhcp.end` – pool range.
- `dhcp.leaseTime` – string (e.g. `"1h"`).
- `dhcp.dnsServers` – IPs handed to clients.
- `dhcp.dynamicDomain` – optional domain for automatic host records.
- `dhcp.reservations` – static leases.
- `dns.enable` – toggle Unbound for this network.
- `dns.a_records` – hostname to IP map.
- `dns.cname_records` – aliases.
- `dns.blocklists` – per-list switches; each list has `enable`, `url`, `description`, `updateInterval`.
- `dns.whitelist` – array of domains to bypass blocking.

### Port forwarding
`portForwards` is an array of rules:
```
{
  proto = "tcp" | "udp" | "both";
  externalPort = 443;
  destination = "192.168.2.33";
  destinationPort = 443;
}
```

### Dynamic DNS
```
dyndns = {
  enable = true;
  provider = "linode";
  domain = "example.com";
  subdomain = "";
  domainId = 0;
  recordId = 0;
  checkInterval = "5m";
};
```
Requires API IDs to match your DNS provider. Secrets live in `secrets/`.

### Global DNS
`dns.upstreamServers` lists DNS-over-TLS endpoints (format `IP@port#hostname`).

### Web UI
```
webui = {
  enable = true;
  port = 8080;
  collectionInterval = 2;
  database = { host = "localhost"; port = 5432; name = "router_webui"; user = "router_webui"; };
  retentionDays = 30;
};
```
Adjust port, polling interval, and retention as needed.
