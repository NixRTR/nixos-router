# Documentation Build Instructions

## Pre-Built Distribution Method

This documentation site uses **pre-built distribution files** committed to the repository. This approach:
- ✅ Avoids npm/network issues during NixOS builds
- ✅ Faster NixOS rebuilds (no npm install needed)
- ✅ Guaranteed reproducible deployments
- ✅ Works in Nix's sandboxed build environment

## When to Rebuild

You only need to rebuild the documentation when:
- Making changes to React components
- Updating dependencies
- Modifying TypeScript files
- Changing styles or content
- Updating documentation content

## How to Rebuild

### Prerequisites
- Node.js 22+ (check with `node --version`)
- npm 8+ (check with `npm --version`)

### Build Steps

```bash
cd docs

# Install dependencies (first time or after package.json changes)
npm install

# Build for production (for router deployment with /docs/ base path)
VITE_BASE_PATH=/docs/ npm run build
```

This creates/updates the `dist/` folder with optimized production files.

### Commit the Build

After building, commit the changes:

```bash
git add dist/ src/ package-lock.json
git commit -m "Update documentation build"
git push
```

## Build Output

The `dist/` folder contains:
```
dist/
├── index.html           # Entry point
├── assets/
│   ├── js/             # Bundled JavaScript chunks
│   └── css/            # Bundled CSS
└── ...
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

### Router Deployment
The NixOS module automatically:
1. Copies `dist/` to `/var/lib/router-webui/docs/`
2. Serves files via the FastAPI backend at `/docs` route
3. Makes the docs available at `http://router:8080/docs`

No manual steps needed on the router!

### GitHub Pages Deployment
GitHub Actions automatically:
1. Builds the docs with `VITE_BASE_PATH=/nixos-router/` for GitHub Pages
2. Deploys to `https://beardedtek.github.io/nixos-router/`

The GitHub Pages build uses a different base path than the router build.

## Base Paths

- **Router**: Build with `VITE_BASE_PATH=/docs/` (committed to repo)
- **GitHub Pages**: Built by GitHub Actions with `VITE_BASE_PATH=/nixos-router/`

## Troubleshooting

### Build Fails with Node Version Error

**Problem:** `Unsupported engine for X: wanted: {"node":">=14.0.0"}`

**Solution:** Upgrade Node.js to version 22 or higher.

### Build Fails with TypeScript Errors

**Problem:** Type errors in `.tsx` files

**Solution:** 
1. Check `tsconfig.json` exists
2. Run `npm install` to ensure all types are installed
3. Fix the reported TypeScript errors

### Build Output is Missing

**Problem:** `dist/` folder doesn't exist after `npm run build`

**Solution:**
1. Check for build errors in terminal
2. Ensure `vite.config.ts` is present
3. Run `npm install` first

### Changes Not Reflected in Router

**Problem:** Made changes but router still shows old docs

**Solution:**
1. Rebuild: `VITE_BASE_PATH=/docs/ npm run build`
2. Commit: `git add dist/ && git commit -m "Update docs build"`
3. On router: `sudo nixos-rebuild switch`
4. Clear browser cache (Ctrl+Shift+R)

---

**Last Updated:** 2025-01-15

