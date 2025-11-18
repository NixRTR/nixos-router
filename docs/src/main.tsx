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

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
