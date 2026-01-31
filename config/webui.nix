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

  # Limit PostgreSQL CPU so aggregation doesn't starve core router functions.
  # 100% = one core max; increase if frontend feels slow and you rely on Redis cache.
  postgresqlCpuQuota = "100%";

  # Access control
  # The WebUI uses system user authentication (PAM)
  # Any user with a valid system account can login
  # To restrict access to specific users, use firewall rules
  # or configure Nginx reverse proxy with additional auth
}
