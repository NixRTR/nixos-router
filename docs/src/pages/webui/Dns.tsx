import { MarkdownContent } from '../../components/MarkdownContent';
import dnsContent from '../../content/dns.md?raw';

export function Dns() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={dnsContent} />
      </div>
    </div>
  );
}

