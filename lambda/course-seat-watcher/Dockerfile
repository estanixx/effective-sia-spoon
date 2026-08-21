# Build context is the repo root (docker build -f lambda/course-seat-watcher/Dockerfile .)
# so this stage can reach email/ -- see design.md "Delivery into Lambda:
# baked into the container image at build time".
FROM node:20-alpine AS email
WORKDIR /app
COPY email/package.json email/package-lock.json ./
RUN npm ci
COPY email/ ./
RUN npx maizzle build production

FROM public.ecr.aws/lambda/python:3.12 AS runtime

# Firefox ESR + geckodriver, pinned by version AND SHA256 (design.md
# "Sizing" -- rejects selenium/standalone-firefox: a Grid-server stack with
# no Lambda Runtime Interface Client, dragging in VNC/Java and worsening
# the Trivy gate for no benefit here). Checksums verified against Mozilla's
# own published SHA256SUMS (Firefox) and the GitHub release asset
# (geckodriver has no published checksum file; the pin below was computed
# by downloading the exact release URL directly). Re-verify both on bump.
ARG FIREFOX_VERSION=140.14.0esr
ARG FIREFOX_SHA256=e0a56bd257b7ee6741688a15770cbd14ebfad5eff98eff833ba3af34f8d41649
ARG GECKODRIVER_VERSION=0.37.1
ARG GECKODRIVER_SHA256=e815130ea95983e162ae91843b48d3a3ce991735635fce83a647afde21e09f7e

RUN curl -fsSL -o /tmp/firefox.tar.xz \
      "https://ftp.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/linux-x86_64/en-US/firefox-${FIREFOX_VERSION}.tar.xz" \
    && echo "${FIREFOX_SHA256}  /tmp/firefox.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/firefox.tar.xz -C /opt \
    && rm /tmp/firefox.tar.xz \
    && curl -fsSL -o /tmp/geckodriver.tar.gz \
      "https://github.com/mozilla/geckodriver/releases/download/v${GECKODRIVER_VERSION}/geckodriver-v${GECKODRIVER_VERSION}-linux64.tar.gz" \
    && echo "${GECKODRIVER_SHA256}  /tmp/geckodriver.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/geckodriver.tar.gz -C /opt \
    && rm /tmp/geckodriver.tar.gz \
    && chmod +x /opt/geckodriver /opt/firefox/firefox

# Read-only filesystem outside /tmp (design.md "Lambda-specific additions"):
# both Firefox's own profile/cache dirs and Python's default temp-file
# locations must land in /tmp, not the image's read-only layers.
ENV HOME=/tmp
ENV TMPDIR=/tmp

COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Flat build_production/seat-alert.html (not nested under src/templates/)
# -- see email/config.production.js's `build.output.from` setting.
COPY --from=email /app/build_production/seat-alert.html ${LAMBDA_TASK_ROOT}/templates/seat-alert.html

COPY config.py scraper.py metrics.py notifier.py handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
