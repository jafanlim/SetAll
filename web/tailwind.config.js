/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './web/portal.html',
    './web/insights.html',
    './web/login.html',
    './web/reset-password.html',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          deep:      '#020617',
          slate:     '#0F172A',
          border:    '#1E293B',
          teal:      '#14B8A6',
          tealHover: '#0D9488',
          purple:    '#8B5CF6',
          orange:    '#F97316',
        }
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', 'sans-serif'],
      }
    }
  },
  plugins: [],
}
