# AGENTS.md — course-seat-watcher

Contributor guide: local setup, how the pieces fit together, every manual
one-time operational step, and the deliberate (sometimes non-obvious)
decisions worth knowing before you change this code.

## Repository layout

```
bootstrap/                       One-time trust anchor (state bucket, OIDC roles, ECR). Local state, manual apply.
modules/lambda-container-function/  Reusable container-image Lambda module.
environments/prod/               The real deployment: SSM, SES, schedule, monitoring, email assets, the Lambda itself.
lambda/course-seat-watcher/      Scraper/handler Python code + Dockerfile.
email/                           Maizzle project building the seat-alert HTML email.
scripts/                         tf-init.sh, setup-branch-protection.sh, build-logo-asset.sh.
.github/workflows/               ci.yml, pr.yml, cd.yml.
```

## Local setup

**Terraform** (any root):
```bash
terraform fmt -check -recursive
cd <root> && terraform init -backend=false && terraform validate
tflint --init && tflint --recursive
checkov --directory . --framework terraform --config-file .checkov.yml --compact
```

**Email** (`email/`):
```bash
cd email && npm ci
npx maizzle build production   # -> email/build_production/seat-alert.html
```
Pinned to `@maizzle/framework ^5.5.0` — **not** the current v6 line. v6 is a
ground-up rewrite (Vue components, Tailwind v4, visual-editor tooling) with
no `tailwind.config.js`/classic `content`-glob build shape. v5 is the last
release matching this project's plain static-template use case. Don't
upgrade past v5 without rewriting `config.js`/`config.production.js`/
`tailwind.config.js` from scratch against the new API.

