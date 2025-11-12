# PowerDNS Admin - Docker Compose

This directory contains the Docker Compose configuration for PowerDNS Admin.

## Why Docker?

PowerDNS Admin has Flask/SQLAlchemy compatibility issues with NixOS's native packages. Running it in Docker provides:
- ✅ **Isolation**: Separate from system packages
- ✅ **Reliability**: Official upstream image
- ✅ **Easy updates**: `docker-compose pull && docker-compose up -d`
- ✅ **Portability**: Standard Docker configuration

## Deployment

**This configuration is automatically deployed by NixOS.**

When you run `sudo nixos-rebuild switch`, NixOS:
1. Deploys `docker-compose.yml` to `/etc/powerdns-admin/`
2. Enables Docker service
3. Starts `powerdns-admin-compose.service`
4. Pulls the latest image
5. Starts the container

## Configuration

To modify the configuration:

1. Edit `modules/powerdns.nix` (not this file)
2. Rebuild: `sudo nixos-rebuild switch --flake /etc/nixos#router`

The file here is for **reference only** and shows what gets deployed.

## Management

### Via Systemd (Recommended)

```bash
# Check status
sudo systemctl status powerdns-admin-compose

# Restart
sudo systemctl restart powerdns-admin-compose

# View logs
sudo journalctl -u powerdns-admin-compose -f
```

### Via Docker Compose

```bash
cd /etc/powerdns-admin

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# Restart
docker-compose restart

# Stop
docker-compose down

# Update and restart
docker-compose pull
docker-compose up -d
```

## Access

- **URL**: `http://router-ip:9191`
- **Default credentials**: `admin` / `admin`
- **⚠️ IMPORTANT**: Change password on first login!

## First-Time Setup

1. Log in with default credentials
2. Change password immediately
3. Configure PowerDNS API:
   - Go to **Settings** > **PDNS**
   - **API URL**: `http://localhost:8081`
   - **API Key**: Check `/var/lib/powerdns/api-key` on the router
4. Create DNS zones and records!

## Data Persistence

All data is stored in `/var/lib/powerdns-admin/` on the host system.

### Backup

```bash
sudo tar -czf powerdns-admin-backup.tar.gz -C /var/lib powerdns-admin
```

### Restore

```bash
sudo systemctl stop powerdns-admin-compose
sudo tar -xzf powerdns-admin-backup.tar.gz -C /var/lib
sudo systemctl start powerdns-admin-compose
```

## Troubleshooting

### Container won't start

```bash
# Check Docker logs
docker logs powerdns-admin

# Check systemd logs
sudo journalctl -u powerdns-admin-compose -n 50

# Verify Docker is running
sudo systemctl status docker
```

### Can't access web interface

```bash
# Check if container is running
docker ps | grep powerdns-admin

# Check if port is listening
sudo netstat -tlnp | grep 9191

# Check firewall
sudo iptables -L -n | grep 9191
```

### Reset to defaults

```bash
# Stop and remove container
cd /etc/powerdns-admin
docker-compose down

# Remove data (⚠️ THIS DELETES ALL DATA)
sudo rm -rf /var/lib/powerdns-admin/*

# Restart
sudo systemctl start powerdns-admin-compose
```

## See Also

- [PowerDNS Admin GitHub](https://github.com/PowerDNS-Admin/PowerDNS-Admin)
- [PowerDNS Documentation](../../docs/powerdns.md)
- [Official Docker Image](https://hub.docker.com/r/ngoduykhanh/powerdns-admin)

