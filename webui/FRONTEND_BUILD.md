# Frontend Build Setup ✅

The frontend is now configured to build automatically during `nixos-rebuild switch`!

## What Was Added

### 1. **Frontend Build Derivation**
```nix
frontendBuild = pkgs.stdenv.mkDerivation {
  name = "router-webui-frontend";
  src = frontendSrc;
  buildInputs = [ pkgs.nodejs_20 ];
  
  buildPhase = ''
    npm install --legacy-peer-deps
    npm run build
  '';
  
  installPhase = ''
    cp -r dist/* $out/
  '';
};
```

This builds the React frontend with Vite during NixOS build.

### 2. **Frontend Installation Service**
```nix
systemd.services.router-webui-frontend-install = {
  description = "Install Router WebUI Frontend";
  # Copies built frontend to /var/lib/router-webui/frontend
};
```

This service runs on boot and copies the built frontend files to the state directory.

### 3. **Backend Dependency**
The backend service now depends on the frontend installation, ensuring the UI is ready when the backend starts.

## What Happens on Rebuild

When you run `sudo nixos-rebuild switch`:

1. **Build Phase (First Time - Takes ~5 minutes)**
   - Downloads Node.js and npm dependencies
   - Installs React, Vite, Flowbite, Tailwind CSS, etc.
   - Compiles TypeScript to JavaScript
   - Bundles the frontend with Vite
   - Optimizes assets for production

2. **Installation Phase**
   - Copies built frontend to `/var/lib/router-webui/frontend/`
   - Sets correct permissions

3. **Service Start**
   - Backend starts and detects frontend files
   - Serves the React app at `http://router:8080`

## Expected Build Output

During rebuild, you'll see:
```
building 'router-webui-frontend'...
unpacking sources...
running buildPhase...
npm install --legacy-peer-deps
added 542 packages in 45s
npm run build
vite v5.x.x building for production...
✓ 234 modules transformed.
dist/index.html                  0.45 kB
dist/assets/index-abc123.css    12.34 kB
dist/assets/index-xyz789.js    234.56 kB
✓ built in 8.42s
```

## After Rebuild

Access the WebUI:
```
http://192.168.2.1:8080  (from HOMELAB)
http://192.168.3.1:8080  (from LAN)
```

You should see:
- ✅ Login page (Flowbite React UI)
- ✅ Dashboard with real-time metrics
- ✅ Network bandwidth charts
- ✅ DHCP client list
- ✅ Service status monitoring

## Troubleshooting

### Build Takes Too Long
The first build downloads all npm packages. Subsequent rebuilds are much faster (cached).

### Frontend Not Showing
```bash
# Check if frontend was installed
ls -la /var/lib/router-webui/frontend/

# Should see:
# index.html
# assets/
#   ├── index-[hash].js
#   ├── index-[hash].css
#   └── ...

# Check backend logs
sudo journalctl -u router-webui-backend -n 50

# Should see:
# "Serving frontend assets from /var/lib/router-webui/frontend/assets"
```

### Still Getting API Response
If you still see JSON instead of the UI:
1. Clear browser cache (Ctrl+Shift+R)
2. Check browser console for errors (F12)
3. Verify frontend files exist (see above)

### Build Fails
If npm build fails:
```bash
# Check the build log
journalctl -xe | grep router-webui-frontend

# Common issues:
# - Network connectivity (downloading npm packages)
# - Disk space
# - TypeScript compilation errors
```

## Build Time Estimates

- **First build:** 5-10 minutes (depends on internet speed)
- **Subsequent builds:** 1-2 minutes (npm cache + Nix cache)

## What Gets Built

- **Frontend (React + Vite):**
  - React 18
  - Flowbite React components
  - Recharts for graphs
  - Tailwind CSS
  - TypeScript compiled to JavaScript
  - Optimized and minified bundles

- **Size:**
  - Uncompressed: ~2-3 MB
  - Gzipped: ~500 KB

## Ready to Build!

Run this to build and deploy the frontend:

```bash
sudo nixos-rebuild switch
```

**Note:** The first rebuild will take longer than usual while it builds the frontend. This is normal!

After it completes, refresh your browser at `http://router:8080` and you'll see the beautiful WebUI! 🎉

---

Last Updated: 2025-11-14

