# NixOS Router Documentation

This directory contains the React-based documentation site for the NixOS Router project.

## Development

To run the documentation site locally:

\`\`\`bash
npm install
npm run dev
\`\`\`

The site will be available at `http://localhost:5173`.

## Building

To build the documentation site:

\`\`\`bash
npm run build
\`\`\`

The built site will be in the `dist/` directory.

## Deployment

The documentation is automatically built and deployed to GitHub Pages via GitHub Actions when changes are pushed to the `main` branch.

For local router deployment, the site is built by the NixOS module and served via the FastAPI backend.
