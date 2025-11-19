import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as r}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const n=`# Global DNS Configuration

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
`;function l(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(r,{content:n})})})}export{l as GlobalDnsConfig};
