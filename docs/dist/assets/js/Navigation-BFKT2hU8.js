import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const s=`# Navigation

![Sidebar](../screenshots/003-sidebar.webp)

![Dark Mode](../screenshots/011-dark-mode.webp)

## Overview

The WebUI navigation consists of two main components: the **Navbar** (top bar) and the **Sidebar** (left navigation menu). Understanding these elements is essential for navigating the interface effectively.

## Navbar

The navbar is located at the top of every page and provides:

### Router Information
- **Router Name**: Displays "NixOS Router" with the NixOS logo
- **Hostname**: Shows the configured hostname of your router
- **Connection Status**: Visual indicator of WebSocket connection status
  - Green: Connected
  - Yellow: Connecting
  - Red: Connection error

### Theme Toggle
- **Sun/Moon Icon**: Toggle between light and dark mode
- **Persistent**: Your theme preference is saved and persists across sessions
- **System Preference**: If no preference is saved, it follows your system's dark mode setting

### Menu Button
- **Hamburger Icon**: Toggle sidebar visibility on smaller screens (below 1650px)
- **Auto-Hide**: Sidebar automatically hides on smaller screens to maximize content space

## Sidebar

The sidebar provides navigation to all major sections of the WebUI.

### Navigation Items

**Main Sections**:
- **Dashboard**: Overview of system status and resources
- **Network**: Network bandwidth monitoring and charts
- **Devices**: View and manage connected devices
- **Device Usage**: Per-device bandwidth statistics
- **System**: System resource monitoring with historical charts
- **Speedtest**: Internet speed testing and results

**System Section**:
- **System Info**: Detailed system information and configuration

**External Links**:
- **Documentation**: Opens the documentation site in a new tab
- **GitHub**: Link to the project repository with star/fork counts
- **Issues**: Link to GitHub issues page

### Sidebar Behavior

**Responsive Design**:
- **Large Screens (1650px+)**: Sidebar is always visible
- **Smaller Screens**: Sidebar is hidden by default, accessible via hamburger menu
- **Overlay**: On smaller screens, clicking outside the sidebar closes it

**Active State**:
- The current page is highlighted in the sidebar
- Navigation is instant (client-side routing)

## Dark Mode

### Purpose

Dark mode provides a comfortable viewing experience in low-light conditions and reduces eye strain.

### How to Use

1. **Toggle Button**: Click the sun/moon icon in the navbar
2. **Automatic**: Theme preference is saved automatically
3. **System Sync**: If no preference is saved, follows your system's dark mode setting

### Features

- **Persistent**: Your choice is remembered across sessions
- **Instant**: Theme changes apply immediately without page reload
- **Consistent**: All pages and components respect the theme setting
- **Accessible**: High contrast maintained in both themes

## Navigation Tips

1. **Keyboard Shortcuts**: Use browser back/forward buttons to navigate
2. **Direct Links**: Bookmark specific pages for quick access
3. **Sidebar Search**: Use browser find (Ctrl+F / Cmd+F) to search within the sidebar
4. **Quick Access**: Favorite devices appear in the Devices page for quick navigation
`;function r(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:s})})})}export{r as Navigation};
