{
  enable = true;
  provider = "linode";

  # Domain and record to update
  domain = "jeandr.net";
  subdomain = "";  # Root domain

  # Linode API credentials (stored in sops secrets)
  domainId = 1730384;
  recordId = 19262732;

  # Update interval
  checkInterval = "5m";
}
