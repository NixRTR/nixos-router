[
  # HTTP/HTTPS to Hera
  {
    proto = "both";
    externalPort = 80;
    destination = "192.168.2.33";
    destinationPort = 80;
  }
  {
    proto = "both";
    externalPort = 443;
    destination = "192.168.2.33";
    destinationPort = 443;
  }
  # Syncthing to Hera
  {
    proto = "both";
    externalPort = 22000;
    destination = "192.168.2.33";
    destinationPort = 22000;
  }
  # Port 4242 to Triton
  {
    proto = "both";
    externalPort = 4242;
    destination = "192.168.2.31";
    destinationPort = 4242;
  }
]
