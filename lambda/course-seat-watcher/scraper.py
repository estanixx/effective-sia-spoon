"""Selenium/Firefox scraping logic ported from the original search.py
prototype, refactored for Lambda (design.md 'Changes from search.py'):

- Fixed /opt/geckodriver + /opt/firefox/firefox binaries (Dockerfile-pinned
  by version and SHA256) instead of webdriver_manager's runtime download.
- Course/filter/label values come from SSM config, not hardcoded constants.
- time.sleep(1.5) after each filter selection is replaced by an explicit
  WebDriverWait on the *next* dependent select becoming populated -- the
  SIA catalog form re-populates each select via an AJAX postback after the
  previous one is chosen, and sleep() was purely working around that
  latency. Waiting for len(options) > 1 (a real done-signal) instead of a
  fixed delay is the #1 flake fix this design calls for.
- Each course starts from a fresh driver.get(catalog_url) rather than
  clicking the form's "Volver" (back) button -- avoids depending on that
  button existing/working, and is no more expensive than the click-then-
  wait-for-repaint it replaces.
"""
import os
import re
import time

from selenium import webdriver
from selenium.common.exceptions import (
    NoSuchElementException,
    StaleElementReferenceException,
    TimeoutException,
)
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait

GECKODRIVER_PATH = "/opt/geckodriver"
FIREFOX_BINARY_PATH = "/opt/firefox/firefox"
PROFILE_PATH = "/tmp/ff-profile"
WAIT_TIMEOUT_SECONDS = 30

_SHOW_BUTTON_XPATH = "//a[contains(., 'Mostrar')] | //button[contains(., 'Mostrar')] | //span[text()='Mostrar']"
_AVAILABILITY_XPATH = "//*[contains(text(), 'Cupos disponibles')]"


def parse_seats(availability_text: str) -> int:
    """Extracts the seat count from the element matched by
    _AVAILABILITY_XPATH, e.g. "Cupos disponibles: 3" -> 3. Split out so the
    contract test (tests/test_scraper_contract.py) can lock this exact
    XPath + parsing pair against a saved fixture without needing a live
    browser."""
    numbers = re.findall(r"\d+", availability_text)
    return int(numbers[0]) if numbers else 0


def build_driver() -> webdriver.Firefox:
    """The container filesystem is read-only outside /tmp, so the Firefox
    profile is pinned there explicitly (Dockerfile also sets HOME/TMPDIR to
    /tmp for the same reason). The directory must be created here, not in
    the Dockerfile: Lambda provisions /tmp fresh per execution environment
    -- it is ephemeral storage, not part of the image -- so anything
    created there at build time never reaches the real runtime. Confirmed
    via a local Docker build: geckodriver fails with "Failed to set
    preferences: unknown error" if the -profile directory doesn't already
    exist when it launches Firefox."""
    os.makedirs(PROFILE_PATH, exist_ok=True)
    service = Service(GECKODRIVER_PATH)
    options = Options()
    options.binary_location = FIREFOX_BINARY_PATH
    options.add_argument("--headless")
    options.add_argument("-profile")
    options.add_argument(PROFILE_PATH)
    return webdriver.Firefox(service=service, options=options)


_SELECT_STALE_RETRIES = 3
_SELECT_POLL_INITIAL_SECONDS = 0.25
_SELECT_POLL_MAX_SECONDS = 2.0
_SELECT_POLL_MULTIPLIER = 2
_SELECT_NUDGE_AFTER_SECONDS = 10.0


