{ config, pkgs, lib, ... }:

with lib;

let
  routerConfig = import ../router-config.nix;
  
  # Extract bridge information from config
  bridges = routerConfig.lan.bridges;
  bridgeIPs = map (b: b.ipv4.address) bridges;

in

{
  # PowerDNS Recursor - Recursive DNS resolver with caching
  services.pdns-recursor = {
    enable = true;
    # Forward to upstream DNS servers (list format for YAML)
    forwardZones = {
      "." = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
    };
    settings = {
      # Listen addresses - Listen on all bridge IPs plus localhost
      local-address = (map (ip: "${ip}:53") bridgeIPs) ++ [ "127.0.0.1:53" ];
      
      # Allow queries from private networks
      allow-from = [
        "127.0.0.0/8"
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
      
      # Caching settings
      max-cache-entries = 1000000;
      max-cache-ttl = 7200;  # 2 hours
      max-negative-ttl = 3600;  # 1 hour for negative caching
      
      # Performance optimizations
      threads = 2;
      pdns-distributes-queries = "yes";
      
      # Security
      dnssec = "process-no-validate";
      
      # Logging
      loglevel = 4;  # Info level
      log-common-errors = "yes";
    };
  };

  # PowerDNS Authoritative Server - For local zone management
  # Prepare PowerDNS Authoritative configuration for Docker container
  system.activationScripts.powerdns-authoritative = ''
    set -euo pipefail

    # Ensure directories exist
    mkdir -p /etc/powerdns
    mkdir -p /var/lib/powerdns

    # Generate API key if it doesn't exist
    if [ ! -f /var/lib/powerdns/api-key ]; then
      echo "Generating PowerDNS API key..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /var/lib/powerdns/api-key
      chmod 600 /var/lib/powerdns/api-key
    fi

    # Ensure database file exists (PowerDNS will initialize if empty)
    if [ ! -f /var/lib/powerdns/pdns.sqlite3 ]; then
      touch /var/lib/powerdns/pdns.sqlite3
      chmod 600 /var/lib/powerdns/pdns.sqlite3
    fi

    API_KEY=$(cat /var/lib/powerdns/api-key)

    cat > /etc/powerdns/pdns.conf <<EOF
# PowerDNS Authoritative configuration (managed by NixOS)
launch=gsqlite3
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3

# API for PowerDNS Admin
api=yes
api-key=${API_KEY}
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=0.0.0.0/0

# Networking
local-port=5300
local-address=127.0.0.1

# Logging
loglevel=4
log-dns-queries=no
log-dns-details=no
EOF

    chmod 640 /etc/powerdns/pdns.conf
  '';

  # Firewall rules for PowerDNS services
  networking.firewall.allowedUDPPorts = mkAfter [ 53 ];
  networking.firewall.allowedTCPPorts = mkAfter [ 53 8081 ];  # 53=DNS, 8081=PowerDNS API
}

