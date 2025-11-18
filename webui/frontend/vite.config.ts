import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    react({
      // Enable automatic JSX runtime (smaller bundle)
      jsxRuntime: 'automatic',
    }),
  ],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true,
      },
    },
  },
  build: {
    // Enable minification and compression
    minify: 'esbuild', // Faster than terser, good compression
    cssMinify: true,
    
    // Optimize chunking
    rollupOptions: {
      output: {
        manualChunks: {
          // Split React and React DOM into separate chunk
          'react-vendor': ['react', 'react-dom', 'react-router-dom'],
          // Split charting library (Recharts is large) - only load when needed
          'charts': ['recharts'],
          // Split UI library (Flowbite)
          'ui-vendor': ['flowbite-react', 'flowbite'],
          // Split HTTP client
          'http-vendor': ['axios'],
        },
        // Optimize chunk file names for better caching
        chunkFileNames: 'assets/js/[name]-[hash].js',
        entryFileNames: 'assets/js/[name]-[hash].js',
        assetFileNames: 'assets/[ext]/[name]-[hash].[ext]',
      },
    },
    // Increase chunk size warning limit to 1000 KB (1 MB)
    // This is reasonable for a router admin interface
    chunkSizeWarningLimit: 1000,
    
    // Enable source maps for debugging (can disable in production)
    sourcemap: false,
    
    // Optimize asset inlining threshold (small assets will be inlined as base64)
    assetsInlineLimit: 4096, // 4KB - inline small assets
    
    // esbuild minification options
    // Note: drop_console is handled via esbuild's pure annotations or a plugin
    // For now, we rely on esbuild's default minification which is already quite good
  },
  
  // Optimize dependencies
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      'react-router-dom',
      'axios',
    ],
    // Exclude large dependencies that should be lazy loaded
    exclude: ['recharts'],
  },
})

