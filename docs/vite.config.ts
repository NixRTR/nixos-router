import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react({
      // Enable automatic JSX runtime (smaller bundle)
      jsxRuntime: 'automatic',
    }),
  ],
  // Base path: defaults to /docs/ for local, set VITE_BASE_PATH=/nixos-router/ for GitHub Pages
  base: process.env.VITE_BASE_PATH || '/docs/',
  build: {
    // Enable minification and compression
    minify: 'esbuild',
    cssMinify: true,
    
    // Optimize chunking
    rollupOptions: {
      output: {
        manualChunks: {
          // Split React and React DOM into separate chunk
          'react-vendor': ['react', 'react-dom', 'react-router-dom'],
          // Split UI library (Flowbite)
          'ui-vendor': ['flowbite-react', 'flowbite'],
          // Split markdown renderer
          'markdown-vendor': ['react-markdown', 'remark-gfm'],
        },
        // Optimize chunk file names for better caching
        chunkFileNames: 'assets/js/[name]-[hash].js',
        entryFileNames: 'assets/js/[name]-[hash].js',
        assetFileNames: 'assets/[ext]/[name]-[hash].[ext]',
      },
    },
    // Lower chunk size warning to catch large bundles early
    chunkSizeWarningLimit: 500,
    
    // Disable source maps for production
    sourcemap: false,
    
    // Optimize asset inlining threshold
    assetsInlineLimit: 4096, // 4KB - inline small assets
    
    // Enable tree shaking and dead code elimination
    target: 'esnext',
    modulePreload: {
      polyfill: false, // Modern browsers support module preload
    },
  },
  
  // Optimize dependencies
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      'react-router-dom',
    ],
  },
})
