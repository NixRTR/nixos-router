# Development Guide

## Repository Structure

```
nixos-router/
├── configuration.nix      # Main system configuration
├── router.nix            # Router module implementation
├── hardware-configuration.nix  # Hardware-specific config
├── vars.nix              # (Removed) Was for user variables
├── flake.nix             # Nix flake definition
├── flake.lock            # Locked flake dependencies
├── secrets/
│   └── secrets.yaml      # Encrypted secrets (Age)
├── scripts/
│   └── install-age-key.sh  # Age key installation helper
└── docs/                 # Documentation
    ├── setup.md          # Installation guide
    ├── router.md         # Router configuration
    ├── secrets.md        # Secrets management
    ├── troubleshooting.md  # Problem solving
    └── development.md    # This file
```

## Development Environment

### Enter Development Shell
```bash
nix develop
```
This provides:
- `sops` - Secret encryption/decryption
- `age` - Key generation and management
- `nixos-rebuild` - System deployment
- `nixfmt` - Nix code formatting

### Code Formatting
```bash
# Format all Nix files
find . -name "*.nix" -exec nixfmt {} \;

# Check formatting
nixfmt --check *.nix
```

## Testing Changes

### Local Testing (Safe)
```bash
# Dry run - check configuration without applying
sudo nixos-rebuild dry-build --flake .#router

# Test build - build but don't activate
sudo nixos-rebuild test --flake .#router
```

### Full Deployment
```bash
# Apply changes
sudo nixos-rebuild switch --flake .#router

# Boot into new configuration
sudo nixos-rebuild boot --flake .#router
```

### Rollback
```bash
# See generations
nixos-rebuild list-generations

# Rollback to previous
sudo nixos-rebuild switch --rollback
```

## Module Development

### Router Module Structure
The `router.nix` module follows NixOS module conventions:

```nix
{ config, lib, ... }:

with lib;

let
  cfg = config.router;
  # Helper functions and derivations
in {
  options.router = {
    # Option definitions
    enable = mkEnableOption "router functionality";

    wan = {
      type = mkOption {
        type = types.enum [ "dhcp" "pppoe" "static" "pptp" ];
        default = "dhcp";
        description = "WAN connection type";
      };
      # ... more options
    };
  };

  config = mkIf cfg.enable {
    # Implementation
    networking = {
      # Network configuration
    };

    services = {
      # Service configuration
    };

    systemd.services = {
      # Custom services
    };
  };
}
```

### Adding New Features

1. **Define options** in `options.router.*`
2. **Implement logic** in `config = mkIf cfg.enable { ... }`
3. **Test thoroughly** with different configurations
4. **Update documentation** in `docs/router.md`

### Option Types Reference
```nix
# Common option types
mkOption {
  type = types.bool;                    # true/false
  type = types.str;                     # String
  type = types.int;                     # Integer
  type = types.listOf types.str;        # List of strings
  type = types.enum [ "a" "b" "c" ];    # One of listed values
  type = types.nullOr types.str;        # String or null
  type = types.submodule { ... };       # Nested options
}
```

## Secrets Development

### Adding New Secrets
1. **Add to secrets.yaml** (plaintext, then encrypt)
2. **Configure in sops.secrets**:
   ```nix
   sops.secrets."new-secret" = {
     path = "/run/secrets/new-secret";
     owner = "serviceuser";
     group = "servicegroup";
     mode = "0400";
   };
   ```

3. **Use in configuration**:
   ```nix
   services.myService.secretFile = config.sops.secrets."new-secret".path;
   ```

### Secrets Best Practices
- Use descriptive names: `database-password`, not `db-pass`
- Set minimal permissions: `0400` for files, `0500` for directories
- Use `neededForUsers = true` for secrets required during user creation
- Document required secrets in `docs/secrets.md`

## Testing Strategy

### Unit Tests
```bash
# Test Nix evaluation
nix-instantiate --eval configuration.nix

# Test with specific arguments
nix-instantiate --eval --argstr hostname "test" configuration.nix
```

### Integration Tests
```bash
# Test router module isolation
nix-build -E '(import <nixpkgs/nixos> { configuration = ./configuration.nix; }).config.system.build.toplevel'

# Verify secrets handling
sops --decrypt secrets/secrets.yaml | jq .  # If YAML has structure
```

### Manual Testing Checklist
- [ ] PPPoE connection establishes
- [ ] DHCP leases are assigned
- [ ] DNS resolution works
- [ ] Port forwarding functions
- [ ] Firewall rules are correct
- [ ] Secrets are properly decrypted
- [ ] User authentication works

## Contributing

### Pull Request Process
1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Make** your changes with tests
4. **Format** code: `nixfmt *.nix`
5. **Test** thoroughly
6. **Update** documentation
7. **Commit** with clear messages
8. **Push** to your fork
9. **Create** Pull Request

### Commit Guidelines
```bash
# Good commit messages
feat: add PPTP WAN support
fix: correct DHCP lease time validation
docs: update secrets management guide
refactor: simplify firewall rule generation

# Bad commit messages
"update stuff"
"fix bug"
"changes"
```

### Code Style
- Use `nixfmt` for consistent formatting
- Follow NixOS module conventions
- Use descriptive variable names
- Add comments for complex logic
- Keep functions small and focused

## Debugging

### Common Development Issues

**Module not loading:**
```bash
# Check imports
grep -n "imports" configuration.nix

# Verify module syntax
nix-instantiate --parse router.nix
```

**Secrets not working:**
```bash
# Test decryption
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops --decrypt secrets/secrets.yaml

# Check file permissions
ls -la /run/secrets/
```

**Network issues:**
```bash
# Monitor network changes
journalctl -f -u systemd-networkd

# Test configuration
networkctl status
```

### Development Tools

**Debug Nix expressions:**
```bash
# Trace evaluation
nix-instantiate --eval --trace configuration.nix

# Show debug info
nix-instantiate --eval --debug configuration.nix
```

**Profile builds:**
```bash
# Time build steps
sudo nixos-rebuild switch --flake .#router --show-trace 2>&1 | ts

# Check store usage
du -sh /nix/store/*router* 2>/dev/null | sort -h | tail -10
```

## Release Process

### Version Bumping
1. Update version in `flake.nix`
2. Update changelog
3. Tag release: `git tag v1.2.3`
4. Push tags: `git push --tags`

### Documentation Updates
- Keep `docs/` in sync with code changes
- Update examples with new features
- Review troubleshooting guides for new issues

## Support

### Getting Help
- Check existing issues on GitHub
- Review `docs/troubleshooting.md`
- Test with minimal configuration
- Provide full error logs and system info

### Issue Template
When reporting bugs, include:
- NixOS version: `nixos-version`
- Hardware details
- Full configuration (redacted)
- Error logs: `journalctl -u <service>`
- Steps to reproduce
