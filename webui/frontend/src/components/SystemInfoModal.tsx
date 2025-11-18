/**
 * System Info Modal - Displays fastfetch output as HTML
 */
import { useState, useEffect } from 'react';
import { Modal } from 'flowbite-react';
import { apiClient } from '../api/client';

interface SystemInfoModalProps {
  show: boolean;
  onClose: () => void;
}

export function SystemInfoModal({ show, onClose }: SystemInfoModalProps) {
  const [htmlContent, setHtmlContent] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (show) {
      fetchFastfetch();
    } else {
      // Reset state when modal closes
      setHtmlContent('');
      setError(null);
    }
  }, [show]);

  const fetchFastfetch = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getFastfetch();
      setHtmlContent(data.html);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch system info');
      setHtmlContent('');
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
          {!loading && !error && htmlContent && (
            <div className="overflow-auto max-h-[70vh] w-full">
              <div 
                className="font-mono text-xs sm:text-sm bg-black text-white p-4 rounded-lg overflow-x-auto"
                style={{
                  fontFamily: "'Courier New', 'Monaco', 'Menlo', 'Consolas', monospace",
                  lineHeight: '1.4',
                  whiteSpace: 'pre-wrap',
                  wordWrap: 'break-word'
                }}
                dangerouslySetInnerHTML={{ __html: htmlContent }}
              />
            </div>
          )}
        </div>
      </Modal.Body>
    </Modal>
  );
}

