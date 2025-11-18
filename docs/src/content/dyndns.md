# Dynamic DNS Configuration

Configure dynamic DNS updates to keep your domain pointing to your router's public IP.

## Linode Dynamic DNS

The router supports Linode's Dynamic DNS service:

\`\`\`nix
dyndns = {
  enable = true;
  provider = "linode";
  domain = "example.com";
  subdomain = "router";
  updateInterval = 300;  # 5 minutes
};
\`\`\`

## Configuration Options

- \`enable\` - Enable/disable dynamic DNS updates
- \`provider\` - DNS provider (currently "linode")
- \`domain\` - Your domain name
- \`subdomain\` - Subdomain to update (optional)
- \`updateInterval\` - How often to check and update (in seconds)

## Secrets

Dynamic DNS credentials should be stored in your secrets file:

\`\`\`yaml
linode-api-key: "your-api-key-here"
\`\`\`

## Verification

Check if dynamic DNS is working:

\`\`\`bash
# Check service status
sudo systemctl status linode-dyndns.service

# Check logs
sudo journalctl -u linode-dyndns.service -n 50
\`\`\`

