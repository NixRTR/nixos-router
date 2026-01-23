{
  enable = true;

  # Upstream DNS servers (shared by all networks)
  # Plain DNS format for dnsmasq (no DoT support)
  upstreamServers = [
    "1.1.1.1"  # Cloudflare DNS
    "9.9.9.9"  # Quad9 DNS
  ];
}
