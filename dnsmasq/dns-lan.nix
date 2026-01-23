{
  a_records = {
    "jeandr.net" = {
      ip = "192.168.3.33";
      comment = "Main jeandr.net domain - points to Hera (HOMELAB)";
    };
    "router.jeandr.net" = {
      ip = "192.168.3.1";
      comment = "Router address (LAN side)";
    };
    "hera.jeandr.net" = {
      ip = "192.168.3.33";
      comment = "Hera - Main web/app server";
    };
    "triton.jeandr.net" = {
      ip = "192.168.3.31";
      comment = "Triton - Secondary server";
    };
    # Add LAN-specific devices here:
    # "workstation.jeandr.net" = { ip = "192.168.3.101"; comment = "Main workstation"; };
    # "desktop.jeandr.net" = { ip = "192.168.3.50"; comment = "Desktop computer"; };
  };

  cname_records = {
    "*.jeandr.net" = {
      target = "jeandr.net";
      comment = "Wildcard for all subdomains";
    };
    # Add more aliases as needed
  };
}