**Lambda** (`lambda/course-seat-watcher/`):
```bash
cd lambda/course-seat-watcher
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

**Container image** (repo root — the Dockerfile needs `email/` in its build
context):
```bash
docker build -f lambda/course-seat-watcher/Dockerfile -t sia-course-seat-watcher:local .
```

## Architectural decisions worth knowing

- **`x86_64`, not `arm64`.** A deliberate deviation from this repo family's
  usual `arm64` default: Mozilla does not publish official aarch64 Linux
  Firefox/geckodriver builds on the same footing as x86_64. Don't "fix"
  this later without re-verifying that constraint.
- **Firefox ESR + geckodriver are pinned by version AND SHA256** in the
  Dockerfile (`ARG FIREFOX_VERSION`/`FIREFOX_SHA256`, `GECKODRIVER_VERSION`/
  `GECKODRIVER_SHA256`). Firefox's checksum is verified against Mozilla's
  own published `SHA256SUMS`; geckodriver publishes no checksum file, so
  its pin was computed by downloading the exact release asset and hashing
  it directly. **Re-verify both, the same way, whenever you bump either
  version** — there is no automation checking this.
- **SSM config uses `lifecycle { ignore_changes = [value] }`.** Terraform
  seeds a minimal value on first apply (so the Lambda never fails on a
  missing parameter) and then never touches the value again — an operator
  edits the real config via `aws ssm put-parameter --overwrite`. `name`/
  `type`/`tags` stay Terraform-managed; only `value` is ignored. Changing
  the *seed* in Terraform after the first apply does nothing; changing the
  real config is an SSM operation, not a `terraform apply`.
- **Recipient emails end up in Terraform state.** The SSM parameter is
  `String`, not `SecureString` — Terraform refreshes and stores its real
  value in state on every plan. State lives in a private, versioned,
  SSE-S3-encrypted bucket readable only by the two OIDC roles. If that's
  ever unacceptable, the escape hatch is an out-of-band `SecureString`
  parameter (Terraform never calls `GetParameter` on it, at the cost of
  losing the "always exists" seed guarantee).
- **`SENDER_EMAIL`/`SES_CONFIGURATION_SET`/`LOGO_URL` are Lambda environment
  variables, not SSM fields.** They're deploy-time infra values Terraform
  already knows exactly; SSM stays scoped to operator-mutable business
  config (courses/filters/recipients).
- **The GitHub OIDC provider is a `data` source, not a `resource`.** IAM
  OIDC providers are keyed by URL and scoped to the whole AWS account, not
  per-project — this account already had one (from an unrelated
  pre-existing setup) before this project's first `terraform apply`, which
  failed with `EntityAlreadyExists` until this was fixed. Never convert it
  back to a `resource`.
- **Two `aws_scheduler_schedule` instances, not one.** "Every 10 minutes,
  06:00–13:00, inclusive of the 13:00 run" isn't expressible as a single
  cron expression — minute and hour fields are independent. `cron(0/10
  6-12 ? * * *)` covers 06:00–12:50; `cron(0 13 ? * * *)` covers 13:00
  exactly. Both live in a custom schedule group named `sia-watcher` (not
  the `default` group) — the group name has to start with `sia-` for
  bootstrap's IAM wildcard (`schedule/sia-*`) to match, since a Scheduler
  ARN is `schedule/<group>/<name>`.
- **The container image measures 1.61GB** (`docker images --format
  '{{.Size}}'`, verified locally after every trim below, real build not
  an estimate) — headless Firefox needs a real GTK3/X11/cairo/pango/mesa/
  dbus shared-library stack that the minimal Lambda base image doesn't
  ship. Still comfortably under the 10GB image limit. Install these with
  `--setopt=install_weak_deps=0` — plain `dnf install gtk3` pulls in
  ~150MB of unrelated pipewire/xdg-desktop-portal/systemd-user packages
  this image has no use for. `ci.yml`'s `image` job prints this same
  number on every run.
  - **`docker inspect --format '{{.Size}}'` lies on this image** —
    verified it reports 416MiB against a real 1.72GB on-disk size
    (confirmed independently via `docker save | wc -c`), because buildx
    exports an attestation manifest list here and `docker inspect`
    reads the wrong field off it. `docker images`'s `Size` column is the
    one that matched reality. Don't reach for `docker inspect` on this
    image's size again without re-checking that.
- **Dead-weight trims applied, fused into the same `RUN` layer that
  creates the bytes** (a `rm` in a *later* layer doesn't shrink the
  image — layers are additive): dropped `boto3` from
  `requirements.txt` (the Lambda Python base image already ships
  boto3/botocore; pinning it forced a redundant install of botocore's
  full AWS service-model set, the single heaviest thing in most boto
  projects); stripped Firefox's crashreporter/pingsender/updater/
  spellcheck-dictionary files (update-channel and spellcheck machinery,
  unused by a headless single-invocation scraper); stripped non-en/es
  `/usr/share/locale` trees from the dnf-installed GTK3/mesa stack;
  stripped `mesa-dri-drivers` down to just the software-rasterizer path
  (`swrast_dri.so`/`kms_swrast_dri.so` symlinks, their real target
  `libdril_dri.so`, `pipe_swrast.so`, `libgallium-*.so` — confirmed via
  `rpm -qf` all four belong to `mesa-dri-drivers` itself), deleting
  ~84MB of vendor GPU drivers (radeonsi/nouveau/i915/iris/panfrost/...)
  a headless Lambda never has hardware for — `mesa-libgbm` hard-`Requires`
  the whole package (`install_weak_deps=0` doesn't stop it; confirmed via
  `rpm -q --qf '%{SIZE}'`, 134MB installed). **Verified after every trim
  above**: `build_driver()` still launches Firefox and completes a real
  `.get()` navigation in the built image (not just "the build
  succeeded").
- **`scraper.py`'s Firefox profile directory is created at runtime, not
  build time.** Lambda provisions `/tmp` fresh per execution environment —
  it's ephemeral storage, not part of the image — so `RUN mkdir` in the
  Dockerfile would be a no-op in real Lambda even though it "works" in a
  local `docker build`. `build_driver()` calls `os.makedirs(...,
  exist_ok=True)` every invocation instead.
- **Firefox logs a sandbox warning on every launch**
  (`CanCreateUserNamespace() clone() failure: EPERM`) — confirmed
  non-fatal locally (Firefox falls back and both a headless screenshot and
  a full Selenium session succeed regardless). **Not yet confirmed in real
  AWS Lambda** — Lambda's gVisor sandbox is stricter than a default local
  Docker container, and there are public reports of this exact
  incompatibility being worse there. This is the single biggest unverified
  risk in the whole design until an actual Lambda invocation is observed
  post-deploy.

## Manual, one-time operational steps

These are **never** automated — they're either genuinely one-time, require
human judgment, or would create real billable/destructive infrastructure if
run by CI.

1. **Apply `bootstrap/` manually.**
   ```bash
   cd bootstrap && terraform init && terraform plan && terraform apply
   ```
   Then record its 5 outputs as GitHub repo variables:
   ```bash
   for name in state_bucket_name plan_role_arn apply_role_arn lambda_exec_boundary_arn ecr_repository_url; do
     gh variable set "$(echo "$name" | tr '[:lower:]' '[:upper:]')" --body "$(terraform output -raw "$name")"
   done
   ```
   (Repo variable names: `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`,
   `AWS_APPLY_ROLE_ARN`, `LAMBDA_EXEC_BOUNDARY_ARN`, `ECR_REPOSITORY_URL`.)

2. **Set `OPS_EMAIL` and `SENDER_EMAIL` repo variables.** `environments/prod`
   requires both (`var.ops_email`, `var.sender_email`) with no defaults —
   design.md left these as open questions (no confirmed sender domain, no
   confirmed ops address). `ci.yml`'s plan job and `cd.yml`'s apply job both
   read them via `TF_VAR_*`; without them, every plan/apply fails on a
   missing required variable.
   ```bash
   gh variable set OPS_EMAIL --body "ops-alerts@example.com"
   gh variable set SENDER_EMAIL --body "watcher@example.com"
   ```

3. **Request SES production access** and verify the sender identity — start
   this early, external approval lead time is unknown. While in the SES
   sandbox, both sender *and every recipient* must be a verified identity;
   `var.sandbox_verified_recipients` (a tfvars list) exists only for this
   period. Emptying that list is the visible marker that production access
   has landed.

4. **Extract the logo asset** (already done for the initial build, re-run
   only if `logo.svg`'s source art changes):
   ```bash
   ./scripts/build-logo-asset.sh   # requires ImageMagick (`magick`)
   ```
   `logo.svg` (the ~2.2MB source, a raster PNG wrapped in an SVG shell —
   confirmed by direct inspection, not actually vector) is **not** committed
   to this repo; only the extracted, downscaled `email/assets/logo.png`
   (~11KB) is.

5. **Confirm the SNS ops-topic subscription** — one email click, after the
   first successful `environments/prod` apply.

6. **Run `scripts/setup-branch-protection.sh` once**, after CI has gone
   green at least once on a PR (GitHub can only require a check name it has
   already observed). User-run only — refuses to run under `CI=1`.

7. **End-to-end verification** (post-deploy): force a bad course code in
   the SSM config and confirm the `sia-watcher-errors` alarm fires with no
   seat email sent.

## Testing

| Layer | Command | What it catches |
|---|---|---|
| Terraform | `terraform fmt`/`validate`/`tflint`/`checkov` per root | Syntax, type, lint, and policy issues — all blocking in `ci.yml`. |
| Python unit | `pytest lambda/course-seat-watcher` | Config validation, EMF shape, recipient grouping, Jinja2 escaping, error policy. No AWS, no browser. |
| Scraper contract | Included in the pytest run above | Locks the scraper's XPath/label contract against a saved HTML fixture, without a live browser. |
| Image build | `docker build -f lambda/course-seat-watcher/Dockerfile .` | Whether the image actually builds — the Dockerfile's COPY paths, shared-library set, and archive tooling are all only proven correct by actually building it. |
| Image scan | `ci.yml`'s `image` job (Trivy, `HIGH,CRITICAL`, `ignore-unfixed: true`) | Supply-chain vulnerabilities in the built image. |
| Firefox smoke test | `docker run --entrypoint python3.12 <image> -c "from scraper import build_driver; build_driver().quit()"` | Whether headless Firefox actually launches inside the image — the highest-risk unknown in this design. |
| Lambda RIE integration | Manual (design task 5.10, not CI-automated) | A full local invocation against the Lambda Runtime Interface Emulator with a stub SSM config. |

## CI/CD

- **`ci.yml`** (`workflow_call` only): `fmt`, `validate` (matrix over
  `bootstrap`/`environments/prod`/`modules/lambda-container-function`),
  `tflint`, `checkov`, `image` (build without push, then Trivy scan).
- **`pr.yml`**: runs `ci`, then — only for same-repo PRs, never forks —
  assumes the read-only plan role and posts a sticky `terraform plan`
  comment on `environments/prod`.
- **`cd.yml`**: runs `ci`, then builds and pushes the image to ECR, then
  applies `environments/prod` with that exact commit's image tag.

Job **ids** in `ci.yml` are load-bearing — GitHub renders them as `<caller
job id> / <job name>` (e.g. `ci / fmt`), and branch protection requires
those exact strings.
