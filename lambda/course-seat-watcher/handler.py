"""Lambda entrypoint. Orchestrates config -> scrape -> metrics -> notify.

Error policy (design.md 'Error policy and ops alerting'): no blanket
`except` that swallows and returns normally -- a swallowed exception is
invisible to the AWS/Lambda Errors metric the sia-watcher-errors alarm
depends on. `emit_run_metrics` runs in `finally` so it fires with whatever
counts were reached even when scraping or notifying raises, then the
exception propagates on its own -- this is the "emit what's available,
then re-raise" behavior, without an explicit `except ... raise`.
"""
from config import load_config
from metrics import emit_course_metric, emit_run_metrics
from notifier import send_notifications
from scraper import build_driver, scrape_courses


def lambda_handler(event, context):
    config = load_config()

    courses_requested = len(config["courses"])
    courses_scraped = 0
    emails_sent = 0
    emails_failed = 0

    try:
        driver = build_driver()
        try:
            results = scrape_courses(
                driver,
                catalog_url=config["catalog_url"],
                filters=config["filters"],
                courses=config["courses"],
            )
        finally:
            driver.quit()

        courses_scraped = len(results)
        for course in results:
            emit_course_metric(course["code"], course["name"], course["seats"])

        emails_sent, emails_failed = send_notifications(
            results, config["recipients"], catalog_url=config["catalog_url"]
        )

        return {"coursesScraped": courses_scraped, "emailsSent": emails_sent}
    finally:
        emit_run_metrics(courses_scraped, courses_requested, emails_sent, emails_failed)
