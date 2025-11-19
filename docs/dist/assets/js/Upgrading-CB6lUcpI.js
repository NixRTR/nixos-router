import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const s=`# Upgrading

## With the Script

1. Boot any Linux shell with internet access on the router (local console or SSH).

2. Re-run the script:

   \`\`\`bash
   curl -fsSL https://beard.click/nixos-router > install.sh
   chmod +x install.sh
   sudo ./install.sh
   \`\`\`

   Choose the upgrade option when prompted. The script pulls the latest commits and rebuilds the system.

## With the ISO

1. Build or download the latest ISO (same steps as installation).

2. Boot from the USB.

3. Select the upgrade entry in the menu; it reuses your existing \`router-config.nix\`.

4. Reboot when finished.

## Verify Upgrade

After upgrading, verify the system is working correctly:

\`\`\`bash
# Check NixOS version
sudo nixos-version

# Verify system configuration is valid
sudo nixos-rebuild dry-run --flake /etc/nixos#router

# Check for failed systemd services
sudo systemctl --failed

# Check WebUI is running
sudo systemctl status router-webui-backend.service
\`\`\`
`;function a(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:s})})})}export{a as Upgrading};
