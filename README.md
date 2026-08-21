<p align="center">
  <img src="email/assets/logo.png" width="96" height="96" alt="SIA Seat Watcher logo">
</p>

<h1 align="center">course-seat-watcher</h1>

<p align="center">
  A serverless watcher that polls UNAL's SIA course catalog for open seats<br>
  and emails you the moment one appears.
</p>

<p align="center">
  <a href="https://github.com/estanixx/effective-sia-spoon/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/estanixx/effective-sia-spoon/ci.yml?branch=main&label=CI&style=flat-square"></a>
  <img alt="Terraform" src="https://img.shields.io/badge/terraform-%3E%3D1.11-844FBA?style=flat-square&logo=terraform&logoColor=white">
  <img alt="AWS Lambda" src="https://img.shields.io/badge/AWS-Lambda%20(container)-FF9900?style=flat-square&logo=awslambda&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-unlicensed-lightgrey?style=flat-square">
</p>

---

## What it does

Registering for a full course at UNAL means refreshing the SIA catalog by
hand, hoping to catch a seat the instant someone drops. `course-seat-watcher`
does that watching for you: every 10 minutes between 06:00 and 13:00
(America/Bogotá), it heads to the catalog, checks the courses you care about,
and — the moment one has an open seat — sends you an email with the details
and a link straight to the SIA.

No laptop needs to stay open, no cron job needs babysitting. It's a
zero-maintenance Lambda that runs whether you're asleep, in class, or nowhere
near a computer.

## How it works

```
 EventBridge Scheduler                    CloudWatch
   (every 10 min, 06:00-13:00) │            Alarms
              │                │        ┌──────┴──────┐
              ▼                │        │  Errors ≥ 1 │
   ┌────────────────────┐      │        │ Scraped < 1 │
   │   Lambda (image)    │──────┘        └──────┬──────┘
   │  Firefox + geckodriver                      │
   └──────────┬───────────┘                      ▼
              │ reads config                 SNS → ops email
              ▼
        SSM Parameter Store
     (courses, filters, recipients)
              │
              ▼
      scrape sia.unal.edu.co
              │
     ┌────────┴────────┐
     ▼                  ▼
 EMF metrics      seat found?
 → CloudWatch          │ yes
                        ▼
                 render email (Maizzle + Jinja2)
                        │
                        ▼
                 SESv2 → your inbox
```

A single container image bundles a pinned Firefox ESR + geckodriver, the
Python scraper/handler, and a pre-built HTML email template. There's no
server to patch, no credentials in the codebase, and no manual step between
"a seat opens" and "you get an email" — SES and IAM handle delivery and
access end to end.

## Repository layout

| Path | What lives there |
|---|---|
| `bootstrap/` | One-time trust anchor: Terraform state bucket, GitHub OIDC roles, ECR repo. Applied manually, once. |
| `modules/lambda-container-function/` | Reusable container-image Lambda module (exec role, log group, IAM policy). |
| `environments/prod/` | The actual deployment: SSM config, SES identities, the schedule, monitoring, the email-asset bucket, and the Lambda itself. |
| `lambda/course-seat-watcher/` | The scraper/handler Python code and its `Dockerfile`. |
| `email/` | The Maizzle project that builds the seat-alert HTML email, baked into the image at build time. |
| `scripts/` | One-time/local operator scripts (`tf-init.sh`, `setup-branch-protection.sh`, `build-logo-asset.sh`). |
| `.github/workflows/` | `ci.yml` (fmt/validate/tflint/checkov/image scan), `pr.yml` (plan + sticky comment), `cd.yml` (build, push, apply on merge to `main`). |

## Getting started

See **[AGENTS.md](AGENTS.md)** for the full contributor guide: local setup,
how to run the test suite, how to build and smoke-test the container image,
and every manual one-time operational step (SES verification, branch
protection, the logo asset pipeline, and the deliberate architectural
choices worth knowing before you touch this code).

## Status

This project follows a chained-PR delivery plan; each PR is independently
`terraform validate`/`plan`-clean before merge. Track progress via the
merged PR history — bootstrap, the Lambda module, the prod environment,
and the email/scraper implementation are complete; CI/CD and policy files
are the current work.