def _wait_for_enabled_select(driver, xpath: str, timeout_seconds: float, nudge=None):
    """Exponential-backoff poll (0.25s, 0.5s, 1s, 2s, 2s, ...) instead of
    WebDriverWait's fixed-interval polling -- the postback that enables
    these selects is itself variable-latency (confirmed live: sometimes
    ~1s, sometimes long enough to blow a 20s fixed-poll budget), so a
    fixed short interval either burns needless round-trips early or a
    fixed long one wastes time on the common fast case. Re-finds the
    element on every poll rather than reusing a reference, since the
    element the previous poll saw may already be a stale, swapped-out
    node by the time this one runs.

    Confirmed live that "slow" and "never" are both real: reproduced a case
    where a select stayed disabled with zero options for a full 40s
    straight -- SIA's AJAX cascade sometimes just doesn't fire for a given
    field, no amount of waiting fixes that. Also confirmed live that
    re-selecting the *previous* field's same value reliably kicks the stuck
    postback loose (observed ready ~2s after the nudge). If `nudge` is
    given, it's called once, after `_SELECT_NUDGE_AFTER_SECONDS` of no
    progress, well before the overall timeout -- not a replacement for the
    timeout, a rescue for the common "cascade silently dropped" case."""
    deadline = time.monotonic() + timeout_seconds
    nudge_at = time.monotonic() + _SELECT_NUDGE_AFTER_SECONDS
    nudged = False
    delay = _SELECT_POLL_INITIAL_SECONDS
    while True:
        try:
            candidate = driver.find_element(By.XPATH, xpath)
            if candidate.is_enabled() and len(Select(candidate).options) > 1:
                return candidate
        except StaleElementReferenceException:
            pass
        now = time.monotonic()
        if not nudged and nudge is not None and now >= nudge_at:
            nudge()
            nudged = True
        if now >= deadline:
            raise TimeoutException(
                f"Select for xpath {xpath!r} never became enabled within {timeout_seconds}s"
            )
        time.sleep(delay)
        delay = min(delay * _SELECT_POLL_MULTIPLIER, _SELECT_POLL_MAX_SECONDS)


def _select_label(driver, label: str, text: str, previous: tuple = None) -> None:
    """Selects `text` in the <select> following the label `label`.

    The SIA form's dependent selects render their full <option> list
    up front but stay `disabled` until the previous select's AJAX (JSF PPR)
    postback finishes and replaces the DOM node -- so `len(options) > 1`
    alone passes immediately against the still-disabled element and races
    the postback (confirmed live: `select_by_visible_text` on the
    still-disabled node raises `NotImplementedError: You may not select a
    disabled option`).

    Confirmed live that a single postback isn't the whole story either: the
    node can go stale a *second* time between this function's own
    find/check/select calls (each is a separate round-trip to the browser,
    and JSF can re-render more than once in quick succession), so staleness
    is caught and the entire find-wait-select sequence is retried, not just
    the initial lookup.

    `previous`, when given, is the `(label, text)` of the select chosen
    right before this one -- used to build a nudge callback (re-selecting
    that same value) for `_wait_for_enabled_select` to fire if this select
    never wakes up on its own."""
    xpath = f"//label[contains(text(), '{label}')]/following::select[1]"

    nudge = None
    if previous is not None:
        prev_label, prev_text = previous
        prev_xpath = f"//label[contains(text(), '{prev_label}')]/following::select[1]"

        def nudge():
            try:
                prev_element = driver.find_element(By.XPATH, prev_xpath)
                Select(prev_element).select_by_visible_text(prev_text)
            except (StaleElementReferenceException, NoSuchElementException):
                pass

    for attempt in range(_SELECT_STALE_RETRIES):
        try:
            element = _wait_for_enabled_select(driver, xpath, WAIT_TIMEOUT_SECONDS, nudge=nudge)
            Select(element).select_by_visible_text(text)
            return
        except StaleElementReferenceException:
            if attempt == _SELECT_STALE_RETRIES - 1:
                raise


def scrape_courses(driver: webdriver.Firefox, catalog_url: str, filters: dict, courses: list) -> list:
    """Returns one entry per configured course, always the full list
    (unavailable courses included with seats=0) -- design.md 'Scraper
    output' contract, so their SeatsAvailable metric is still emitted."""
    wait = WebDriverWait(driver, WAIT_TIMEOUT_SECONDS)
    results = []

    for course in courses:
        driver.get(catalog_url)

        previous = None
        for label, text in filters.items():
            _select_label(driver, label, text, previous=previous)
            previous = (label, text)

        show_button = wait.until(EC.element_to_be_clickable((By.XPATH, _SHOW_BUTTON_XPATH)))
        driver.execute_script("arguments[0].click();", show_button)

        code_link_xpath = f"//a[text()='{course['code']}']"
        link = wait.until(EC.element_to_be_clickable((By.XPATH, code_link_xpath)))
        driver.execute_script("arguments[0].click();", link)

        availability_element = wait.until(
            EC.visibility_of_element_located((By.XPATH, _AVAILABILITY_XPATH))
        )
        seats = parse_seats(availability_element.text)

        results.append({"code": course["code"], "name": course["name"], "seats": seats})

    return results
