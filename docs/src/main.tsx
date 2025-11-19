import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Initialize theme (dark/light) before React renders to avoid FOUC
(() => {
  try {
    const stored = localStorage.getItem('theme');
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const shouldDark = stored ? stored === 'dark' : prefersDark;
    const root = document.documentElement;
    if (shouldDark) {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }
  } catch {}
})();

// Add Plausible analytics - only for GitHub Pages, not for router's webui
// GitHub Pages builds use VITE_BASE_PATH=/nixos-router/, local builds use /docs/
if (import.meta.env.VITE_BASE_PATH === '/nixos-router/') {
  // Initialize plausible queue
  (window as any).plausible = (window as any).plausible || function() { 
    ((window as any).plausible.q = (window as any).plausible.q || []).push(arguments) 
  };

  // Add Plausible script
  const script = document.createElement('script');
  script.defer = true;
  script.setAttribute('data-domain', 'beardedtek.github.io');
  script.src = 'https://plausible.beardedtek.org/js/script.file-downloads.hash.outbound-links.js';
  document.head.appendChild(script);
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
