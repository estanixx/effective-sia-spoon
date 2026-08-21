"""Locks scraper.py's XPath/label contract against a saved HTML fixture,
without a live browser (design.md 'Contract' test layer -- the separate
'Integration' layer, task 5.10, is what actually exercises Firefox).
"""
from pathlib import Path

from lxml import etree

from scraper import _AVAILABILITY_XPATH, parse_seats

_FIXTURE_PATH = Path(__file__).parent / "fixtures" / "sia_result_page.html"


def test_availability_xpath_matches_fixture():
    tree = etree.HTML(_FIXTURE_PATH.read_text(encoding="utf-8"))
    matches = tree.xpath(_AVAILABILITY_XPATH)

    assert matches, "_AVAILABILITY_XPATH did not match anything in the fixture"
    assert parse_seats(matches[0].text) == 3


def test_parse_seats_extracts_first_number():
    assert parse_seats("Cupos disponibles: 12") == 12


def test_parse_seats_returns_zero_when_no_number_present():
    assert parse_seats("Cupos disponibles: ninguno") == 0
