import json

import pytest

from config import ConfigError, validate_config, load_config

_VALID_CONFIG = {
    "version": 1,
    "catalog_url": "https://sia.unal.edu.co/example",
    "filters": {"Nivel de estudio": "Pregrado"},
    "courses": [{"code": "3006931", "name": "Estadística"}],
    "recipients": [{"email": "student@unal.edu.co", "courses": ["3006931"]}],
}


def test_validate_config_accepts_valid_shape():
    assert validate_config(dict(_VALID_CONFIG)) == _VALID_CONFIG


@pytest.mark.parametrize("missing_key", ["catalog_url", "filters", "courses", "recipients"])
def test_validate_config_rejects_missing_key(missing_key):
    config = dict(_VALID_CONFIG)
    del config[missing_key]

    with pytest.raises(ConfigError, match=missing_key):
        validate_config(config)


def test_validate_config_rejects_unknown_course_code_in_recipient():
    config = dict(_VALID_CONFIG)
    config["recipients"] = [{"email": "student@unal.edu.co", "courses": ["9999999"]}]

    with pytest.raises(ConfigError, match="9999999"):
        validate_config(config)


class _StubSsmClient:
    class exceptions:
        class ParameterNotFound(Exception):
            pass

    def __init__(self, value=None, raise_not_found=False):
        self._value = value
        self._raise_not_found = raise_not_found

    def get_parameter(self, Name):
        if self._raise_not_found:
            raise self.exceptions.ParameterNotFound()
        return {"Parameter": {"Value": self._value}}


def test_load_config_raises_on_missing_parameter():
    client = _StubSsmClient(raise_not_found=True)

    with pytest.raises(ConfigError, match="not found"):
        load_config(parameter_name="/sia/prod/watcher/config", ssm_client=client)


def test_load_config_raises_on_malformed_json():
    client = _StubSsmClient(value="{not valid json")

    with pytest.raises(ConfigError, match="not valid JSON"):
        load_config(parameter_name="/sia/prod/watcher/config", ssm_client=client)


def test_load_config_returns_validated_config():
    client = _StubSsmClient(value=json.dumps(_VALID_CONFIG))

    assert load_config(parameter_name="/sia/prod/watcher/config", ssm_client=client) == _VALID_CONFIG
