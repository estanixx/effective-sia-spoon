// Pinned to @maizzle/framework ^5.5.0 (see package.json), NOT the current
// v6 line -- v6 is a ground-up rewrite (Vue components, Tailwind v4,
// visual-editor tooling) with no `tailwind.config.js`/classic `content`
// build shape. v5 is the last release matching this project's plain
// static-template use case and design.md's assumed config.js/
// config.<env>.js/tailwind.config.js structure. Re-evaluate the pin if v5
// is ever deprecated upstream.

/** @type {import('@maizzle/framework').Config} */
export default {
  build: {
    content: ['src/templates/**/*.html'],
    // Without this, Maizzle's default `from: ['emails']` doesn't match our
    // src/templates path, so it falls back to preserving the full relative
    // path and outputs build_local/src/templates/seat-alert.html instead
    // of the flat build_local/seat-alert.html the Dockerfile expects.
    output: {
      from: ['src/templates'],
      path: 'build_local',
    },
  },
  // Explicit (not the CLI default ['components', 'emails', 'layouts']) so
  // the on-disk layout matches design.md's file tree: src/layouts/main.html
  // is registered as the <x-main> component, resolved from src/templates/
  // seat-alert.html.
  components: {
    folders: ['src/components', 'src/templates', 'src/layouts'],
  },
}
