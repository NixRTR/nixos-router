{
  enable = true;  # Set to false to disable DHCP for this network
  start = "192.168.3.100";
  end = "192.168.3.200";
  leaseTime = "1h";
  dnsServers = [
    "192.168.3.1"
  ];

  # DHCP option 15 (domain name / Windows "DNS suffix for this connection").
  # Default (when unset): derived from the first DNS A-record zone (e.g. jeandr.net).
  # If that matches dns-lan.nix cname_records like "*.jeandr.net", dnsmasq's address=/jeandr.net/IP
  # matches ANY name ending in .jeandr.net — including oauth2.googleapis.com.jeandr.net when Windows
  # appends the suffix. Fix: remove the apex wildcard and use explicit host/CNAME records, OR set
  # option15Domain to a zone that is NOT covered by that wildcard (e.g. same as dynamicDomain below),
  # OR set option15Domain = "" to stop sending option 15 (short-name resolution may change).
  # option15Domain = "dhcp.lan.local";
  
  # Dynamic DNS domain for DHCP clients (optional)
  # If set, ALL DHCP clients get automatic DNS entries
  # Example: client with hostname "phone" gets "phone.dhcp.lan.local"
  # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.lan.local"
  dynamicDomain = "dhcp.lan.local";  # Set to "" to disable dynamic DNS
  
  reservations = import ./dhcp-reservations-lan.nix;
}
