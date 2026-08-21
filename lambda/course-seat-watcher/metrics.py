"""Hand-rolled CloudWatch Embedded Metric Format (EMF) emission to stdout.

Deliberately not `aws-embedded-metrics` (adds an async flush/threading
model and its own dependency surface for the same output) and not
`cloudwatch:PutMetricData` (not resource-scopable -- would need an
unscopable "*" IAM grant, plus per-call cost). One JSON object per line,
never pretty-printed: CloudWatch Logs parses EMF per log event.
"""
import json
import time

_NAMESPACE = "SiaSeatWatcher"


def emit_course_metric(course_code: str, course_name: str, seats_available: int) -> None:
    """Emitted once per configured course, every invocation, regardless of
    whether any notification email is sent -- CourseName is a property, not
    a dimension, to keep metric cardinality at one dimension (CourseCode)
    while staying queryable in Logs Insights."""
    payload = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": _NAMESPACE,
                    "Dimensions": [["CourseCode"]],
                    "Metrics": [{"Name": "SeatsAvailable", "Unit": "Count"}],
                }
            ],
        },
        "CourseCode": course_code,
        "CourseName": course_name,
        "SeatsAvailable": seats_available,
    }
    print(json.dumps(payload))


def emit_run_metrics(
    courses_scraped: int,
    courses_requested: int,
    emails_sent: int,
    emails_failed: int,
) -> None:
    """Emitted exactly once per invocation, in handler.py's `finally` block
    so it fires even on failure (with whatever counts were reached before
    the failure). Empty dimension set: these are run-level totals, not
    per-course. CoursesScraped < 1 over 3 consecutive periods is the
    monitoring.tf alarm that catches a successful-but-empty run, or the
    schedule going silent entirely (missing data also breaches it)."""
    payload = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": _NAMESPACE,
                    "Dimensions": [[]],
                    "Metrics": [
                        {"Name": "CoursesScraped", "Unit": "Count"},
                        {"Name": "CoursesRequested", "Unit": "Count"},
                        {"Name": "EmailsSent", "Unit": "Count"},
                        {"Name": "EmailsFailed", "Unit": "Count"},
                    ],
                }
            ],
        },
        "CoursesScraped": courses_scraped,
        "CoursesRequested": courses_requested,
        "EmailsSent": emails_sent,
        "EmailsFailed": emails_failed,
    }
    print(json.dumps(payload))
