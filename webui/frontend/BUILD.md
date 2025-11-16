# Frontend Build Instructions

## Pre-Built Distribution Method

This frontend uses **pre-built distribution files** committed to the repository. This approach:
- ✅ Avoids npm/network issues during NixOS builds
- ✅ Faster NixOS rebuilds (no npm install needed)
- ✅ Guaranteed reproducible deployments
- ✅ Works in Nix's sandboxed build environment

## When to Rebuild

You only need to rebuild the frontend when:
- Making changes to React components
- Updating dependencies
- Modifying TypeScript files
- Changing styles or assets

## How to Rebuild

### Prerequisites
- Node.js 18+ (check with `node --version`)
- npm 8+ (check with `npm --version`)

### Build Steps

```bash
cd webui/frontend

# Install dependencies (first time or after package.json changes)
npm install

# Build for production
npm run build
```

This creates/updates the `dist/` folder with optimized production files.

### Commit the Build

After building, commit the changes:

```bash
git add dist/ src/ package-lock.json .gitignore
git commit -m "Update frontend build"
git push
```

## Build Output

The `dist/` folder contains:
```
dist/
├── index.html           # Entry point
├── assets/
│   ├── index-[hash].js  # Bundled JavaScript
│   ├── index-[hash].css # Bundled CSS
│   └── ...              # Other assets
└── vite.svg            # Favicon
```

## Development

For local development with hot reload:

```bash
npm run dev
```

This starts a development server at `http://localhost:5173` with:
- Hot module replacement
- Fast refresh
- Source maps for debugging

**Note:** Development mode doesn't update the `dist/` folder. Only `npm run build` does.

## Deployment

The NixOS module automatically:
1. Copies `dist/` to `/var/lib/router-webui/frontend/`
2. Serves files via the FastAPI backend
3. Makes the UI available at `http://router:8080`

No manual steps needed on the router!

## File Sizes

Typical build output:
- Total: ~2-3 MB uncompressed
- Gzipped: ~500 KB
- Main JS bundle: ~200-300 KB (gzipped)
- CSS bundle: ~10-20 KB (gzipped)

## Troubleshooting

### Build Fails with Node Version Error

**Problem:** `Unsupported engine for X: wanted: {"node":">=14.0.0"}`

**Solution:** Upgrade Node.js to version 18 or higher.

### Build Fails with TypeScript Errors

**Problem:** Type errors in `.tsx` files

**Solution:** 
1. Check `src/vite-env.d.ts` exists
2. Run `npm install` to ensure all types are installed
3. Fix the reported TypeScript errors

### Build Output is Missing

**Problem:** `dist/` folder doesn't exist after `npm run build`

**Solution:**
1. Check for build errors in terminal
2. Ensure `vite.config.ts` is present
3. Run `npm install` first

### Changes Not Reflected in Router

**Problem:** Made changes but router still shows old UI

**Solution:**
1. Rebuild: `npm run build`
2. Commit: `git add dist/ && git commit -m "Update build"`
3. On router: `sudo nixos-rebuild switch`
4. Clear browser cache (Ctrl+Shift+R)

---

**Last Updated:** 2025-11-15

