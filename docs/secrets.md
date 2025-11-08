# Secrets Management

## Overview

This project uses [sops-nix](https://github.com/Mic92/sops-nix) to manage sensitive configuration securely. Secrets are encrypted with [Age](https://age-encryption.org/) and decrypted at runtime.

## Architecture

- **Storage**: Encrypted YAML files in `secrets/` directory
- **Encryption**: Age public-key encryption
- **Decryption**: Automatic at system activation
- **Access**: Decrypted secrets in `/run/secrets/` (root-only)

## Required Secrets

### PPPoE Credentials
```yaml
pppoe-username: "your-isp-username"
pppoe-password: "your-isp-password"
```

### System User Password
```yaml
password: "$6$rounds=1000000$salt$hashed-password"
```

Generate with: `mkpasswd -m sha-512`

## Key Management

### Generate Age Key
```bash
# Generate new keypair
age-keygen -o ~/.config/sops/age/keys.txt

# Extract public key for encryption
age-keygen -y ~/.config/sops/age/keys.txt
```

### Bootstrap on New System
```bash
# Copy your Age private key
sudo mkdir -p /var/lib/sops-nix
sudo cp ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt
sudo chmod 400 /var/lib/sops-nix/key.txt

# Or use the provided script
sudo ./scripts/install-age-key.sh
```

## Working with Secrets

### Edit Secrets
```bash
# Decrypt, edit, and re-encrypt
sops secrets/secrets.yaml
```

### Manual Encryption
```bash
# Encrypt plaintext file
sops --encrypt --age <public-key> input.yaml > secrets/secrets.yaml
```

### View Decrypted Secrets
```bash
# Temporary view (doesn't modify file)
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops --decrypt secrets/secrets.yaml
```

## Configuration

### SOPS Setup
```nix
sops = {
  defaultSopsFile = ./secrets/secrets.yaml;
  age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    generateKey = true;  # Only for initial setup
  };
  secrets = {
    "pppoe-password" = {
      path = "/run/secrets/pppoe-password";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    "password" = {
      path = "/run/secrets/password";
      owner = "root";
      group = "root";
      mode = "0400";
      neededForUsers = true;  # Decrypt before user creation
    };
  };
};
```

## Security Considerations

### Access Control
- Secrets are decrypted to `/run/secrets/` with `0400` permissions
- Only root can read decrypted secrets
- Files are temporary and cleaned on reboot

### Key Storage
- Private keys stored in `/var/lib/sops-nix/key.txt`
- Backup keys securely (password manager, HSM)
- Never commit private keys to version control

### Best Practices
1. **Rotate secrets regularly** through your ISP
2. **Use strong Age passphrases** for key encryption
3. **Limit SSH access** to the router
4. **Audit secret access** logs
5. **Backup encrypted secrets** (safe to commit)

## Troubleshooting

### "Permission denied" when editing
```bash
# Ensure you have the Age key
ls -la ~/.config/sops/age/keys.txt
# Should be 400 permissions
```

### "Failed to get the data key"
```bash
# Check Age key is available
echo $SOPS_AGE_KEY_FILE
# Or copy to standard location
cp /var/lib/sops-nix/key.txt ~/.config/sops/age/keys.txt
```

### Secrets not available at runtime
```bash
# Check sops-nix service
systemctl status sops-nix

# Verify secrets were decrypted
ls -la /run/secrets/
```

### User password not working
```bash
# Verify password format (should start with $6$)
head -1 /run/secrets/password

# Check it's a valid hash
mkpasswd --test < /run/secrets/password
```

## Migration from Other Systems

### From pass/krops
Convert existing secrets:
```bash
for gpg_file in *.gpg; do
  echo "$(basename "$gpg_file" .gpg): |"
  pass "$(dirname "$gpg_file")/$(basename "$gpg_file" .gpg)" | sed 's/^/  /'
done > secrets.yaml
```

### From manual secrets
Create YAML structure:
```yaml
secret-name: "secret-value"
another-secret: "another-value"
```

Then encrypt with sops.

## Advanced Usage

### Multiple Environments
Use different secret files for different deployments:
```nix
sops = {
  defaultSopsFile = ./secrets/production.yaml;
  # Or ./secrets/staging.yaml, ./secrets/development.yaml
};
```

### Template Secrets
For secrets that need to be embedded in configuration files:
```nix
sops.templates."config.toml" = {
  content = ''
    password = "${config.sops.placeholder."database-password"}"
  '';
  owner = "serviceuser";
};
```

### SSH Key Integration
```yaml
ssh-private-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
```

```nix
sops.secrets."ssh-private-key" = {
  path = "/etc/ssh/ssh_host_ed25519_key";
  owner = "root";
  group = "root";
  mode = "0600";
};
```
