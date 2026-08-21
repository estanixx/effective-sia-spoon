import json

from metrics import emit_course_metric, emit_run_metrics


def test_emit_course_metric_shape(capsys):
    emit_course_metric("3006931", "Estadística", 3)

    line = capsys.readouterr().out.strip()
    payload = json.loads(line)

    assert payload["CourseCode"] == "3006931"
    assert payload["CourseName"] == "Estadística"
    assert payload["SeatsAvailable"] == 3
    metric = payload["_aws"]["CloudWatchMetrics"][0]
    assert metric["Namespace"] == "SiaSeatWatcher"
    assert metric["Dimensions"] == [["CourseCode"]]
    assert metric["Metrics"] == [{"Name": "SeatsAvailable", "Unit": "Count"}]


def test_emit_course_metric_is_single_line(capsys):
    emit_course_metric("3006931", "Estadística", 3)

    out = capsys.readouterr().out
    assert out.count("\n") == 1


def test_emit_run_metrics_shape(capsys):
    emit_run_metrics(courses_scraped=2, courses_requested=3, emails_sent=1, emails_failed=0)

    payload = json.loads(capsys.readouterr().out.strip())

    assert payload["CoursesScraped"] == 2
    assert payload["CoursesRequested"] == 3
    assert payload["EmailsSent"] == 1
    assert payload["EmailsFailed"] == 0
    metric = payload["_aws"]["CloudWatchMetrics"][0]
    assert metric["Dimensions"] == [[]]
    assert {m["Name"] for m in metric["Metrics"]} == {
        "CoursesScraped",
        "CoursesRequested",
        "EmailsSent",
        "EmailsFailed",
    }
