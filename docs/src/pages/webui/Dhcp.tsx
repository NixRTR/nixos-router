import { MarkdownContent } from '../../components/MarkdownContent';
import dhcpContent from '../../content/dhcp.md?raw';

export function Dhcp() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={dhcpContent} />
      </div>
    </div>
  );
}

