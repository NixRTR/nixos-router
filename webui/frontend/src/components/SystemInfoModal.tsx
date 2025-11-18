/**
 * System Info Modal - Displays fastfetch output
 */
import { useState, useEffect } from 'react';
import { Modal } from 'flowbite-react';
import { apiClient } from '../api/client';

interface SystemInfoModalProps {
  show: boolean;
  onClose: () => void;
}

export function SystemInfoModal({ show, onClose }: SystemInfoModalProps) {
  const [output, setOutput] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (show) {
      fetchFastfetch();
    } else {
      // Reset state when modal closes
      setOutput('');
      setError(null);
    }
  }, [show]);

  const fetchFastfetch = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getFastfetch();
      setOutput(data.output);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch system info');
      setOutput('');
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
          {!loading && !error && output && (
            <div className="overflow-auto max-h-[70vh] w-full">
              <pre className="text-[9px] sm:text-[10px] md:text-xs font-mono whitespace-pre-wrap break-words bg-gray-900 dark:bg-gray-800 text-green-400 p-3 sm:p-4 rounded-lg overflow-x-auto w-full">
                {output}
              </pre>
            </div>
          )}
        </div>
      </Modal.Body>
    </Modal>
  );
}

