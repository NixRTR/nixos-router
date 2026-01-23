{
  enable = true;  # Set to false to disable DHCP for this network
  start = "192.168.3.100";
  end = "192.168.3.200";
  leaseTime = "1h";
  dnsServers = [
    "192.168.3.1"
  ];
  
  # Dynamic DNS domain for DHCP clients (optional)
  # If set, ALL DHCP clients get automatic DNS entries
  # Example: client with hostname "phone" gets "phone.dhcp.lan.local"
  # If no hostname provided, uses: "dhcp-<last-octet>.dhcp.lan.local"
  dynamicDomain = "dhcp.lan.local";  # Set to "" to disable dynamic DNS
  
  reservations = [
    # Example: { hostname = "desktop"; hwAddress = "11:22:33:44:55:66"; ipAddress = "192.168.3.50"; }
    # Example: { hostname = "laptop"; hwAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "192.168.3.51"; }
  ];
}
