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

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait

GECKODRIVER_PATH = "/opt/geckodriver"
FIREFOX_BINARY_PATH = "/opt/firefox/firefox"
PROFILE_PATH = "/tmp/ff-profile"
WAIT_TIMEOUT_SECONDS = 20

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


def _select_label(wait: WebDriverWait, label: str, text: str) -> None:
    xpath = f"//label[contains(text(), '{label}')]/following::select[1]"
    element = wait.until(EC.presence_of_element_located((By.XPATH, xpath)))
    wait.until(lambda _d: len(Select(element).options) > 1)
    Select(element).select_by_visible_text(text)


def scrape_courses(driver: webdriver.Firefox, catalog_url: str, filters: dict, courses: list) -> list:
    """Returns one entry per configured course, always the full list
    (unavailable courses included with seats=0) -- design.md 'Scraper
    output' contract, so their SeatsAvailable metric is still emitted."""
    wait = WebDriverWait(driver, WAIT_TIMEOUT_SECONDS)
    results = []

    for course in courses:
        driver.get(catalog_url)

        for label, text in filters.items():
            _select_label(wait, label, text)

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
