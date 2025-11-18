/**
 * System Info Modal - Displays system information with NixOS logo
 */
import { useState, useEffect } from 'react';
import { Modal } from 'flowbite-react';
import { apiClient } from '../api/client';

interface SystemInfoModalProps {
  show: boolean;
  onClose: () => void;
}

export function SystemInfoModal({ show, onClose }: SystemInfoModalProps) {
  const [textData, setTextData] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (show) {
      fetchFastfetch();
    } else {
      // Reset state when modal closes
      setTextData('');
      setError(null);
    }
  }, [show]);

  const fetchFastfetch = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getFastfetch();
      setTextData(data.text);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch system info');
      setTextData('');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal show={show} onClose={onClose} size="xl">
      <Modal.Header>System Info</Modal.Header>
      <Modal.Body>
        <div className="space-y-4">
          {loading && (
            <div className="text-center py-8 text-gray-500">
              Loading system information...
            </div>
          )}
          {error && (
            <div className="text-center py-8 text-red-500">
              Error: {error}
            </div>
          )}
          {!loading && !error && textData && (
            <div className="flex gap-6 items-start">
              {/* NixOS Logo */}
              <div className="flex-shrink-0 flex items-center justify-center">
                <svg
                  width="100"
                  height="100"
                  viewBox="0 0 100 100"
                  fill="none"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  {/* NixOS Snowflake Logo - Official style */}
                  <g fill="#5277C3" className="dark:fill-blue-400">
                    {/* Main snowflake pattern */}
                    <path d="M50 10L55 20L50 30L45 20L50 10Z" />
                    <path d="M50 90L55 80L50 70L45 80L50 90Z" />
                    <path d="M10 50L20 45L30 50L20 55L10 50Z" />
                    <path d="M90 50L80 45L70 50L80 55L90 50Z" />
                    <path d="M25 25L30 15L40 25L30 35L25 25Z" />
                    <path d="M75 75L80 65L90 75L80 85L75 75Z" />
                    <path d="M25 75L30 65L40 75L30 85L25 75Z" />
                    <path d="M75 25L80 15L90 25L80 35L75 25Z" />
                    {/* Center circle */}
                    <circle cx="50" cy="50" r="6" />
                  </g>
                </svg>
              </div>
              
              {/* Fastfetch Text Output */}
              <div className="flex-1">
                <pre className="font-mono text-sm whitespace-pre-wrap text-gray-800 dark:text-gray-200 bg-gray-50 dark:bg-gray-900 p-4 rounded-lg overflow-auto max-h-[60vh]">
                  {textData}
                </pre>
              </div>
            </div>
          )}
        </div>
      </Modal.Body>
    </Modal>
  );
}
