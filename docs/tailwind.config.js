/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
    "node_modules/flowbite-react/lib/esm/**/*.js",
  ],
  theme: {
    extend: {
      screens: {
        'xl-custom': '1650px', // Custom breakpoint for hamburger menu
      },
    },
  },
  plugins: [
    require('flowbite/plugin'),
    require('flowbite-typography'),
  ],
}

