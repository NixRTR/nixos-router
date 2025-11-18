// Copy index.html to 404.html for GitHub Pages client-side routing
// Also create .nojekyll file to disable Jekyll processing
import { copyFileSync, writeFileSync } from 'fs';

copyFileSync('dist/index.html', 'dist/404.html');
console.log('Copied index.html to 404.html for GitHub Pages');

// Create .nojekyll file to disable Jekyll processing on GitHub Pages
writeFileSync('dist/.nojekyll', '');
console.log('Created .nojekyll file for GitHub Pages');

