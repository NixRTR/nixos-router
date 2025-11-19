import{j as e,N as I,T as M,M as N}from"./ui-vendor-CtbJYEGA.js";import{d as U,R as b,L as j,u as H,a as g,B as G,e as V,f as u,h as F}from"./react-vendor-ZjkKMkft.js";import{M as _,r as $}from"./markdown-vendor-DRFysTMB.js";(function(){const r=document.createElement("link").relList;if(r&&r.supports&&r.supports("modulepreload"))return;for(const o of document.querySelectorAll('link[rel="modulepreload"]'))a(o);new MutationObserver(o=>{for(const s of o)if(s.type==="childList")for(const m of s.addedNodes)m.tagName==="LINK"&&m.rel==="modulepreload"&&a(m)}).observe(document,{childList:!0,subtree:!0});function n(o){const s={};return o.integrity&&(s.integrity=o.integrity),o.referrerPolicy&&(s.referrerPolicy=o.referrerPolicy),o.crossOrigin==="use-credentials"?s.credentials="include":o.crossOrigin==="anonymous"?s.credentials="omit":s.credentials="same-origin",s}function a(o){if(o.ep)return;o.ep=!0;const s=n(o);fetch(o.href,s)}})();var v={},O;function q(){if(O)return v;O=1;var t=U();return v.createRoot=t.createRoot,v.hydrateRoot=t.hydrateRoot,v}var K=q(),B={color:void 0,size:void 0,className:void 0,style:void 0,attr:void 0},A=b.createContext&&b.createContext(B),Q=["attr","size","title"];function J(t,r){if(t==null)return{};var n=Y(t,r),a,o;if(Object.getOwnPropertySymbols){var s=Object.getOwnPropertySymbols(t);for(o=0;o<s.length;o++)a=s[o],!(r.indexOf(a)>=0)&&Object.prototype.propertyIsEnumerable.call(t,a)&&(n[a]=t[a])}return n}function Y(t,r){if(t==null)return{};var n={};for(var a in t)if(Object.prototype.hasOwnProperty.call(t,a)){if(r.indexOf(a)>=0)continue;n[a]=t[a]}return n}function w(){return w=Object.assign?Object.assign.bind():function(t){for(var r=1;r<arguments.length;r++){var n=arguments[r];for(var a in n)Object.prototype.hasOwnProperty.call(n,a)&&(t[a]=n[a])}return t},w.apply(this,arguments)}function L(t,r){var n=Object.keys(t);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(t);r&&(a=a.filter(function(o){return Object.getOwnPropertyDescriptor(t,o).enumerable})),n.push.apply(n,a)}return n}function k(t){for(var r=1;r<arguments.length;r++){var n=arguments[r]!=null?arguments[r]:{};r%2?L(Object(n),!0).forEach(function(a){Z(t,a,n[a])}):Object.getOwnPropertyDescriptors?Object.defineProperties(t,Object.getOwnPropertyDescriptors(n)):L(Object(n)).forEach(function(a){Object.defineProperty(t,a,Object.getOwnPropertyDescriptor(n,a))})}return t}function Z(t,r,n){return r=X(r),r in t?Object.defineProperty(t,r,{value:n,enumerable:!0,configurable:!0,writable:!0}):t[r]=n,t}function X(t){var r=ee(t,"string");return typeof r=="symbol"?r:r+""}function ee(t,r){if(typeof t!="object"||!t)return t;var n=t[Symbol.toPrimitive];if(n!==void 0){var a=n.call(t,r);if(typeof a!="object")return a;throw new TypeError("@@toPrimitive must return a primitive value.")}return(r==="string"?String:Number)(t)}function T(t){return t&&t.map((r,n)=>b.createElement(r.tag,k({key:n},r.attr),T(r.child)))}function x(t){return r=>b.createElement(te,w({attr:k({},t.attr)},r),T(t.child))}function te(t){var r=n=>{var{attr:a,size:o,title:s}=t,m=J(t,Q),f=o||n.size||"1em",i;return n.className&&(i=n.className),t.className&&(i=(i?i+" ":"")+t.className),b.createElement("svg",w({stroke:"currentColor",fill:"currentColor",strokeWidth:"0"},n.attr,a,m,{className:i,style:k(k({color:t.color||n.color},n.style),t.style),height:f,width:f,xmlns:"http://www.w3.org/2000/svg"}),s&&b.createElement("title",null,s),t.children)};return A!==void 0?b.createElement(A.Consumer,null,n=>r(n)):r(B)}function E(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{fillRule:"evenodd",d:"M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z",clipRule:"evenodd"},child:[]}]})(t)}function z(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{fillRule:"evenodd",d:"M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z",clipRule:"evenodd"},child:[]}]})(t)}function re(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{fillRule:"evenodd",d:"M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z",clipRule:"evenodd"},child:[]}]})(t)}function ne(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{fillRule:"evenodd",d:"M3 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 10a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 15a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z",clipRule:"evenodd"},child:[]}]})(t)}function ae(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{d:"M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z"},child:[]}]})(t)}function oe(t){return x({attr:{viewBox:"0 0 20 20",fill:"currentColor","aria-hidden":"true"},child:[{tag:"path",attr:{fillRule:"evenodd",d:"M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z",clipRule:"evenodd"},child:[]}]})(t)}function se({onMenuClick:t}){const r=()=>{const n=document.documentElement;if(n.classList.contains("dark")){n.classList.remove("dark");try{localStorage.setItem("theme","light")}catch{}}else{n.classList.add("dark");try{localStorage.setItem("theme","dark")}catch{}}};return e.jsxs(I,{fluid:!0,className:"border-b",children:[e.jsxs("div",{className:"flex items-center gap-3",children:[e.jsx("button",{onClick:t,className:"p-2 text-gray-500 rounded-lg lg:hidden hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600","aria-label":"Toggle menu",children:e.jsx(ne,{className:"w-6 h-6"})}),e.jsx(I.Brand,{children:e.jsx(j,{to:"/",className:"self-center whitespace-nowrap text-xl font-semibold text-gray-900 dark:text-white",children:"NixOS Router Documentation"})})]}),e.jsx("div",{className:"flex items-center gap-2 md:gap-4",children:e.jsx(M,{content:"Toggle theme",placement:"bottom",children:e.jsxs("button",{type:"button",onClick:r,className:"p-2 rounded-lg text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:focus:ring-gray-600","aria-label":"Toggle theme",title:"Toggle theme",children:[e.jsx("span",{className:"hidden dark:inline-block",children:e.jsx(oe,{className:"w-5 h-5"})}),e.jsx("span",{className:"inline-block dark:hidden",children:e.jsx(ae,{className:"w-5 h-5"})})]})})})]})}function ie(t){return x({attr:{viewBox:"0 0 496 512"},child:[{tag:"path",attr:{d:"M165.9 397.4c0 2-2.3 3.6-5.2 3.6-3.3.3-5.6-1.3-5.6-3.6 0-2 2.3-3.6 5.2-3.6 3-.3 5.6 1.3 5.6 3.6zm-31.1-4.5c-.7 2 1.3 4.3 4.3 4.9 2.6 1 5.6 0 6.2-2s-1.3-4.3-4.3-5.2c-2.6-.7-5.5.3-6.2 2.3zm44.2-1.7c-2.9.7-4.9 2.6-4.6 4.9.3 2 2.9 3.3 5.9 2.6 2.9-.7 4.9-2.6 4.6-4.6-.3-1.9-3-3.2-5.9-2.9zM244.8 8C106.1 8 0 113.3 0 252c0 110.9 69.8 205.8 169.5 239.2 12.8 2.3 17.3-5.6 17.3-12.1 0-6.2-.3-40.4-.3-61.4 0 0-70 15-84.7-29.8 0 0-11.4-29.1-27.8-36.6 0 0-22.9-15.7 1.6-15.4 0 0 24.9 2 38.6 25.8 21.9 38.6 58.6 27.5 72.9 20.9 2.3-16 8.8-27.1 16-33.7-55.9-6.2-112.3-14.3-112.3-110.5 0-27.5 7.6-41.3 23.6-58.9-2.6-6.5-11.1-33.3 2.6-67.9 20.9-6.5 69 27 69 27 20-5.6 41.5-8.5 62.8-8.5s42.8 2.9 62.8 8.5c0 0 48.1-33.6 69-27 13.7 34.7 5.2 61.4 2.6 67.9 16 17.7 25.8 31.5 25.8 58.9 0 96.5-58.9 104.2-114.8 110.5 9.2 7.9 17 22.9 17 46.4 0 33.7-.3 75.4-.3 83.6 0 6.5 4.6 14.4 17.3 12.1C428.2 457.8 496 362.9 496 252 496 113.3 383.5 8 244.8 8zM97.2 352.9c-1.3 1-1 3.3.7 5.2 1.6 1.6 3.9 2.3 5.2 1 1.3-1 1-3.3-.7-5.2-1.6-1.6-3.9-2.3-5.2-1zm-10.8-8.1c-.7 1.3.3 2.9 2.3 3.9 1.6 1 3.6.7 4.3-.7.7-1.3-.3-2.9-2.3-3.9-2-.6-3.6-.3-4.3.7zm32.4 35.6c-1.6 1.3-1 4.3 1.3 6.2 2.3 2.3 5.2 2.6 6.5 1 1.3-1.3.7-4.3-1.3-6.2-2.2-2.3-5.2-2.6-6.5-1zm-11.4-14.7c-1.6 1-1.6 3.6 0 5.9 1.6 2.3 4.3 3.3 5.6 2.3 1.6-1.3 1.6-3.9 0-6.2-1.4-2.3-4-3.3-5.6-2z"},child:[]}]})(t)}function le({isOpen:t,onClose:r}){const n=H(),[a,o]=g.useState(null);g.useEffect(()=>{(async()=>{try{const l=await fetch("https://api.github.com/repos/BeardedTek/nixos-router");if(l.ok){const p=await l.json();o({stars:p.stargazers_count||0,forks:p.forks_count||0})}else o({stars:0,forks:0})}catch(l){console.error("Failed to fetch GitHub stats:",l),o({stars:0,forks:0})}})()},[]);const s=[{path:"/",label:"Home"},{path:"/installation",label:"Installation"},{path:"/upgrading",label:"Upgrading"},{path:"/verification",label:"Verification"},{path:"/configuration",label:"Configuration",children:[{path:"/configuration/system",label:"System"},{path:"/configuration/wan",label:"WAN"},{path:"/configuration/lan-bridges",label:"LAN Bridges"},{path:"/configuration/homelab",label:"Homelab"},{path:"/configuration/lan",label:"LAN"},{path:"/configuration/port-forwarding",label:"Port Forwarding"},{path:"/configuration/dyndns",label:"Dynamic DNS"},{path:"/configuration/global-dns",label:"Global DNS"},{path:"/configuration/webui",label:"WebUI"}]}],m=i=>n.pathname===i,f=(i,l)=>m(i)?!0:l?l.some(p=>n.pathname.startsWith(p.path)):!1;return e.jsxs(e.Fragment,{children:[t&&e.jsx("div",{className:"fixed inset-0 bg-gray-900 bg-opacity-50 z-20 lg:hidden",onClick:r}),e.jsx("aside",{className:`fixed top-0 left-0 z-30 w-64 h-screen pt-16 transition-transform bg-white border-r border-gray-200 dark:bg-gray-800 dark:border-gray-700 lg:translate-x-0 ${t?"translate-x-0":"-translate-x-full"} lg:static lg:z-auto`,children:e.jsxs("div",{className:"h-full px-3 py-4 overflow-y-auto",children:[e.jsx("ul",{className:"space-y-2 font-medium",children:s.map(i=>e.jsxs("li",{children:[e.jsx(j,{to:i.path,onClick:()=>{window.innerWidth<1024&&r()},className:`flex items-center p-2 rounded-lg ${f(i.path,i.children)?"text-blue-600 bg-blue-50 dark:text-blue-500 dark:bg-gray-700":"text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700"}`,children:e.jsx("span",{className:"ml-3",children:i.label})}),i.children&&f(i.path,i.children)&&e.jsx("ul",{className:"ml-6 mt-2 space-y-1",children:i.children.map(l=>e.jsx("li",{children:e.jsx(j,{to:l.path,onClick:()=>{window.innerWidth<1024&&r()},className:`flex items-center p-2 rounded-lg text-sm ${m(l.path)?"text-blue-600 bg-blue-50 dark:text-blue-500 dark:bg-gray-700":"text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700"}`,children:l.label})},l.path))})]},i.path))}),e.jsx("div",{className:"pt-4 mt-4 border-t border-gray-200 dark:border-gray-700",children:e.jsxs("ul",{className:"space-y-2 font-medium",children:[e.jsx("li",{children:e.jsxs("a",{href:"https://github.com/BeardedTek/nixos-router",target:"_blank",rel:"noopener noreferrer",onClick:()=>{window.innerWidth<1024&&r()},className:"flex items-center justify-between p-2 rounded-lg text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700",children:[e.jsxs("div",{className:"flex items-center",children:[e.jsx(ie,{className:"w-5 h-5 mr-3"}),e.jsx("span",{children:"GitHub"})]}),a!==null&&e.jsxs("span",{className:"ml-2 text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap",children:["⭐ ",a.stars," 🍴 ",a.forks]})]})}),e.jsx("li",{children:e.jsxs("a",{href:"https://github.com/BeardedTek/nixos-router/issues",target:"_blank",rel:"noopener noreferrer",onClick:()=>{window.innerWidth<1024&&r()},className:"flex items-center p-2 rounded-lg text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700",children:[e.jsx(re,{className:"w-5 h-5 mr-3"}),e.jsx("span",{children:"Issues"})]})})]})})]})})]})}function ce({children:t}){const[r,n]=g.useState(!1);return e.jsxs("div",{className:"flex h-screen bg-gray-50 dark:bg-gray-900",children:[e.jsx(le,{isOpen:r,onClose:()=>n(!1)}),e.jsxs("div",{className:"flex-1 flex flex-col overflow-hidden",children:[e.jsx(se,{onMenuClick:()=>n(!r)}),e.jsx("main",{className:"flex-1 overflow-y-auto bg-gray-50 dark:bg-gray-900",children:t})]})]})}function h({content:t}){return e.jsx("article",{className:"format format-blue dark:format-invert max-w-none",children:e.jsx(_,{remarkPlugins:[$],children:t})})}const de=`# NixOS Router Documentation

Welcome to the NixOS Router documentation. This guide will help you install, configure, and maintain your NixOS-based router.

## Quick Links

- [Installation Guide](/installation) - Get started with installing the router
- [Upgrading Guide](/upgrading) - Learn how to upgrade your router
- [Verification](/verification) - Verify your router is working correctly
- [Configuration](/configuration) - Configure all aspects of your router

## Features

- Multi-network support (isolated LAN segments)
- DHCP server (Kea)
- DNS server (Unbound with ad-blocking)
- Web dashboard for monitoring
- Dynamic DNS updates (Linode)
- Firewall and NAT
- Secrets management via sops-nix

## Getting Started

1. Follow the [Installation Guide](/installation) to set up your router
2. Verify your installation using the [Verification Guide](/verification)
3. Customize your configuration using the [Configuration Guide](/configuration)

## Need Help?

- Check the [GitHub Issues](https://github.com/BeardedTek/nixos-router/issues)
- Review the [GitHub Repository](https://github.com/BeardedTek/nixos-router)
`;function ue(){const[t,r]=g.useState([]),[n,a]=g.useState(0),[o,s]=g.useState(!1),[m,f]=g.useState(!1),i="/docs/",l=g.useRef(null);g.useEffect(()=>{(async()=>{try{const d=`${i}screenshots/manifest.json`,y=await fetch(d);if(y.ok){const W=(await y.json()).screenshots.map(({file:P,original:D,alt:R})=>({src:`${i}screenshots/${P}`,original:D?`${i}screenshots/${D}`:`${i}screenshots/${P}`,alt:R}));r(W)}else console.warn("Could not load screenshots manifest, using empty list"),r([])}catch(d){console.error("Error loading screenshots manifest:",d),r([])}})()},[i]),g.useEffect(()=>{if(t.length===0||o){l.current&&(clearInterval(l.current),l.current=null);return}return l.current=setInterval(()=>{a(c=>(c+1)%t.length)},5e3),()=>{l.current&&clearInterval(l.current)}},[t.length,o]);const p=c=>{a(c),l.current&&clearInterval(l.current),l.current=setInterval(()=>{a(d=>(d+1)%t.length)},5e3)},C=()=>{p((n-1+t.length)%t.length)},S=()=>{p((n+1)%t.length)};return e.jsxs("div",{className:"p-6 max-w-4xl mx-auto space-y-6",children:[t.length>0&&e.jsxs("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm overflow-hidden",children:[e.jsxs("div",{className:"relative h-64 sm:h-80 xl:h-96 group bg-gray-100 dark:bg-gray-700",children:[e.jsx("button",{onClick:C,onMouseEnter:()=>s(!0),onMouseLeave:()=>s(!1),className:"absolute left-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-2 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200","aria-label":"Previous image",children:e.jsx(E,{className:"w-6 h-6"})}),e.jsx("div",{className:"relative w-full h-full cursor-pointer lg:cursor-zoom-in",onClick:()=>{window.innerWidth>=1024&&f(!0)},children:t.map((c,d)=>e.jsx("img",{src:c.src,alt:c.alt,className:`absolute inset-0 w-full h-full object-contain transition-opacity duration-500 ${d===n?"opacity-100":"opacity-0"}`,onError:y=>{y.target.style.display="none"}},d))}),e.jsx("button",{onClick:S,onMouseEnter:()=>s(!0),onMouseLeave:()=>s(!1),className:"absolute right-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-2 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200","aria-label":"Next image",children:e.jsx(z,{className:"w-6 h-6"})})]}),e.jsx("div",{className:"p-4 bg-gray-50 dark:bg-gray-900 border-t border-gray-200 dark:border-gray-700",children:e.jsx("div",{className:"flex gap-2 overflow-x-auto scrollbar-hide justify-center",children:t.map((c,d)=>e.jsx("button",{onClick:()=>p(d),onMouseEnter:()=>s(!0),onMouseLeave:()=>s(!1),className:`flex-shrink-0 w-20 h-20 rounded-lg overflow-hidden border-2 transition-all duration-200 ${d===n?"border-blue-500 dark:border-blue-400 ring-2 ring-blue-500/50 dark:ring-blue-400/50 scale-105":"border-gray-300 dark:border-gray-600 hover:border-gray-400 dark:hover:border-gray-500 opacity-70 hover:opacity-100"}`,"aria-label":`Go to ${c.alt}`,children:e.jsx("img",{src:c.src,alt:c.alt,className:"w-full h-full object-cover",onError:y=>{y.target.style.display="none"}})},d))})})]}),e.jsxs(N,{show:m,onClose:()=>f(!1),size:"7xl",children:[e.jsx(N.Header,{children:e.jsx("div",{className:"flex items-center justify-between w-full",children:e.jsx("span",{children:t[n]?.alt||"Screenshot"})})}),e.jsx(N.Body,{children:e.jsxs("div",{className:"relative",children:[e.jsx("button",{onClick:c=>{c.stopPropagation(),C()},className:"absolute left-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-3 rounded-full","aria-label":"Previous image",children:e.jsx(E,{className:"w-8 h-8"})}),e.jsx("img",{src:t[n]?.original||t[n]?.src,alt:t[n]?.alt,className:"w-full h-auto max-h-[80vh] object-contain mx-auto",onError:c=>{const d=c.target;d.src!==t[n]?.src?d.src=t[n]?.src:d.style.display="none"}}),e.jsx("button",{onClick:c=>{c.stopPropagation(),S()},className:"absolute right-4 top-1/2 -translate-y-1/2 z-10 bg-black/50 hover:bg-black/70 text-white p-3 rounded-full","aria-label":"Next image",children:e.jsx(z,{className:"w-8 h-8"})})]})})]}),e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:de})})]})}const he=`# Installation

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
`;function ge(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:he})})})}const me=`# Upgrading

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
`;function fe(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:me})})})}const pe=`# Verify System Operation

## Basic System Verification

\`\`\`bash
# Check NixOS version
sudo nixos-version

# Verify system configuration is valid
sudo nixos-rebuild dry-run --flake /etc/nixos#router

# Check for failed systemd services
sudo systemctl --failed

# Check system health
sudo systemctl status
\`\`\`

## Router-Specific Services

\`\`\`bash
# WebUI Backend (main service)
sudo systemctl status router-webui-backend.service

# PostgreSQL (required for WebUI)
sudo systemctl status postgresql.service

# Kea DHCP servers (check both networks if configured)
sudo systemctl status kea-dhcp4-homelab.service
sudo systemctl status kea-dhcp4-lan.service

# Unbound DNS servers (check both networks if configured)
sudo systemctl status unbound-homelab.service
sudo systemctl status unbound-lan.service

# Dynamic DNS (if enabled)
sudo systemctl status linode-dyndns.service
sudo systemctl status linode-dyndns-on-wan-up.service

# Speedtest monitoring (if enabled)
sudo systemctl status speedtest.service
sudo systemctl status speedtest-on-wan-up.service
\`\`\`

## Verify Network Connectivity

\`\`\`bash
# Check WAN interface is up
ip addr show eno1  # or your WAN interface
ip link show eno1

# Check PPPoE connection (if using PPPoE)
ip addr show ppp0
sudo systemctl status pppoe-connection.service

# Check bridge interfaces
ip addr show br0
ip addr show br1  # if using multi-bridge mode

# Verify routing table
ip route show

# Check NAT is working
sudo nft list ruleset | grep -A 10 "nat"

# Test internet connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com
\`\`\`

## Verify DNS

\`\`\`bash
# Test DNS resolution
dig @192.168.2.1 router.jeandr.net  # HOMELAB DNS
dig @192.168.3.1 router.jeandr.net  # LAN DNS

# Check DNS is listening
sudo ss -tlnp | grep :53

# Test DNS from a client
# (from a device on the network)
nslookup router.jeandr.net 192.168.2.1
\`\`\`

## Verify DHCP

\`\`\`bash
# Check DHCP leases file exists and has entries
sudo cat /var/lib/kea/dhcp4.leases | tail -20

# Verify DHCP is listening
sudo ss -ulnp | grep :67

# Test DHCP from a client
# (release and renew on a client device)
\`\`\`

## Verify WebUI

\`\`\`bash
# Check WebUI is accessible
curl -I http://localhost:8080
# or from a client:
curl -I http://192.168.2.1:8080  # or your router IP

# Check WebUI logs for errors
sudo journalctl -u router-webui-backend.service -n 50 --no-pager

# Verify database connection
sudo -u router-webui psql -h localhost -U router_webui -d router_webui -c "SELECT COUNT(*) FROM system_metrics;"
\`\`\`

## Verify Firewall and Port Forwarding

\`\`\`bash
# Verify nftables rules are loaded
sudo nft list ruleset

# Check port forwarding rules
sudo nft list chain inet router port_forward

# Test port forwarding (from external network)
# telnet your-public-ip 443
\`\`\`
`;function be(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:pe})})})}const xe=`# Configuration

This section covers all configuration options for the NixOS Router.

## Configuration Sections

- [System Configuration](/configuration/system) - Basic system settings
- [WAN Configuration](/configuration/wan) - WAN interface and connection settings
- [LAN Bridges](/configuration/lan-bridges) - LAN bridge configuration
- [Homelab Network](/configuration/homelab) - Homelab network settings
- [LAN Network](/configuration/lan) - LAN network settings
- [Port Forwarding](/configuration/port-forwarding) - Port forwarding rules
- [Dynamic DNS](/configuration/dyndns) - Dynamic DNS configuration
- [Global DNS](/configuration/global-dns) - Global DNS settings
- [WebUI](/configuration/webui) - Web dashboard configuration
`;function ye(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:xe})})})}const ve=`# System Configuration

System configuration covers basic settings for your router.

## Hostname

Set the hostname of your router:

\`\`\`nix
hostname = "nixos-router";
\`\`\`

## Domain

Set the domain for DNS search:

\`\`\`nix
domain = "example.com";
\`\`\`

## Timezone

Configure the timezone:

\`\`\`nix
timezone = "America/Anchorage";
\`\`\`

## Username

Set the admin username:

\`\`\`nix
username = "routeradmin";
\`\`\`

## Nameservers

Configure nameservers for the router itself (used in /etc/resolv.conf):

\`\`\`nix
nameservers = [ "1.1.1.1" "9.9.9.9" "192.168.3.33" ];
\`\`\`

## SSH Keys

Add SSH authorized keys for the router admin user:

\`\`\`nix
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
];
\`\`\`
`;function we(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:ve})})})}const ke=`# WAN Configuration

Configure your WAN (Wide Area Network) interface and connection type.

## Connection Type

The router supports two WAN connection types:

### DHCP

For most home internet connections:

\`\`\`nix
wan = {
  type = "dhcp";
  interface = "eno1";
};
\`\`\`

### PPPoE

For DSL or fiber connections that require PPPoE authentication:

\`\`\`nix
wan = {
  type = "pppoe";
  interface = "eno1";
};
\`\`\`

When using PPPoE, you'll also need to configure credentials in your secrets file (see secrets management).

## Interface Selection

Choose the network interface connected to your internet connection. Common interface names:

- \`eno1\`, \`eno2\` - Onboard Ethernet
- \`enp4s0\`, \`enp5s0\` - PCIe Ethernet cards
- \`eth0\`, \`eth1\` - Legacy naming

Use \`ip link show\` to list available interfaces.
`;function Ne(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:ke})})})}const je=`# LAN Bridges Configuration

Configure LAN (Local Area Network) bridges for your internal networks.

## Bridge Configuration

Bridges allow you to combine multiple physical interfaces into a single logical network:

\`\`\`nix
lan = {
  bridges = [
    {
      name = "br0";
      interfaces = [ "enp4s0" "enp5s0" ];
      ipv4 = {
        address = "192.168.2.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
    {
      name = "br1";
      interfaces = [ "enp6s0" "enp7s0" ];
      ipv4 = {
        address = "192.168.3.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
  ];
};
\`\`\`

## Network Isolation

Enable isolation to block traffic between bridges:

\`\`\`nix
lan = {
  isolation = true;
};
\`\`\`

## Isolation Exceptions

Allow specific devices to access other networks:

\`\`\`nix
isolationExceptions = [
  {
    source = "192.168.3.10";
    sourceBridge = "br1";
    destBridge = "br0";
  }
];
\`\`\`
`;function Ce(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:je})})})}const Se=`# Homelab Network Configuration

Configure the homelab network (typically br0, 192.168.2.x).

## DHCP Configuration

Configure DHCP for the homelab network:

\`\`\`nix
homelab = {
  dhcp = {
    enable = true;
    rangeStart = "192.168.2.100";
    rangeEnd = "192.168.2.200";
    leaseTime = 86400;  # 24 hours
  };
};
\`\`\`

## DNS Configuration

Configure DNS for the homelab network:

\`\`\`nix
homelab = {
  dns = {
    enable = true;
    domain = "homelab.local";
    blockAds = true;
  };
};
\`\`\`

## IP Address

Set the router's IP address on this network:

\`\`\`nix
homelab = {
  ipAddress = "192.168.2.1";
};
\`\`\`
`;function Pe(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:Se})})})}const De=`# LAN Network Configuration

Configure the LAN network (typically br1, 192.168.3.x).

## DHCP Configuration

Configure DHCP for the LAN network:

\`\`\`nix
lan = {
  dhcp = {
    enable = true;
    rangeStart = "192.168.3.100";
    rangeEnd = "192.168.3.200";
    leaseTime = 86400;  # 24 hours
  };
};
\`\`\`

## DNS Configuration

Configure DNS for the LAN network:

\`\`\`nix
lan = {
  dns = {
    enable = true;
    domain = "lan.local";
    blockAds = true;
  };
};
\`\`\`

## IP Address

Set the router's IP address on this network:

\`\`\`nix
lan = {
  ipAddress = "192.168.3.1";
};
\`\`\`
`;function Ie(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:De})})})}const Oe=`# Port Forwarding Configuration

Configure port forwarding rules to expose internal services to the internet.

## Port Forward Rules

Add port forwarding rules:

\`\`\`nix
portForwards = [
  {
    name = "web-server";
    protocol = "tcp";
    externalPort = 443;
    internalIP = "192.168.2.10";
    internalPort = 443;
  }
  {
    name = "ssh-server";
    protocol = "tcp";
    externalPort = 2222;
    internalIP = "192.168.2.20";
    internalPort = 22;
  }
];
\`\`\`

## Rule Format

Each port forward rule requires:

- \`name\` - Descriptive name for the rule
- \`protocol\` - "tcp" or "udp"
- \`externalPort\` - Port on the WAN interface
- \`internalIP\` - IP address of the internal service
- \`internalPort\` - Port of the internal service

## Security Considerations

- Only forward ports that are necessary
- Use non-standard external ports when possible
- Ensure internal services are properly secured
- Consider using a VPN instead of port forwarding for remote access
`;function Ae(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:Oe})})})}const Le=`# Dynamic DNS Configuration

Configure dynamic DNS updates to keep your domain pointing to your router's public IP.

## Linode Dynamic DNS

The router supports Linode's Dynamic DNS service:

\`\`\`nix
dyndns = {
  enable = true;
  provider = "linode";
  domain = "example.com";
  subdomain = "router";
  updateInterval = 300;  # 5 minutes
};
\`\`\`

## Configuration Options

- \`enable\` - Enable/disable dynamic DNS updates
- \`provider\` - DNS provider (currently "linode")
- \`domain\` - Your domain name
- \`subdomain\` - Subdomain to update (optional)
- \`updateInterval\` - How often to check and update (in seconds)

## Secrets

Dynamic DNS credentials should be stored in your secrets file:

\`\`\`yaml
linode-api-key: "your-api-key-here"
\`\`\`

## Verification

Check if dynamic DNS is working:

\`\`\`bash
# Check service status
sudo systemctl status linode-dyndns.service

# Check logs
sudo journalctl -u linode-dyndns.service -n 50
\`\`\`
`;function Ee(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:Le})})})}const ze=`# Global DNS Configuration

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
`;function He(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:ze})})})}const Be=`# WebUI Configuration

Configure the web dashboard for monitoring your router.

## Basic Settings

\`\`\`nix
webui = {
  enable = true;
  port = 8080;
  collectionInterval = 2;  # seconds
  retentionDays = 30;
};
\`\`\`

## Configuration Options

- \`enable\` - Enable/disable the WebUI
- \`port\` - Port to serve the WebUI on (default: 8080)
- \`collectionInterval\` - How often to collect metrics (in seconds)
- \`retentionDays\` - How many days of historical data to keep

## Access

Access the WebUI at:

\`\`\`
http://router-ip:8080
\`\`\`

## Features

The WebUI provides:

- Real-time system metrics (CPU, memory, load)
- Network interface statistics
- Device usage and bandwidth tracking
- Service status monitoring
- Historical data visualization

## Authentication

The WebUI uses system user authentication (PAM). Log in with your router admin credentials.
`;function Te(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(h,{content:Be})})})}function We(){const t=H(),r=F();return g.useEffect(()=>{t.pathname!=="/"&&t.pathname.endsWith("/")&&r(t.pathname.slice(0,-1),{replace:!0})},[t.pathname,r]),null}function Re(){return e.jsxs(G,{basename:"/docs/",children:[e.jsx(We,{}),e.jsx(ce,{children:e.jsxs(V,{children:[e.jsx(u,{path:"/",element:e.jsx(ue,{})}),e.jsx(u,{path:"/installation",element:e.jsx(ge,{})}),e.jsx(u,{path:"/upgrading",element:e.jsx(fe,{})}),e.jsx(u,{path:"/verification",element:e.jsx(be,{})}),e.jsx(u,{path:"/configuration",element:e.jsx(ye,{})}),e.jsx(u,{path:"/configuration/system",element:e.jsx(we,{})}),e.jsx(u,{path:"/configuration/wan",element:e.jsx(Ne,{})}),e.jsx(u,{path:"/configuration/lan-bridges",element:e.jsx(Ce,{})}),e.jsx(u,{path:"/configuration/homelab",element:e.jsx(Pe,{})}),e.jsx(u,{path:"/configuration/lan",element:e.jsx(Ie,{})}),e.jsx(u,{path:"/configuration/port-forwarding",element:e.jsx(Ae,{})}),e.jsx(u,{path:"/configuration/dyndns",element:e.jsx(Ee,{})}),e.jsx(u,{path:"/configuration/global-dns",element:e.jsx(He,{})}),e.jsx(u,{path:"/configuration/webui",element:e.jsx(Te,{})})]})})]})}(()=>{try{const t=localStorage.getItem("theme"),r=window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)").matches,n=t?t==="dark":r,a=document.documentElement;n?a.classList.add("dark"):a.classList.remove("dark")}catch{}})();K.createRoot(document.getElementById("root")).render(e.jsx(g.StrictMode,{children:e.jsx(Re,{})}));
