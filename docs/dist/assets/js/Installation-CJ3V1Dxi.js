import{j as t}from"./ui-vendor-CtbJYEGA.js";import{M as e}from"./MarkdownContent-CHjPgFnl.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const s=`# Installation

This guide covers installing the NixOS Router on your hardware.

## Using the Install Script (Recommended)

Run from a vanilla NixOS installer shell:

**Important:** Please take time to inspect this installer script. It is **never** recommended to blindly run scripts from the internet.

\`\`\`bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
\`\`\`

### What does it do?

- Downloads, makes executable and runs [\`/scripts/install-router.sh\`](https://github.com/BeardedTek/nixos-router/blob/main/scripts/install-router.sh)
  - Clones this repository
  - Asks for user input with sane defaults to generate your \`router-config.nix\`
  - Builds the system

## Using the Custom ISO

**Note:** This script fetches everything via Nix; expect a large download on the first run.

1. Build the ISO:

   \`\`\`bash
   cd iso
   ./build-iso.sh
   \`\`\`

2. Write \`result/iso/*.iso\` to a USB drive.

3. (Optional) Place your \`router-config.nix\` inside the USB \`config/\` folder for unattended installs.

4. Boot the router from USB and follow the menu. Pick install or upgrade.

5. After completion, reboot and remove the USB stick.
`;function a(){return t.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:t.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:t.jsx(e,{content:s})})})}export{a as Installation};
