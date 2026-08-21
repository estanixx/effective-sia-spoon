"""Groups scrape results by recipient and sends the seat-alert email via
SESv2. Renders the Maizzle-built, already-Tailwind-compiled-and-inlined
HTML (baked into the image at Docker build time -- see the Dockerfile's
`email` stage and design.md 'Email / Maizzle: Delivery into Lambda') with
Jinja2, using custom [[ var ]] / [% tag %] delimiters because Maizzle owns
the default {{ }} / {{{ }}} syntax at build time. autoescape=True is a
security control, not polish: course names and seat counts are scraped
from an external, uncontrolled page and injected into HTML sent to third
parties.
"""
import os
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3
import jinja2
from botocore.exceptions import BotoCoreError, ClientError

_TEMPLATE_NAME = "seat-alert.html"
_BOGOTA_TZ = ZoneInfo("America/Bogota")


def _build_jinja_env(template_dir: str) -> jinja2.Environment:
    return jinja2.Environment(
        loader=jinja2.FileSystemLoader(template_dir),
        autoescape=True,
        variable_start_string="[[",
        variable_end_string="]]",
        block_start_string="[%",
        block_end_string="%]",
    )


def group_matches_by_recipient(results: list, recipients: list) -> dict:
    """One email per recipient per invocation, sent only if >=1 of *their*
    courses has seats > 0. Only available courses are listed -- unavailable
    ones stay metrics-only (already emitted by handler.py before this
    runs)."""
    seats_by_code = {course["code"]: course for course in results}
    grouped = {}

    for recipient in recipients:
        available = [
            seats_by_code[code]
            for code in recipient["courses"]
            if code in seats_by_code and seats_by_code[code]["seats"] > 0
        ]
        if available:
            grouped[recipient["email"]] = available

    return grouped


def _build_subject(courses: list) -> str:
    if len(courses) == 1:
        return f"Cupos disponibles: {courses[0]['name']}"
    return f"Cupos disponibles: {len(courses)} asignaturas — SIA UNAL"


def _build_preheader(courses: list) -> str:
    return f"{len(courses)} asignatura(s) con cupo disponible ahora."


def _build_plaintext(courses: list, cta_url: str) -> str:
    """Mandatory plain-text alternative on every send (spam-filter hygiene
    + clients that reject HTML-only) -- built directly from the course
    list rather than derived from the HTML, so it needs no extra parsing
    dependency."""
    lines = ["Se encontraron cupos disponibles en las siguientes asignaturas:", ""]
    for course in courses:
        lines.append(f"- {course['name']} ({course['code']}): {course['seats']} cupo(s) disponible(s)")
    lines.append("")
    lines.append(f"Ver en el SIA: {cta_url}")
    return "\n".join(lines)


def send_notifications(
    results: list,
    recipients: list,
    catalog_url: str,
    ses_client=None,
    template_dir: str = None,
) -> tuple:
    """Returns (emails_sent, emails_failed). A failed send for one
    recipient does not stop the others -- each is independent."""
    grouped = group_matches_by_recipient(results, recipients)
    if not grouped:
        return 0, 0

    ses = ses_client or boto3.client("sesv2")
    template_dir = template_dir or os.environ.get("SEAT_ALERT_TEMPLATE_DIR", "/var/task/templates")
    template = _build_jinja_env(template_dir).get_template(_TEMPLATE_NAME)
    generated_at = datetime.now(_BOGOTA_TZ).strftime("%Y-%m-%d %H:%M %Z")

    sender_email = os.environ["SENDER_EMAIL"]
    configuration_set = os.environ["SES_CONFIGURATION_SET"]
    logo_url = os.environ["LOGO_URL"]

    sent, failed = 0, 0

    for recipient_email, courses in grouped.items():
        html = template.render(
            preheader=_build_preheader(courses),
            recipient_email=recipient_email,
            courses=courses,
            cta_url=catalog_url,
            logo_url=logo_url,
            generated_at_bogota=generated_at,
        )
        text = _build_plaintext(courses, catalog_url)

        try:
            ses.send_email(
                FromEmailAddress=sender_email,
                Destination={"ToAddresses": [recipient_email]},
                Content={
                    "Simple": {
                        "Subject": {"Data": _build_subject(courses), "Charset": "UTF-8"},
                        "Body": {
                            "Html": {"Data": html, "Charset": "UTF-8"},
                            "Text": {"Data": text, "Charset": "UTF-8"},
                        },
                    }
                },
                ConfigurationSetName=configuration_set,
            )
            sent += 1
        except (BotoCoreError, ClientError):
            failed += 1

    return sent, failed
