{
  # Enable web-based monitoring dashboard
  enable = true;

  # Port for the WebUI (default: 8080)
  port = 8080;

  # Data collection interval in seconds (default: 2)
  # Lower = more frequent updates, higher CPU usage
  # Higher = less frequent updates, lower CPU usage
  collectionInterval = 2;

  # Database settings (PostgreSQL)
  database = {
    host = "localhost";
    port = 5432;
    name = "router_webui";
    user = "router_webui";
  };

  # Historical data retention in days (default: 30)
  # Older data is automatically cleaned up
  retentionDays = 30;

  # Access control
  # The WebUI uses system user authentication (PAM)
  # Any user with a valid system account can login
  # To restrict access to specific users, use firewall rules
  # or configure Nginx reverse proxy with additional auth
}
