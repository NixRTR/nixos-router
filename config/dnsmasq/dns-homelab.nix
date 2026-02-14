{
  # Domain hosting mode: false = fully hosted (local only), true = partially hosted (forward unlisted to upstream)
  forward_unlisted = false;

  a_records = {
    "jeandr.net" = {
      ip = "192.168.2.33";
      comment = "Main jeandr.net domain - points to Hera";
    };
    "router.jeandr.net" = {
      ip = "192.168.2.1";
      comment = "Router address";
    };
    "hera.jeandr.net" = {
      ip = "192.168.2.33";
      comment = "Hera - Main web/app server";
    };
    "triton.jeandr.net" = {
      ip = "192.168.2.31";
      comment = "Triton - Secondary server";
    };
    # Add more servers here as needed:
    # "nas.jeandr.net" = { ip = "192.168.2.40"; comment = "NAS storage"; };
  };

  cname_records = {
    "*.jeandr.net" = {
      target = "jeandr.net";
      comment = "Wildcard - all subdomains point to main domain";
    };
    # Add more aliases as needed:
    # "app.jeandr.net" = { target = "hera.jeandr.net"; comment = "Application"; };
    # "api.jeandr.net" = { target = "hera.jeandr.net"; comment = "API"; };
  };
}
