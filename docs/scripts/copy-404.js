// Copy index.html to 404.html for GitHub Pages client-side routing
// Only do this when building for GitHub Pages (VITE_BASE_PATH=/nixos-router/)
// Also create .nojekyll file to disable Jekyll processing
import { copyFileSync, writeFileSync } from 'fs';

const basePath = process.env.VITE_BASE_PATH || '';

// Only create 404.html for GitHub Pages builds
if (basePath === '/nixos-router/') {
  copyFileSync('dist/index.html', 'dist/404.html');
  console.log('Copied index.html to 404.html for GitHub Pages');
  
  // Create .nojekyll file to disable Jekyll processing on GitHub Pages
  writeFileSync('dist/.nojekyll', '');
  console.log('Created .nojekyll file for GitHub Pages');
} else {
  console.log('Skipping 404.html creation (not a GitHub Pages build)');
}

