import { MarkdownContent } from '../../components/MarkdownContent';

const globalDnsContent = `# Global DNS Configuration

Configure global DNS settings that apply to all networks.

## DNS Blocklists

Enable ad-blocking and malware protection:

\`\`\`nix
dns = {
  blockAds = true;
  blockMalware = true;
};
\`\`\`

## Upstream DNS Servers

Configure upstream DNS servers for recursive resolution:

\`\`\`nix
dns = {
  upstreamServers = [
    "1.1.1.1"
    "9.9.9.9"
  ];
};
\`\`\`

## DNS-over-TLS

Enable DNS-over-TLS for encrypted DNS queries:

\`\`\`nix
dns = {
  dnsOverTls = true;
};
\`\`\`

## DNSSEC

Enable DNSSEC validation:

\`\`\`nix
dns = {
  dnssec = true;
};
\`\`\`
`;

export function GlobalDnsConfig() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={globalDnsContent} />
      </div>
    </div>
  );
}
