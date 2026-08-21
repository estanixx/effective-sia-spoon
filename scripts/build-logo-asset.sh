#!/usr/bin/env bash
# One-time, manually-run extraction of the email logo asset. NOT a CI step
# (design.md "Logo asset pipeline"): logo.svg is confirmed (by direct
# inspection) to be a viewBox="0 0 1254 1254" wrapper around a single
# image/png;base64 payload -- a raster masquerading as vector, so SVG
# optimization cannot help. This script extracts that payload and downscales
# it to a 240px PNG (2x a 120px email render) for email/assets/logo.png,
# which is committed as a build output so the email asset is deterministic
# and reviewable in a PR, and CI needs no image-processing toolchain.
#
# Requires ImageMagick (`magick`). Re-run only if logo.svg's source art
# changes.
set -euo pipefail

cd "$(dirname "$0")/.."

grep -o 'base64,[^"]*' logo.svg | cut -d, -f2 | base64 -d > /tmp/logo-full.png
magick /tmp/logo-full.png -resize 240x240 -strip PNG8:email/assets/logo.png
rm -f /tmp/logo-full.png

echo "Wrote email/assets/logo.png ($(du -h email/assets/logo.png | cut -f1))"
