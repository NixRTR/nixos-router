{
  # Domain hosting mode: false = fully hosted (local only), true = partially hosted (forward unlisted to upstream)
  forward_unlisted = false;

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
    # Apex wildcard: dnsmasq address=/jeandr.net/IP matches every *.jeandr.net name, including
    # bogus names like oauth2.googleapis.com.jeandr.net when clients append DHCP domain (option 15).
    # Prefer explicit records, a narrower zone (e.g. *.svc.jeandr.net), or fix DHCP option15Domain.
    "*.jeandr.net" = {
      target = "jeandr.net";
      comment = "Wildcard for all subdomains";
    };
    # Add more aliases as needed
  };
}
