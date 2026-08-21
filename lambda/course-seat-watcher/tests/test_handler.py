"""Verifies handler.py's error policy (design.md 'Error policy and ops
alerting'): run-level metrics are always emitted, even when scraping
raises, and the exception always propagates -- no swallowed failure.
"""
import json

import pytest

import handler


_CONFIG = {
    "catalog_url": "https://sia.unal.edu.co/",
    "filters": {},
    "courses": [{"code": "A", "name": "Curso A"}],
    "recipients": [],
}


class _FakeDriver:
    def quit(self):
        pass


def test_lambda_handler_emits_run_metrics_and_reraises_on_scrape_failure(monkeypatch, capsys):
    monkeypatch.setattr(handler, "load_config", lambda: _CONFIG)
    monkeypatch.setattr(handler, "build_driver", lambda: _FakeDriver())

    def _boom(*args, **kwargs):
        raise RuntimeError("scrape failed")

    monkeypatch.setattr(handler, "scrape_courses", _boom)

    with pytest.raises(RuntimeError, match="scrape failed"):
        handler.lambda_handler({}, None)

    run_metric_lines = [
        line for line in capsys.readouterr().out.splitlines() if "CoursesScraped" in line
    ]
    assert len(run_metric_lines) == 1
    payload = json.loads(run_metric_lines[0])
    assert payload["CoursesScraped"] == 0
    assert payload["CoursesRequested"] == 1
    assert payload["EmailsSent"] == 0
    assert payload["EmailsFailed"] == 0


def test_lambda_handler_happy_path_emits_metrics_and_returns_summary(monkeypatch, capsys):
    monkeypatch.setattr(handler, "load_config", lambda: _CONFIG)
    monkeypatch.setattr(handler, "build_driver", lambda: _FakeDriver())
    monkeypatch.setattr(
        handler, "scrape_courses", lambda *a, **k: [{"code": "A", "name": "Curso A", "seats": 2}]
    )
    monkeypatch.setattr(handler, "send_notifications", lambda *a, **k: (1, 0))

    result = handler.lambda_handler({}, None)

    assert result == {"coursesScraped": 1, "emailsSent": 1}

    out_lines = capsys.readouterr().out.splitlines()
    course_metrics = [json.loads(line) for line in out_lines if '"CourseCode"' in line]
    run_metrics = [json.loads(line) for line in out_lines if '"CoursesScraped"' in line]

    assert len(course_metrics) == 1
    assert course_metrics[0]["SeatsAvailable"] == 2
    assert len(run_metrics) == 1
    assert run_metrics[0]["CoursesScraped"] == 1
    assert run_metrics[0]["CoursesRequested"] == 1
    assert run_metrics[0]["EmailsSent"] == 1
    assert run_metrics[0]["EmailsFailed"] == 0
