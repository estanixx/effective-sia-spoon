import os
from pathlib import Path

import pytest
from botocore.exceptions import ClientError

from notifier import (
    _build_plaintext,
    _build_preheader,
    _build_subject,
    group_matches_by_recipient,
    send_notifications,
)

_FIXTURES_DIR = Path(__file__).parent / "fixtures"

_RESULTS = [
    {"code": "A", "name": "Curso A", "seats": 3},
    {"code": "B", "name": "Curso B", "seats": 0},
    {"code": "C", "name": "Curso C", "seats": 1},
]


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setenv("SENDER_EMAIL", "watcher@example.com")
    monkeypatch.setenv("SES_CONFIGURATION_SET", "sia-watcher")
    monkeypatch.setenv("LOGO_URL", "https://assets.example.com/logo.png")


class _StubSesClient:
    def __init__(self, fail_for=()):
        self.sent = []
        self._fail_for = set(fail_for)

    def send_email(self, **kwargs):
        to_address = kwargs["Destination"]["ToAddresses"][0]
        if to_address in self._fail_for:
            raise ClientError(
                {"Error": {"Code": "MessageRejected", "Message": "simulated SES failure"}},
                "SendEmail",
            )
        self.sent.append(kwargs)


def test_group_matches_by_recipient_only_includes_available_courses():
    recipients = [{"email": "a@example.com", "courses": ["A", "B"]}]

    grouped = group_matches_by_recipient(_RESULTS, recipients)

    assert list(grouped.keys()) == ["a@example.com"]
    assert [c["code"] for c in grouped["a@example.com"]] == ["A"]


def test_group_matches_by_recipient_skips_recipient_with_no_matches():
    recipients = [{"email": "nobody@example.com", "courses": ["B"]}]

    assert group_matches_by_recipient(_RESULTS, recipients) == {}


def test_group_matches_by_recipient_groups_multiple_courses_into_one_entry():
    recipients = [{"email": "a@example.com", "courses": ["A", "C"]}]

    grouped = group_matches_by_recipient(_RESULTS, recipients)

    assert len(grouped) == 1
    assert {c["code"] for c in grouped["a@example.com"]} == {"A", "C"}


def test_subject_singular_vs_plural():
    assert _build_subject([{"name": "Curso A"}]) == "Cupos disponibles: Curso A"
    assert _build_subject([{"name": "A"}, {"name": "B"}]) == "Cupos disponibles: 2 asignaturas — SIA UNAL"


def test_preheader_includes_count():
    assert _build_preheader([{"name": "A"}, {"name": "B"}]) == "2 asignatura(s) con cupo disponible ahora."


def test_plaintext_includes_each_course_and_cta():
    text = _build_plaintext([{"name": "Curso A", "code": "A", "seats": 3}], "https://sia.unal.edu.co/")

    assert "Curso A (A): 3 cupo(s) disponible(s)" in text
    assert "https://sia.unal.edu.co/" in text


def test_send_notifications_only_sends_to_recipients_with_matches():
    ses = _StubSesClient()
    recipients = [
        {"email": "a@example.com", "courses": ["A"]},
        {"email": "nobody@example.com", "courses": ["B"]},
    ]

    sent, failed = send_notifications(
        _RESULTS, recipients, catalog_url="https://sia.unal.edu.co/",
        ses_client=ses, template_dir=str(_FIXTURES_DIR),
    )

    assert sent == 1
    assert failed == 0
    assert len(ses.sent) == 1
    assert ses.sent[0]["Destination"]["ToAddresses"] == ["a@example.com"]
    assert ses.sent[0]["FromEmailAddress"] == "watcher@example.com"
    assert ses.sent[0]["ConfigurationSetName"] == "sia-watcher"


def test_send_notifications_counts_partial_failure_without_aborting():
    ses = _StubSesClient(fail_for={"a@example.com"})
    recipients = [
        {"email": "a@example.com", "courses": ["A"]},
        {"email": "c@example.com", "courses": ["C"]},
    ]

    sent, failed = send_notifications(
        _RESULTS, recipients, catalog_url="https://sia.unal.edu.co/",
        ses_client=ses, template_dir=str(_FIXTURES_DIR),
    )

    assert sent == 1
    assert failed == 1


def test_send_notifications_escapes_malicious_course_name():
    results = [{"code": "X", "name": "<script>alert(1)</script>", "seats": 1}]
    recipients = [{"email": "a@example.com", "courses": ["X"]}]
    ses = _StubSesClient()

    send_notifications(
        results, recipients, catalog_url="https://sia.unal.edu.co/",
        ses_client=ses, template_dir=str(_FIXTURES_DIR),
    )

    html = ses.sent[0]["Content"]["Simple"]["Body"]["Html"]["Data"]
    assert "<script>" not in html
    assert "&lt;script&gt;" in html
