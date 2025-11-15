# Router WebUI Deployment Guide

## Quick Start

### Prerequisites
- NixOS router with the configuration from this repository
- System user account for authentication
- Network access to the router

### Step 1: Enable WebUI in Configuration

Edit `configuration.nix` and add:

```nix
{
  imports = [
    # ... existing imports
    ./modules/webui.nix
  ];

  services.router-webui = {
    enable = true;
    port = 8080;
  };

  # Open firewall
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```

### Step 2: Build and Deploy

```bash
# From your router
sudo nixos-rebuild switch
```

### Step 3: Access WebUI

1. Open browser: `http://<router-ip>:8080`
2. Login with your system username/password
3. View real-time router metrics!

## Development Workflow

### Backend Development

```bash
cd webui/backend

# Create Python virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set up environment
export DATABASE_URL="postgresql+asyncpg://router_webui:password@localhost/router_webui"
export JWT_SECRET_KEY="dev-secret-key-change-in-production"
export DEBUG="true"

# Run development server
uvicorn main:app --reload --host 0.0.0.0 --port 8080

# API docs available at: http://localhost:8080/docs
```

### Frontend Development

```bash
cd webui/frontend

# Install dependencies
npm install

# Run development server (proxies API to localhost:8080)
npm run dev

# Frontend available at: http://localhost:3000
```

### Testing

```bash
# Backend tests
cd webui/backend
pytest

# Frontend tests (if implemented)
cd webui/frontend
npm test
```

## Production Configuration

### Security Best Practices

1. **Use sops for JWT secret:**

```nix
# In modules/secrets.nix
sops.secrets."webui-jwt-secret" = {
  sopsFile = ./secrets.yaml;
  owner = "router-webui";
  mode = "0400";
};

# In configuration.nix
services.router-webui.jwtSecretFile = config.sops.secrets."webui-jwt-secret".path;
```

2. **Use HTTPS (via reverse proxy):**

```nix
services.nginx = {
  enable = true;
  virtualHosts."router.jeandr.net" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:8080";
      proxyWebsockets = true;
    };
  };
};
```

3. **Restrict access to local network:**

```nix
networking.firewall.interfaces."br0".allowedTCPPorts = [ 8080 ];
# Only accessible from HOMELAB network
```

### Performance Tuning

```nix
services.router-webui = {
  enable = true;
  port = 8080;
  collectionInterval = 5;  # Reduce to 5 seconds if needed
  
  database = {
    host = "localhost";
    port = 5432;
    name = "router_webui";
    user = "router_webui";
  };
};

# PostgreSQL tuning
services.postgresql = {
  settings = {
    shared_buffers = "256MB";
    effective_cache_size = "1GB";
    maintenance_work_mem = "64MB";
    max_connections = 20;
  };
};
```

### Data Retention

Edit `webui/backend/config.py`:

```python
# Historical Data Retention
metrics_retention_days: int = 30  # Keep 30 days of data
```

Add a cleanup job:

```nix
systemd.timers.router-webui-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.router-webui-cleanup = {
  script = ''
    ${pkgs.postgresql}/bin/psql -U router_webui -d router_webui -c "
      DELETE FROM system_metrics WHERE timestamp < NOW() - INTERVAL '30 days';
      DELETE FROM interface_stats WHERE timestamp < NOW() - INTERVAL '30 days';
      DELETE FROM service_status WHERE timestamp < NOW() - INTERVAL '30 days';
    "
  '';
};
```

## Troubleshooting

### Issue: Cannot connect to WebUI

**Check:**
1. Service is running: `sudo systemctl status router-webui-backend`
2. Port is open: `sudo ss -tlnp | grep 8080`
3. Firewall allows access: `sudo iptables -L | grep 8080`

**Solution:**
```bash
# Restart service
sudo systemctl restart router-webui-backend

# Check logs
sudo journalctl -u router-webui-backend -n 50
```

### Issue: WebSocket disconnects frequently

**Check:**
1. Network stability
2. JWT token expiration (default: 24 hours)
3. Backend service crashes

**Solution:**
```bash
# Increase JWT expiration
# Edit webui/backend/config.py:
jwt_expiration_minutes: int = 60 * 48  # 48 hours

# Rebuild
sudo nixos-rebuild switch
```

### Issue: Database connection errors

**Check:**
1. PostgreSQL is running: `sudo systemctl status postgresql`
2. Database exists: `sudo -u postgres psql -l | grep router_webui`
3. User has permissions

**Solution:**
```bash
# Recreate database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS router_webui;"
sudo -u postgres psql -c "CREATE DATABASE router_webui OWNER router_webui;"
sudo -u router_webui psql -d router_webui < webui/backend/schema.sql
```

### Issue: Frontend shows old data

**Solution:**
```bash
# Clear browser cache and reload
# Or rebuild frontend:
cd webui/frontend
rm -rf dist node_modules
npm install
npm run build
sudo nixos-rebuild switch
```

### Issue: High CPU usage

**Check:**
- Collection interval is too aggressive
- Too many WebSocket connections

**Solution:**
```nix
# Increase collection interval
services.router-webui.collectionInterval = 5;  # 5 seconds instead of 2
```

## Monitoring

### Check WebUI Health

```bash
# Health endpoint
curl http://localhost:8080/api/health

# Expected response:
# {"status":"healthy","active_connections":1}
```

### Monitor Resource Usage

```bash
# Backend service
systemctl status router-webui-backend

# Database size
sudo -u postgres psql -d router_webui -c "
  SELECT pg_size_pretty(pg_database_size('router_webui'));
"

# Active WebSocket connections
sudo journalctl -u router-webui-backend | grep "WebSocket"
```

### Logs

```bash
# Backend logs (last 100 lines)
sudo journalctl -u router-webui-backend -n 100

# Real-time logs
sudo journalctl -u router-webui-backend -f

# PostgreSQL logs
sudo journalctl -u postgresql -f
```

## Backup and Restore

### Backup Database

```bash
# Backup metrics data
sudo -u postgres pg_dump router_webui > router_webui_backup_$(date +%Y%m%d).sql

# Backup with compression
sudo -u postgres pg_dump router_webui | gzip > router_webui_backup_$(date +%Y%m%d).sql.gz
```

### Restore Database

```bash
# Restore from backup
sudo -u postgres psql router_webui < router_webui_backup_20240101.sql

# Or from compressed backup
gunzip < router_webui_backup_20240101.sql.gz | sudo -u postgres psql router_webui
```

## Upgrading

### Update WebUI Code

```bash
# Pull latest code
cd /path/to/nixos-router
git pull

# Rebuild
sudo nixos-rebuild switch
```

### Database Migrations

If database schema changes are needed:

```bash
cd webui/backend

# Generate migration
alembic revision --autogenerate -m "Description of changes"

# Apply migration
alembic upgrade head
```

## Stage 2 Preview (Configuration Management)

Coming soon:
- Edit network settings via WebUI
- Modify DHCP/DNS configuration
- Live `nixos-rebuild` progress
- Configuration rollback
- Change history tracking

Stay tuned!

