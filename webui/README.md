# Router WebUI

A modern web-based monitoring and management interface for the NixOS router, built with FastAPI (backend) and React + Flowbite (frontend).

## Architecture

### Backend (FastAPI + PostgreSQL)
- **FastAPI** - Modern async Python web framework
- **PostgreSQL** - Time-series data storage for metrics
- **WebSockets** - Real-time metrics broadcasting (2-second interval)
- **JWT Authentication** - System user authentication via PAM
- **SQLAlchemy** - Async ORM for database operations

### Frontend (React + TypeScript)
- **React 18** - Modern UI library
- **TypeScript** - Type-safe development
- **Flowbite React** - Tailwind CSS component library
- **Recharts** - Beautiful, responsive charts
- **Vite** - Fast build tooling

### Data Collection
- **psutil** - System metrics (CPU, memory, load, uptime)
- **Kea DHCP** - Parse lease file for client information
- **Unbound** - DNS statistics via control socket
- **Systemd** - Service status monitoring
- **Network interfaces** - Real-time bandwidth monitoring

## Features (Stage 1 - Display Only)

✅ **Real-time Dashboard**
- System metrics (CPU, memory, load average, uptime)
- Network interface statistics with live bandwidth graphs
- Service status monitoring
- DHCP client list with search/filter

✅ **Network Monitoring**
- Per-interface bandwidth charts
- Historical data visualization
- Upload/download rates in real-time

✅ **Authentication**
- System user login (PAM)
- JWT token-based sessions
- Secure WebSocket connections

✅ **Responsive Design**
- Mobile-friendly Flowbite components
- Dark mode support (via Tailwind)
- Clean, modern UI

## Development Setup

### Backend Development

```bash
cd webui/backend

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export DATABASE_URL="postgresql+asyncpg://router_webui:password@localhost/router_webui"
export JWT_SECRET_KEY="your-secret-key-here"
export DEBUG=true

# Run development server
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8080

# Access API docs
open http://localhost:8080/docs
```

### Frontend Development

```bash
cd webui/frontend

# Install dependencies
npm install

# Run development server (with proxy to backend)
npm run dev

# Access frontend
open http://localhost:3000
```

### Database Setup (Development)

```bash
# Create PostgreSQL database
createdb router_webui

# Run schema
psql router_webui < webui/backend/schema.sql
```

## Production Deployment (NixOS)

### 1. Enable in `configuration.nix`

```nix
{
  imports = [
    # ... other modules
    ./modules/webui.nix
  ];

  services.router-webui = {
    enable = true;
    port = 8080;
    collectionInterval = 2;  # seconds
  };

  # Open firewall for WebUI
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
```

### 2. Build Frontend

```bash
cd webui/frontend
npm install
npm run build
```

### 3. Deploy

```bash
sudo nixos-rebuild switch
```

### 4. Access

Open `http://router-ip:8080` in your browser

**Default credentials:** Your system user account

## API Endpoints

### Authentication
- `POST /api/auth/login` - Login with system credentials
- `GET /api/auth/me` - Get current user info
- `POST /api/auth/logout` - Logout

### Real-time Data
- `WS /ws?token={jwt}` - WebSocket for real-time metrics

### Historical Data
- `GET /api/history/system` - System metrics history
- `GET /api/history/interface/{name}` - Interface statistics history
- `GET /api/history/bandwidth/{network}?period={1h|24h|7d|30d}` - Bandwidth history
- `GET /api/history/services` - Service status history

### Health Check
- `GET /api/health` - Service health status

## WebSocket Message Format

```json
{
  "type": "metrics",
  "data": {
    "timestamp": "2024-01-01T00:00:00",
    "system": {
      "cpu_percent": 25.5,
      "memory_percent": 45.2,
      "load_avg_1m": 0.85,
      ...
    },
    "interfaces": [
      {
        "interface": "ppp0",
        "rx_rate_mbps": 15.2,
        "tx_rate_mbps": 3.8,
        ...
      }
    ],
    "services": [...],
    "dhcp_clients": [...],
    "dns_stats": [...]
  }
}
```

## Database Schema

### Tables
- `system_metrics` - System-wide metrics time-series
- `interface_stats` - Network interface statistics
- `dhcp_leases` - Current DHCP leases snapshot
- `service_status` - Service status time-series
- `config_changes` - Configuration change log (Stage 2)

### Indexes
- Optimized for time-series queries
- Composite indexes on (interface, timestamp) and (service_name, timestamp)

## Configuration

### Backend Environment Variables

```bash
DATABASE_URL=postgresql+asyncpg://user:pass@host/db
JWT_SECRET_KEY=your-secret-key
JWT_ALGORITHM=HS256
JWT_EXPIRATION_MINUTES=1440
COLLECTION_INTERVAL=2
KEA_LEASE_FILE=/var/lib/kea/dhcp4.leases
ROUTER_CONFIG_FILE=/etc/nixos/router-config.nix
DEBUG=false
```

### Frontend Environment Variables

```bash
VITE_API_URL=http://localhost:8080
VITE_WS_URL=ws://localhost:8080/ws
```

## Stage 2 (Future) - Configuration Management

Planned features:
- Edit DHCP settings via WebUI
- Modify DNS records
- Manage firewall rules
- View configuration change history
- Live `nixos-rebuild` progress
- Configuration rollback capability

## Troubleshooting

### Backend Issues

```bash
# Check service status
sudo systemctl status router-webui-backend

# View logs
sudo journalctl -u router-webui-backend -f

# Test database connection
psql -h localhost -U router_webui -d router_webui -c "SELECT COUNT(*) FROM system_metrics;"
```

### Frontend Issues

```bash
# Check if backend is accessible
curl http://localhost:8080/api/health

# Rebuild frontend
cd webui/frontend
rm -rf node_modules dist
npm install
npm run build
```

### WebSocket Connection Issues

1. Verify JWT token is valid
2. Check firewall allows port 8080
3. Ensure backend service is running
4. Check browser console for errors

## Performance

### Backend
- ~50-80MB RAM usage
- 2-second data collection interval
- Async I/O for non-blocking operations
- Database connection pooling

### Frontend
- Minimal bundle size with Vite
- Lazy-loaded routes
- Efficient WebSocket reconnection
- Buffered metrics for sparklines (last 60 points)

## Security

- PAM-based authentication
- JWT tokens with configurable expiration
- HTTPS support (via reverse proxy)
- Systemd security hardening (NoNewPrivileges, ProtectSystem, etc.)
- CORS configuration for development
- SQL injection prevention (SQLAlchemy ORM)
- XSS protection (React escaping)

## Contributing

This is part of the NixOS router project. Follow the main project's contribution guidelines.

## License

Same as the parent project.

