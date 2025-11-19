// Generate a manifest of all screenshots in the public/screenshots directory
// This runs at build time to automatically discover all screenshot images
// Also converts images to WebP format for better performance
import { readdirSync, statSync, existsSync } from 'fs';
import { join, extname, basename } from 'path';
import { writeFileSync } from 'fs';
import sharp from 'sharp';

const screenshotsDir = join(process.cwd(), 'public', 'screenshots');
const manifestPath = join(process.cwd(), 'public', 'screenshots', 'manifest.json');

// Supported image extensions (excluding .webp as we'll generate those)
const imageExtensions = ['.png', '.jpg', '.jpeg', '.gif'];

async function convertToWebP(inputPath, outputPath) {
  try {
    await sharp(inputPath)
      .webp({ quality: 80, effort: 4 }) // Reduced from 85 to 80 for smaller file size with minimal quality loss
      .toFile(outputPath);
    return true;
  } catch (error) {
    console.error(`Error converting ${inputPath} to WebP:`, error);
    return false;
  }
}

try {
  // Read all files in the screenshots directory
  const files = readdirSync(screenshotsDir);
  
  // Filter to only image files (exclude README.md, manifest.json, .webp files, etc.)
  const imageFiles = files.filter(file => {
    const ext = extname(file).toLowerCase();
    return imageExtensions.includes(ext);
  });

  const images = [];
  
  // Process each image file
  for (const file of imageFiles) {
    const fullPath = join(screenshotsDir, file);
    const stats = statSync(fullPath);
    const baseName = basename(file, extname(file));
    const webpFile = `${baseName}.webp`;
    const webpPath = join(screenshotsDir, webpFile);
    
    // Convert to WebP if it doesn't already exist or if source is newer
    let webpExists = existsSync(webpPath);
    if (webpExists) {
      const webpStats = statSync(webpPath);
      // Regenerate if source is newer
      if (stats.mtime > webpStats.mtime) {
        webpExists = false;
      }
    }
    
    if (!webpExists) {
      console.log(`Converting ${file} to WebP...`);
      const converted = await convertToWebP(fullPath, webpPath);
      if (!converted) {
        console.warn(`Failed to convert ${file} to WebP, skipping...`);
        continue;
      }
    }
    
    const webpStats = statSync(webpPath);
    
    // Generate description from filename: strip leading numbers, then convert to title case
    // Examples: "010-dark-mode" → "Dark Mode", "007-device-usage" → "Device Usage"
    let description = baseName
      .replace(/^\d+-/, '') // Remove leading digits and dash (e.g., "010-")
      .replace(/[-_]/g, ' ') // Replace hyphens and underscores with spaces
      .split(' ')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join(' ');
    
    images.push({
      file: webpFile, // Use WebP version
      original: file, // Keep reference to original
      alt: description, // Use description as alt text
      size: webpStats.size,
      originalSize: stats.size,
    });
  }
  
  // Sort by filename for consistent ordering
  images.sort((a, b) => a.file.localeCompare(b.file));

  // Write manifest
  const manifest = {
    generated: new Date().toISOString(),
    count: images.length,
    screenshots: images,
  };

  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8');
  console.log(`Generated screenshots manifest with ${images.length} images`);
  console.log('Images:', images.map(img => img.file).join(', '));
} catch (error) {
  console.error('Error generating screenshots manifest:', error);
  // Write empty manifest if directory doesn't exist or error occurs
  writeFileSync(manifestPath, JSON.stringify({ generated: new Date().toISOString(), count: 0, screenshots: [] }, null, 2), 'utf-8');
}

