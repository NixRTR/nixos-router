{
  enable = true;  # Set to false to disable DHCP for this network
  start = "192.168.2.100";
  end = "192.168.2.200";
  leaseTime = "1h";
  dnsServers = [
    "192.168.2.1"
  ];
  
  # Dynamic DNS domain for DHCP clients (optional)
  # If set, ALL DHCP clients get automatic DNS entries
  # Example: client with hostname "phone" gets "phone.dhcp.homelab.local"
  # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.homelab.local"
  dynamicDomain = "dhcp.homelab.local";  # Set to "" to disable dynamic DNS
  
  reservations = import ./dhcp-reservations-homelab.nix;
}
