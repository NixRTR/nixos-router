import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as s}from"./MarkdownContent-CHjPgFnl.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const t=`# Verify System Operation

## Basic System Verification

\`\`\`bash
# Check NixOS version
sudo nixos-version

# Verify system configuration is valid
sudo nixos-rebuild dry-run --flake /etc/nixos#router

# Check for failed systemd services
sudo systemctl --failed

# Check system health
sudo systemctl status
\`\`\`

## Router-Specific Services

\`\`\`bash
# WebUI Backend (main service)
sudo systemctl status router-webui-backend.service

# PostgreSQL (required for WebUI)
sudo systemctl status postgresql.service

# Kea DHCP servers (check both networks if configured)
sudo systemctl status kea-dhcp4-homelab.service
sudo systemctl status kea-dhcp4-lan.service

# Unbound DNS servers (check both networks if configured)
sudo systemctl status unbound-homelab.service
sudo systemctl status unbound-lan.service

# Dynamic DNS (if enabled)
sudo systemctl status linode-dyndns.service
sudo systemctl status linode-dyndns-on-wan-up.service

# Speedtest monitoring (if enabled)
sudo systemctl status speedtest.service
sudo systemctl status speedtest-on-wan-up.service
\`\`\`

## Verify Network Connectivity

\`\`\`bash
# Check WAN interface is up
ip addr show eno1  # or your WAN interface
ip link show eno1

# Check PPPoE connection (if using PPPoE)
ip addr show ppp0
sudo systemctl status pppoe-connection.service

# Check bridge interfaces
ip addr show br0
ip addr show br1  # if using multi-bridge mode

# Verify routing table
ip route show

# Check NAT is working
sudo nft list ruleset | grep -A 10 "nat"

# Test internet connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com
\`\`\`

## Verify DNS

\`\`\`bash
# Test DNS resolution
dig @192.168.2.1 router.jeandr.net  # HOMELAB DNS
dig @192.168.3.1 router.jeandr.net  # LAN DNS

# Check DNS is listening
sudo ss -tlnp | grep :53

# Test DNS from a client
# (from a device on the network)
nslookup router.jeandr.net 192.168.2.1
\`\`\`

## Verify DHCP

\`\`\`bash
# Check DHCP leases file exists and has entries
sudo cat /var/lib/kea/dhcp4.leases | tail -20

# Verify DHCP is listening
sudo ss -ulnp | grep :67

# Test DHCP from a client
# (release and renew on a client device)
\`\`\`

## Verify WebUI

\`\`\`bash
# Check WebUI is accessible
curl -I http://localhost:8080
# or from a client:
curl -I http://192.168.2.1:8080  # or your router IP

# Check WebUI logs for errors
sudo journalctl -u router-webui-backend.service -n 50 --no-pager

# Verify database connection
sudo -u router-webui psql -h localhost -U router_webui -d router_webui -c "SELECT COUNT(*) FROM system_metrics;"
\`\`\`

## Verify Firewall and Port Forwarding

\`\`\`bash
# Verify nftables rules are loaded
sudo nft list ruleset

# Check port forwarding rules
sudo nft list chain inet router port_forward

# Test port forwarding (from external network)
# telnet your-public-ip 443
\`\`\`
`;function a(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(s,{content:t})})})}export{a as Verification};
