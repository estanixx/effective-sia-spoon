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

# public.ecr.aws/lambda/python:3.12 (Amazon Linux 2023 based) ships none of
# tar/xz/gzip (needed to unpack the archives below) nor the shared-library
# stack headless Firefox links against at runtime (GTK3 + its X11/cairo/
# pango/mesa/dbus dependency chain) -- confirmed empirically via a local
# build: without these, Firefox fails to even start ("XPCOMGlueLoad error
# ... libgtk-3.so.0: cannot open shared object file"). install_weak_deps=0
# keeps this to the actual link-time dependency set instead of also
# pulling in gtk3's optional weak deps (pipewire, xdg-desktop-portal,
# systemd user services) which add ~150MB and multiple running-service
# packages for no reason in a headless, single-invocation Lambda image.
# Locale stripping happens in this SAME RUN, not a later one -- a `rm` in a
# later layer only hides the bytes from the merged view, it doesn't shrink
# the image (each layer is additive). Non-en locale trees are dead weight:
# this project only ever renders/logs in en/es and dnf's own translations
# aren't read at runtime.
# mesa-libgbm hard-Requires mesa-dri-drivers (~134MB, confirmed via
# `rpm -q --qf '%{SIZE}'` -- not a weak dep, install_weak_deps=0 above
# doesn't stop it). It ships one DRI/gallium driver .so per real GPU vendor
# (radeonsi, nouveau, i915, iris, panfrost, ...) headless Lambda never has
# hardware for. Kept: swrast_dri.so + kms_swrast_dri.so (the software-
# rasterizer symlinks GBM/EGL actually load when there's no GPU) and their
# real targets -- libdril_dri.so, pipe_swrast.so, libgallium-*.so
# (confirmed via `rpm -qf` all three belong to mesa-dri-drivers itself).
# Verified after trimming: Firefox still launches and completes a full
# Selenium session in this image (build_driver() smoke test).
# dnf upgrade -y fused into this same RUN, before install: the base image
# (public.ecr.aws/lambda/python:3.12) ships whatever Amazon Linux 2023
# packages were current at its own build time, which lag behind AL2023's
# rolling security updates. Real, live finding via the Trivy PR gate: 3
# HIGH CVEs (libsoup3 CVE-2026-15711, openssl-fips-provider-latest and
# openssl-snapsafe-libs both CVE-2026-14456), all already "fixed" upstream
# -- a plain upgrade, not a workaround. Runs before the explicit installs
# below so the newly-pulled packages start from patched versions too, and
# stays fused (not a later RUN) for the same reason cleanup below is fused:
# an upgrade in a later layer doesn't shrink or replace the earlier layer's
# bytes, it only adds more on top.
RUN dnf upgrade -y --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
    && dnf install -y --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
      tar xz gzip findutils gtk3 libXt dbus-glib mesa-libgbm alsa-lib \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
         ! -name 'en*' ! -name 'es*' -exec rm -rf {} + \
    && find /usr/lib64/dri -mindepth 1 \
         ! -name 'swrast_dri.so' ! -name 'kms_swrast_dri.so' ! -name 'libdril_dri.so' -delete \
    && find /usr/lib64/gallium-pipe -mindepth 1 ! -name 'pipe_swrast.so' -delete

# Cleanup below is fused into the same RUN as the extraction (same reason as
# above). Everything removed is dead weight for a headless, single-purpose
# scraper: crashreporter/pingsender/updater are update-channel machinery
# this Lambda never uses (the image itself is the update mechanism), and
# spellcheck dictionaries are never exercised by Selenium automation.
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
    && chmod +x /opt/geckodriver /opt/firefox/firefox \
    && rm -rf /opt/firefox/crashreporter /opt/firefox/crashreporter.ini \
              /opt/firefox/crashreporter-override.ini /opt/firefox/pingsender \
              /opt/firefox/updater /opt/firefox/update-settings.ini \
              /opt/firefox/precomplete /opt/firefox/removed-files \
              /opt/firefox/dictionaries

# Firefox's content-process sandbox tries to create an unprivileged user
# namespace and fails under both a default `docker run` and (per public
# reports of Firefox-under-Lambda) the real Lambda gVisor sandbox --
# confirmed locally: "Sandbox: CanCreateUserNamespace() clone() failure:
# EPERM". This is non-fatal -- Firefox falls back and still runs correctly
# (verified: headless screenshot and a full Selenium session both succeed
# despite the warning) -- but it prints to stderr on every launch, so it's
# called out here rather than left as an unexplained warning in every
# invocation's logs.

# Read-only filesystem outside /tmp (design.md "Lambda-specific additions"):
# both Firefox's own profile/cache dirs and Python's default temp-file
# locations must land in /tmp, not the image's read-only layers.
ENV HOME=/tmp
ENV TMPDIR=/tmp

# COPY sources are resolved against the build context (repo root), not
# this Dockerfile's own directory -- every lambda/ source needs the full
# lambda/course-seat-watcher/ prefix.
COPY lambda/course-seat-watcher/requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Flat build_production/seat-alert.html (not nested under src/templates/)
# -- see email/config.production.js's `build.output.from` setting.
COPY --from=email /app/build_production/seat-alert.html ${LAMBDA_TASK_ROOT}/templates/seat-alert.html

COPY lambda/course-seat-watcher/config.py lambda/course-seat-watcher/scraper.py lambda/course-seat-watcher/metrics.py lambda/course-seat-watcher/notifier.py lambda/course-seat-watcher/handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
