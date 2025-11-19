import { TooltipProps } from 'recharts';

/**
 * Custom tooltip for Recharts that formats values with 2 decimals and appropriate units
 * Based on the data key name, it determines the unit:
 * - cpu, memory: %
 * - download, upload, rx_mbps, tx_mbps, read_mbps, write_mbps: Mbit/s or MB/s
 * - load: (no unit)
 * - temperature: °C
 */
export function CustomTooltip({ active, payload, label }: TooltipProps<number, string>) {
  if (!active || !payload || payload.length === 0) {
    return null;
  }

  const formatValue = (value: number | undefined, dataKey: string | number | undefined): string => {
    if (value === undefined || value === null) return 'N/A';
    
    const formatted = value.toFixed(2);
    const key = String(dataKey || '').toLowerCase();
    
    // Determine unit based on data key
    if (key.includes('cpu') || key.includes('memory')) {
      return `${formatted}%`;
    } else if (key.includes('download') || key.includes('upload') || 
               key.includes('rx_mbps') || key.includes('tx_mbps')) {
      return `${formatted} Mbit/s`;
    } else if (key.includes('read_mbps') || key.includes('write_mbps')) {
      return `${formatted} MB/s`;
    } else if (key.includes('temperature')) {
      return `${formatted} °C`;
    } else if (key.includes('load')) {
      return formatted; // Load average has no unit
    }
    
    // Default: just return formatted number
    return formatted;
  };

  return (
    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg p-3">
      <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mb-2">{label}</p>
      {payload.map((entry, index) => (
        <p key={index} className="text-sm" style={{ color: entry.color }}>
          {`${entry.name}: ${formatValue(entry.value as number, entry.dataKey as string)}`}
        </p>
      ))}
    </div>
  );
}

