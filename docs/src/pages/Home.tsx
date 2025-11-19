import { MarkdownContent } from '../components/MarkdownContent';
import { Modal } from 'flowbite-react';
import { useEffect, useState, useRef } from 'react';
import { HiChevronLeft, HiChevronRight } from 'react-icons/hi';

const homeContent = `# NixOS Router Documentation

Welcome to the NixOS Router documentation. This guide will help you install, configure, and maintain your NixOS-based router.

## Quick Links

    - [Installation Guide](/installation) - Get started with installing the router
    - [Upgrading Guide](/upgrading) - Learn how to upgrade your router
    - [Verification](/verification) - Verify your router is working correctly
    - [WebUI Documentation](/webui) - Learn about the web interface features
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
  const [modalImageIndex, setModalImageIndex] = useState(0); // Track which image was clicked for modal
  const [containerHeight, setContainerHeight] = useState<number | null>(null); // Dynamic container height
  const basePath = import.meta.env.VITE_BASE_PATH || '/docs/';
  const intervalRef = useRef<number | null>(null);
  const lastAutoAdvanceRef = useRef<number>(Date.now()); // Track when last AUTO advance happened (not manual)
  const imageContainerRef = useRef<HTMLDivElement>(null);

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

  // Measure all images and set container height to the tallest image
  useEffect(() => {
    if (screenshots.length === 0 || !imageContainerRef.current) return;

    const container = imageContainerRef.current;
    const containerWidth = container.offsetWidth - 32; // Account for px-4 padding (16px * 2)
    
    const measureImages = async () => {
      const imageHeights: number[] = [];
      
      // Load and measure each image
      const promises = screenshots.map((screenshot) => {
        return new Promise<number>((resolve) => {
          const img = new Image();
          img.onload = () => {
            // Calculate height based on container width while maintaining aspect ratio
            const aspectRatio = img.height / img.width;
            const calculatedHeight = containerWidth * aspectRatio;
            imageHeights.push(calculatedHeight);
            resolve(calculatedHeight);
          };
          img.onerror = () => {
            resolve(0);
          };
          img.src = screenshot.src;
        });
      });

      await Promise.all(promises);
      
      // Set container height to the maximum image height
      if (imageHeights.length > 0) {
        const maxHeight = Math.max(...imageHeights);
        setContainerHeight(maxHeight);
      }
    };

    // Wait for container to be rendered, then measure
    const timeoutId = setTimeout(() => {
      measureImages();
    }, 100);

    // Re-measure on window resize
    const handleResize = () => {
      if (container) {
        const newWidth = container.offsetWidth - 32;
        const promises = screenshots.map((screenshot) => {
          return new Promise<number>((resolve) => {
            const img = new Image();
            img.onload = () => {
              const aspectRatio = img.height / img.width;
              const calculatedHeight = newWidth * aspectRatio;
              resolve(calculatedHeight);
            };
            img.onerror = () => resolve(0);
            img.src = screenshot.src;
          });
        });

        Promise.all(promises).then((heights) => {
          if (heights.length > 0) {
            const maxHeight = Math.max(...heights);
            setContainerHeight(maxHeight);
          }
        });
      }
    };

    window.addEventListener('resize', handleResize);

    return () => {
      clearTimeout(timeoutId);
      window.removeEventListener('resize', handleResize);
    };
  }, [screenshots]);

  // Auto-advance carousel every 5 seconds - always at consistent rate
  useEffect(() => {
    if (screenshots.length === 0 || isPaused) {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    // Calculate time until next auto-advance (maintain consistent 5-second intervals)
    const now = Date.now();
    const timeSinceLastAutoAdvance = now - lastAutoAdvanceRef.current;
    const timeUntilNext = Math.max(0, 5000 - (timeSinceLastAutoAdvance % 5000));

    // Set initial timeout to align with 5-second intervals from last auto-advance
    const timeoutId = setTimeout(() => {
      setCurrentIndex((prev) => {
        lastAutoAdvanceRef.current = Date.now();
        return (prev + 1) % screenshots.length;
      });

      // Then set up regular interval that always runs every 5 seconds
      intervalRef.current = setInterval(() => {
        setCurrentIndex((prev) => {
          lastAutoAdvanceRef.current = Date.now();
          return (prev + 1) % screenshots.length;
        });
      }, 5000);
    }, timeUntilNext);

    return () => {
      clearTimeout(timeoutId);
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [screenshots.length, isPaused]);

  const goToSlide = (index: number) => {
    setCurrentIndex(index);
    // Don't reset the interval or update lastAutoAdvanceRef
    // The interval will continue at its natural pace based on when it last auto-advanced
  };

  const goToPrevious = () => {
    goToSlide((currentIndex - 1 + screenshots.length) % screenshots.length);
  };

  const goToNext = () => {
    goToSlide((currentIndex + 1) % screenshots.length);
  };

  // Swipe gesture handlers (only for mobile/tablet, disabled on lg+)
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  const touchEndRef = useRef<{ x: number; y: number } | null>(null);

  const minSwipeDistance = 50;

  const onTouchStart = (e: React.TouchEvent) => {
    // Only enable swipe on screens below lg (1024px)
    if (window.innerWidth >= 1024) return;
    
    touchEndRef.current = null;
    touchStartRef.current = {
      x: e.targetTouches[0].clientX,
      y: e.targetTouches[0].clientY,
    };
  };

  const onTouchMove = (e: React.TouchEvent) => {
    if (window.innerWidth >= 1024) return;
    touchEndRef.current = {
      x: e.targetTouches[0].clientX,
      y: e.targetTouches[0].clientY,
    };
  };

  const onTouchEnd = () => {
    if (window.innerWidth >= 1024) return;
    if (!touchStartRef.current || !touchEndRef.current) return;

    const distanceX = touchStartRef.current.x - touchEndRef.current.x;
    const distanceY = touchStartRef.current.y - touchEndRef.current.y;
    const isLeftSwipe = distanceX > minSwipeDistance;
    const isRightSwipe = distanceX < -minSwipeDistance;
    const isVerticalSwipe = Math.abs(distanceY) > Math.abs(distanceX);

    // Only handle horizontal swipes
    if (!isVerticalSwipe) {
      if (isLeftSwipe) {
        goToNext();
      } else if (isRightSwipe) {
        goToPrevious();
      }
    }
  };

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      {/* Screenshot Carousel */}
      {screenshots.length > 0 && (
        <div className="bg-gray-50 dark:bg-gray-900 overflow-hidden">
          {/* Main Image Display */}
          <div 
            ref={imageContainerRef}
            className="relative group bg-gray-50 dark:bg-gray-900 flex items-center justify-center px-4 py-4"
            style={{ 
              height: containerHeight ? `${containerHeight}px` : 'auto',
              minHeight: containerHeight ? undefined : '16rem'
            }}
          >
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
              className="relative w-full cursor-pointer lg:cursor-zoom-in"
              onClick={() => {
                // Only open modal on lg screens and larger
                if (window.innerWidth >= 1024) {
                  setModalImageIndex(currentIndex); // Store which image was clicked
                  setModalOpen(true);
                }
              }}
              onTouchStart={onTouchStart}
              onTouchMove={onTouchMove}
              onTouchEnd={onTouchEnd}
            >
              {screenshots.map((screenshot, index) => (
                <img
                  key={index}
                  src={screenshot.src}
                  alt={screenshot.alt}
                  className={`absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-full h-auto transition-opacity duration-500 ${
                    index === currentIndex ? 'opacity-100' : 'opacity-0'
                  }`}
                  style={{ 
                    maxWidth: 'calc(100% - 2rem)',
                  }}
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

          {/* Image Description Label */}
          <div className="px-4 py-2 bg-gray-50 dark:bg-gray-900">
            <p className="text-center text-sm font-medium text-gray-700 dark:text-gray-300">
              {screenshots[currentIndex]?.alt || ''}
            </p>
          </div>

          {/* Thumbnails */}
          <div className="pt-2 pb-4 px-4 bg-gray-50 dark:bg-gray-900">
            <div className="grid grid-cols-5 sm:grid-cols-6 md:grid-cols-7 lg:grid-cols-8 gap-2 justify-items-center">
              {screenshots.map((screenshot, index) => (
                <button
                  key={index}
                  onClick={() => goToSlide(index)}
                  onMouseEnter={() => setIsPaused(true)}
                  onMouseLeave={() => setIsPaused(false)}
                  className={`w-12 h-12 sm:w-16 sm:h-16 md:w-20 md:h-20 rounded-lg overflow-hidden border-2 transition-all duration-200 ${
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
          <span>{screenshots[modalImageIndex]?.alt || 'Screenshot'}</span>
        </Modal.Header>
        <Modal.Body>
          <div className="p-4">
            <img
              src={screenshots[modalImageIndex]?.original || screenshots[modalImageIndex]?.src}
              alt={screenshots[modalImageIndex]?.alt}
              className="w-full h-auto max-h-[75vh] object-contain mx-auto"
              onError={(e) => {
                // Fallback to WebP if original fails
                const img = e.target as HTMLImageElement;
                if (img.src !== screenshots[modalImageIndex]?.src) {
                  img.src = screenshots[modalImageIndex]?.src;
                } else {
                  img.style.display = 'none';
                }
              }}
            />
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

