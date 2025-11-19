import { Link } from 'react-router-dom';
import { MarkdownContent } from '../components/MarkdownContent';
import { Modal } from 'flowbite-react';
import { useEffect, useState, useRef } from 'react';
import { HiChevronLeft, HiChevronRight, HiX } from 'react-icons/hi';

const homeContent = `# NixOS Router Documentation

Welcome to the NixOS Router documentation. This guide will help you install, configure, and maintain your NixOS-based router.

## Quick Links

- [Installation Guide](/installation) - Get started with installing the router
- [Upgrading Guide](/upgrading) - Learn how to upgrade your router
- [Verification](/verification) - Verify your router is working correctly
- [Configuration](/configuration) - Configure all aspects of your router

## Features

- Multi-network support (isolated LAN segments)
- DHCP server (Kea)
- DNS server (Unbound with ad-blocking)
- Web dashboard for monitoring
- Dynamic DNS updates (Linode)
- Firewall and NAT
- Secrets management via sops-nix

## Getting Started

1. Follow the [Installation Guide](/installation) to set up your router
2. Verify your installation using the [Verification Guide](/verification)
3. Customize your configuration using the [Configuration Guide](/configuration)

## Need Help?

- Check the [GitHub Issues](https://github.com/BeardedTek/nixos-router/issues)
- Review the [GitHub Repository](https://github.com/BeardedTek/nixos-router)
`;

interface ScreenshotManifest {
  generated: string;
  count: number;
  screenshots: Array<{
    file: string;
    original?: string;
    alt: string;
    size: number;
    originalSize?: number;
  }>;
}

export function Home() {
  const [screenshots, setScreenshots] = useState<Array<{ src: string; original: string; alt: string }>>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const basePath = import.meta.env.VITE_BASE_PATH || '/docs/';
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    // Load screenshots from manifest.json generated at build time
    const loadScreenshots = async () => {
      try {
        const manifestUrl = `${basePath}screenshots/manifest.json`;
        const response = await fetch(manifestUrl);
        
        if (response.ok) {
          const manifest: ScreenshotManifest = await response.json();
          const loadedScreenshots = manifest.screenshots.map(({ file, original, alt }) => ({
            src: `${basePath}screenshots/${file}`, // WebP for carousel
            original: original ? `${basePath}screenshots/${original}` : `${basePath}screenshots/${file}`, // Original for modal
            alt,
          }));
          setScreenshots(loadedScreenshots);
        } else {
          console.warn('Could not load screenshots manifest, using empty list');
          setScreenshots([]);
        }
      } catch (error) {
        console.error('Error loading screenshots manifest:', error);
        setScreenshots([]);
      }
    };
    
    loadScreenshots();
  }, [basePath]);

  // Auto-advance carousel every 5 seconds
  useEffect(() => {
    if (screenshots.length === 0 || isPaused) {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    intervalRef.current = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % screenshots.length);
    }, 5000);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [screenshots.length, isPaused]);

  const goToSlide = (index: number) => {
    setCurrentIndex(index);
    // Reset auto-advance timer
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }
    intervalRef.current = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % screenshots.length);
    }, 5000);
  };

  const goToPrevious = () => {
    goToSlide((currentIndex - 1 + screenshots.length) % screenshots.length);
  };

  const goToNext = () => {
    goToSlide((currentIndex + 1) % screenshots.length);
  };

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      {/* Screenshot Carousel */}
      {screenshots.length > 0 && (
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm overflow-hidden">
          {/* Main Image Display */}
          <div className="relative h-64 sm:h-80 xl:h-96 group bg-gray-100 dark:bg-gray-700">
            {/* Previous Arrow */}
            <button
              onClick={goToPrevious}
              onMouseEnter={() => setIsPaused(true)}
              onMouseLeave={() => setIsPaused(false)}
              className="absolute left-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-2 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200"
              aria-label="Previous image"
            >
              <HiChevronLeft className="w-6 h-6" />
            </button>

            {/* Main Image with fade transition */}
            <div 
              className="relative w-full h-full cursor-pointer lg:cursor-zoom-in"
              onClick={() => {
                // Only open modal on lg screens and larger
                if (window.innerWidth >= 1024) {
                  setModalOpen(true);
                }
              }}
            >
              {screenshots.map((screenshot, index) => (
                <img
                  key={index}
                  src={screenshot.src}
                  alt={screenshot.alt}
                  className={`absolute inset-0 w-full h-full object-contain transition-opacity duration-500 ${
                    index === currentIndex ? 'opacity-100' : 'opacity-0'
                  }`}
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              ))}
            </div>

            {/* Next Arrow */}
            <button
              onClick={goToNext}
              onMouseEnter={() => setIsPaused(true)}
              onMouseLeave={() => setIsPaused(false)}
              className="absolute right-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-2 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200"
              aria-label="Next image"
            >
              <HiChevronRight className="w-6 h-6" />
            </button>
          </div>

          {/* Thumbnails */}
          <div className="p-4 bg-gray-50 dark:bg-gray-900 border-t border-gray-200 dark:border-gray-700">
            <div className="flex gap-2 overflow-x-auto scrollbar-hide justify-center">
              {screenshots.map((screenshot, index) => (
                <button
                  key={index}
                  onClick={() => goToSlide(index)}
                  onMouseEnter={() => setIsPaused(true)}
                  onMouseLeave={() => setIsPaused(false)}
                  className={`flex-shrink-0 w-20 h-20 rounded-lg overflow-hidden border-2 transition-all duration-200 ${
                    index === currentIndex
                      ? 'border-blue-500 dark:border-blue-400 ring-2 ring-blue-500/50 dark:ring-blue-400/50 scale-105'
                      : 'border-gray-300 dark:border-gray-600 hover:border-gray-400 dark:hover:border-gray-500 opacity-70 hover:opacity-100'
                  }`}
                  aria-label={`Go to ${screenshot.alt}`}
                >
                  <img
                    src={screenshot.src}
                    alt={screenshot.alt}
                    className="w-full h-full object-cover"
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none';
                    }}
                  />
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Screenshot Modal */}
      <Modal show={modalOpen} onClose={() => setModalOpen(false)} size="7xl">
        <Modal.Header>
          <div className="flex items-center justify-between w-full">
            <span>{screenshots[currentIndex]?.alt || 'Screenshot'}</span>
          </div>
        </Modal.Header>
        <Modal.Body>
          <div className="relative">
            {/* Navigation arrows in modal */}
            <button
              onClick={(e) => {
                e.stopPropagation();
                goToPrevious();
              }}
              className="absolute left-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-3 rounded-full"
              aria-label="Previous image"
            >
              <HiChevronLeft className="w-8 h-8" />
            </button>

            <img
              src={screenshots[currentIndex]?.original || screenshots[currentIndex]?.src}
              alt={screenshots[currentIndex]?.alt}
              className="w-full h-auto max-h-[80vh] object-contain mx-auto"
              onError={(e) => {
                // Fallback to WebP if original fails
                const img = e.target as HTMLImageElement;
                if (img.src !== screenshots[currentIndex]?.src) {
                  img.src = screenshots[currentIndex]?.src;
                } else {
                  img.style.display = 'none';
                }
              }}
            />

            <button
              onClick={(e) => {
                e.stopPropagation();
                goToNext();
              }}
              className="absolute right-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-3 rounded-full"
              aria-label="Next image"
            >
              <HiChevronRight className="w-8 h-8" />
            </button>
          </div>
        </Modal.Body>
      </Modal>

      {/* Documentation Content */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={homeContent} />
      </div>
    </div>
  );
}

