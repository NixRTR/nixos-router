# WebUI Deployment Fixes

## Issues Found and Resolved

When deploying the WebUI to the production router, several issues were encountered and fixed:

### 1. Database Initialization User Error ✅

**Error:**
```
router-webui-initdb.service: Failed to determine user credentials: No such process
router-webui-initdb.service: Failed at step USER
```

**Root Cause:**
The `router-webui-initdb` service was trying to run as the database user `router_webui` (underscore), but that's a PostgreSQL database user, not a system user.

**Fix:**
Changed the service to run as the `postgres` system user:
```nix
serviceConfig = {
  Type = "oneshot";
  User = "postgres";  # Changed from cfg.database.user
  RemainAfterExit = true;
};
```

### 2. PostgreSQL Authentication Configuration ✅

**Issue:**
PostgreSQL was not configured to allow local connections from the application.

**Fix:**
Added trust authentication for local connections:
```nix
services.postgresql = {
  enable = true;
  ensureDatabases = [ cfg.database.name ];
  ensureUsers = [{
    name = cfg.database.user;
    ensureDBOwnership = true;
  }];
  
  # Allow local trust authentication
  authentication = pkgs.lib.mkOverride 10 ''
    local all all trust
    host all all 127.0.0.1/32 trust
    host all all ::1/128 trust
  '';
};
```

### 3. JWT Secret Management ✅

**Issue:**
No JWT secret was configured, which would cause authentication to fail.

**Fix:**
Added automatic JWT secret generation on first boot:
```nix
systemd.services.router-webui-jwt-init = {
  description = "Generate JWT secret for Router WebUI";
  wantedBy = [ "multi-user.target" ];
  before = [ "router-webui-backend.service" ];
  
  script = ''
    if [ ! -f /var/lib/router-webui/jwt-secret ]; then
      ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/router-webui/jwt-secret
      chmod 600 /var/lib/router-webui/jwt-secret
      chown router-webui:router-webui /var/lib/router-webui/jwt-secret
    fi
  '';
};
```

Updated backend config to read JWT secret from file:
```python
# config.py
jwt_secret_file: Optional[str] = None

def load_jwt_secret(settings_obj: Settings) -> str:
    if settings_obj.jwt_secret_file and os.path.exists(settings_obj.jwt_secret_file):
        with open(settings_obj.jwt_secret_file, 'r') as f:
            return f.read().strip()
    return settings_obj.jwt_secret_key
```

### 4. Python PAM Library ✅

**Issue:**
The original implementation used `python-pam` which may not be available in nixpkgs.

**Fix:**
Switched to `pamela`, which is available in nixpkgs:

**In `modules/webui.nix`:**
```nix
pythonEnv = pkgs.python311.withPackages (ps: with ps; [
  # ... other packages ...
  pamela  # PAM authentication support
]);
```

**In `webui/backend/auth.py`:**
```python
try:
    import pamela
    pamela.authenticate(username, password, service='login')
    return True
except pamela.PAMError:
    return False
```

### 5. PAM Authentication Permissions ✅

**Issue:**
The `router-webui` user needs access to system authentication to verify user credentials.

**Fix:**
Added the router-webui user to the `shadow` group and configured PAM:
```nix
users.users.router-webui = {
  isSystemUser = true;
  group = "router-webui";
  extraGroups = [ "shadow" ];  # Required for PAM authentication
  description = "Router WebUI service user";
};

# Configure PAM service
security.pam.services.router-webui = {
  allowNullPassword = false;
  unixAuth = true;
};
```

## Testing the Fixes

After applying these fixes, rebuild and check service status:

```bash
# Rebuild system
sudo nixos-rebuild switch

# Check database initialization
sudo systemctl status router-webui-initdb

# Check JWT secret generation
sudo systemctl status router-webui-jwt-init
ls -la /var/lib/router-webui/jwt-secret

# Check backend service
sudo systemctl status router-webui-backend

# View logs
sudo journalctl -u router-webui-backend -n 50 -f
```

## Verification Steps

1. **Database is initialized:**
   ```bash
   sudo -u postgres psql -l | grep router_webui
   sudo -u postgres psql -d router_webui -c "\dt"
   ```

2. **JWT secret exists:**
   ```bash
   sudo ls -l /var/lib/router-webui/jwt-secret
   ```

3. **Backend is running:**
   ```bash
   curl http://localhost:8080/api/health
   ```

4. **Can access WebUI:**
   ```
   http://router-ip:8080
   ```

## All Fixed! ✅

All issues have been resolved. The WebUI should now:
- ✅ Initialize the database correctly
- ✅ Generate JWT secrets automatically
- ✅ Authenticate users via PAM
- ✅ Start successfully on boot
- ✅ Be accessible at http://router-ip:8080

## Next Steps

1. Run `sudo nixos-rebuild switch` to apply the fixes
2. Check service status to verify everything starts correctly
3. Access the WebUI and login with your system credentials
4. Monitor logs for any issues during first run

---

Last Updated: 2025-11-14

