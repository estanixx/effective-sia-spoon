"""Reads and validates the watcher's runtime config from SSM. One
ssm:GetParameter call per invocation -- the module's only IAM grant besides
logging and ses:SendEmail (design.md 'Lambda exec role').

Parameter name is a hardcoded convention matching environments/prod/ssm.tf's
`/${name_prefix}/prod/watcher/config` (name_prefix defaults to "sia"), not
passed via a Lambda environment variable -- environment_variables is
reserved for deploy-time infra values (SENDER_EMAIL, SES_CONFIGURATION_SET,
LOGO_URL), while this SSM parameter name is itself part of that same
deploy-time contract and stays a plain default here, overridable for tests.
"""
import json
import os

import boto3

_DEFAULT_PARAMETER_NAME = "/sia/prod/watcher/config"


class ConfigError(Exception):
    """SSM config parameter missing, not valid JSON, missing a required
    key, or a recipient references a course code that isn't configured."""


def load_config(parameter_name: str = None, ssm_client=None) -> dict:
    parameter_name = parameter_name or os.environ.get(
        "WATCHER_CONFIG_PARAMETER", _DEFAULT_PARAMETER_NAME
    )
    ssm = ssm_client or boto3.client("ssm")

    try:
        response = ssm.get_parameter(Name=parameter_name)
    except ssm.exceptions.ParameterNotFound as exc:
        raise ConfigError(f"SSM parameter {parameter_name} not found") from exc

    raw_value = response["Parameter"]["Value"]

    try:
        config = json.loads(raw_value)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"SSM parameter {parameter_name} is not valid JSON: {exc}") from exc

    return validate_config(config)


def validate_config(config: dict) -> dict:
    for key in ("catalog_url", "filters", "courses", "recipients"):
        if key not in config:
            raise ConfigError(f"config missing required key: {key}")

    known_codes = {course["code"] for course in config["courses"]}

    for recipient in config["recipients"]:
        for code in recipient["courses"]:
            if code not in known_codes:
                raise ConfigError(
                    f"recipient {recipient['email']} references unknown course code {code!r}"
                )

    return config
