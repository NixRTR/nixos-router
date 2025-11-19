// Clean up temporary WebP files from public/screenshots after build
// These files are generated during prebuild and copied to dist by Vite
import { readdirSync, unlinkSync, existsSync } from 'fs';
import { join, extname } from 'path';

const screenshotsDir = join(process.cwd(), 'public', 'screenshots');

try {
  // Only clean up if the directory exists
  if (!existsSync(screenshotsDir)) {
    console.log('Screenshots directory does not exist, skipping cleanup');
    process.exit(0);
  }

  // Read all files in the screenshots directory
  const files = readdirSync(screenshotsDir);
  
  // Filter to only WebP files (exclude originals, README.md, manifest.json, etc.)
  const webpFiles = files.filter(file => {
    return extname(file).toLowerCase() === '.webp';
  });

  // Delete each WebP file
  let deletedCount = 0;
  for (const file of webpFiles) {
    const filePath = join(screenshotsDir, file);
    try {
      unlinkSync(filePath);
      deletedCount++;
    } catch (error) {
      console.warn(`Failed to delete ${file}:`, error);
    }
  }

  if (deletedCount > 0) {
    console.log(`Cleaned up ${deletedCount} temporary WebP file(s) from public/screenshots/`);
  } else {
    console.log('No WebP files to clean up');
  }
} catch (error) {
  console.error('Error cleaning up WebP files:', error);
  // Don't fail the build if cleanup fails
  process.exit(0);
}

