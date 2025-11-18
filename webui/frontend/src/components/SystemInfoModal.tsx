/**
 * System Info Modal - Displays fastfetch output as WebP image
 */
import { useState, useEffect } from 'react';
import { Modal } from 'flowbite-react';
import { apiClient } from '../api/client';

interface SystemInfoModalProps {
  show: boolean;
  onClose: () => void;
}

export function SystemInfoModal({ show, onClose }: SystemInfoModalProps) {
  const [imageData, setImageData] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (show) {
      fetchFastfetch();
    } else {
      // Reset state when modal closes
      setImageData('');
      setError(null);
    }
  }, [show]);

  const fetchFastfetch = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getFastfetch();
      setImageData(data.image);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch system info');
      setImageData('');
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
          {!loading && !error && imageData && (
            <div className="overflow-auto max-h-[70vh] w-full flex justify-center">
              <img 
                src={`data:image/webp;base64,${imageData}`}
                alt="System Information"
                className="max-w-full h-auto rounded-lg"
              />
            </div>
          )}
        </div>
      </Modal.Body>
    </Modal>
  );
}

