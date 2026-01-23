{
  # Enable Apprise API notification service
  enable = true;

  # Internal port for apprise-api (default: 8001, separate from webui)
  port = 8001;

  # Maximum attachment size in MB (0 = disabled)
  attachSize = 0;

  # Optional: Attachments directory path
  # attachmentsDir = "/var/lib/apprise/attachments";

  # Notification Services Configuration
  # Configure notification services that apprise-api will use
  # Secrets (passwords, tokens) are stored in secrets/secrets.yaml
  services = {
    # Email configuration
    email = {
      enable = false;
      smtpHost = "smtp.gmail.com";
      smtpPort = 587;
      username = "your-email@gmail.com";
      # Password stored in sops secrets as "apprise-email-password"
      to = "recipient@example.com";
      # Optional: from address (defaults to username)
      # from = "your-email@gmail.com";
    };

    # Home Assistant configuration
    homeAssistant = {
      enable = false;
      host = "homeassistant.local";
      port = 8123;
      # Access token stored in sops secrets as "apprise-homeassistant-token"
      # Optional: use HTTPS
      # useHttps = false;
    };

    # Discord configuration
    discord = {
      enable = false;
      # Webhook ID and token stored in sops secrets:
      # - "apprise-discord-webhook-id"
      # - "apprise-discord-webhook-token"
    };

    # Slack configuration
    slack = {
      enable = false;
      # Tokens stored in sops secrets:
      # - "apprise-slack-token-a"
      # - "apprise-slack-token-b"
      # - "apprise-slack-token-c"
    };

    # Telegram configuration
    telegram = {
      enable = false;
      # Bot token stored in sops secrets as "apprise-telegram-bot-token"
      chatId = "123456789";  # Can be stored in sops if preferred
    };

    # ntfy configuration
    ntfy = {
      enable = false;
      topic = "router-notifications";
      # Optional: custom ntfy server
      # server = "https://ntfy.sh";
      # Optional: authentication
      # Username stored in sops as "apprise-ntfy-username"
      # Password stored in sops as "apprise-ntfy-password"
    };
  };
}
