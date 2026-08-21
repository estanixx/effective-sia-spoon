/** @type {import('tailwindcss').Config} */
module.exports = {
  presets: [
    require('tailwindcss-preset-email'),
  ],
  content: [
    './src/components/**/*.html',
    './src/templates/**/*.html',
    './src/layouts/**/*.html',
  ],
  theme: {
    extend: {
      colors: {
        canvas: '#FBF8F2', // page + body background
        brand: '#0F332E', // header + footer bands
        ink: '#1A2E2A', // primary body text
        muted: '#6B7C77', // secondary text, timestamps, footer legal
        accent: '#D89B3A', // gold hairline under header, seat-count emphasis
        // Corrected CTA fill: white-on-#FF6B4A (the original literal spec)
        // measures 2.82:1, failing WCAG AA at every text size. White on
        // #C24328 measures 5.09:1, passing AA normal text. See tasks.md
        // Phase 4.2 -- this was already resolved during planning, not
        // reopened here.
        cta: '#C24328',
        positive: '#4E9B7C', // "disponible" badge
      },
    },
  },
}
