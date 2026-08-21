/** @type {import('@maizzle/framework').Config} */
export default {
  build: {
    content: ['src/templates/**/*.html'],
    output: {
      from: ['src/templates'],
      path: 'build_production',
      extension: 'html',
    },
    summary: false,
  },
  components: {
    folders: ['src/components', 'src/templates', 'src/layouts'],
  },
  // Inlining only runs when `css.inline` is present at all (any truthy
  // value, including {}) -- absent by default, which is why the base
  // config.js does not set it (kept faster for local iteration).
  css: {
    inline: {
      applyWidthAttributes: ['table', 'td', 'img'],
      applyHeightAttributes: ['table', 'td', 'img'],
    },
  },
  prettify: false,
  minify: {
    lineLengthLimit: 500,
    removeIndentations: true,
    removeCSSComments: true,
    removeHTMLComments: true,
  },
}
