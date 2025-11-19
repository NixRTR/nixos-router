# Screenshots Directory

Add your screenshot images to this directory. The carousel on the Home page will **automatically detect and display all images** in this folder.

## How It Works

The system uses **dynamic screenshot detection**:
1. At build time, a script scans this directory and generates a `manifest.json` file
2. The React app loads the manifest and displays all discovered images
3. **No code changes needed** - just drop images in this folder!

## Supported Formats
- PNG (recommended)
- JPG/JPEG
- GIF

**Note:** All images are automatically converted to WebP format at build time for better performance. The original files are preserved, and WebP versions are used in the carousel. The modal viewer uses the original high-quality images.

**Build Process:**
- WebP files are generated in `public/screenshots/` during the build (these are ignored in git)
- Vite copies everything from `public/` to `dist/` during build
- WebP files in `dist/screenshots/` are committed to git (since `dist/` is committed)
- This ensures the WebP files are available when deploying to the router

## Naming Convention

**You can name your screenshots anything you want!** The system will:
- Automatically detect all image files
- Generate readable alt text from the filename
- Display them in alphabetical order

Examples:
- `dashboard.png` → "Dashboard"
- `network-monitoring.png` → "Network Monitoring"
- `device_usage.png` → "Device Usage"
- `my-custom-screenshot.jpg` → "My Custom Screenshot"

## Image Recommendations
- Recommended size: 1920x1080 or similar 16:9 aspect ratio
- File size: Keep under 500KB per image for faster loading
- Format: PNG for screenshots with text, JPG for photos

## Adding Screenshots

1. Drop your screenshot files into this directory (`docs/public/screenshots/`)
2. Name them whatever you want (e.g., `my-feature.png`)
3. Run `npm run build` - the manifest will be regenerated automatically
4. The carousel will display all images on the Home page

**Note:** The `manifest.json` file is auto-generated - don't edit it manually!

