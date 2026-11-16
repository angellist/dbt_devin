import io
import json
from datetime import datetime, timezone

import requests
import responses

from devin_export.api import DEFAULT_BASE_URL
from devin_export.cli import main, parse_timestamp, write_records

NOW = datetime(2026, 10, 8, 12, 0, tzinfo=timezone.utc)


def test_parse_timestamp_forms():
    assert parse_timestamp("1700000000", NOW) == 1700000000
    assert parse_timestamp("now", NOW) == int(NOW.timestamp())
    assert parse_timestamp("1d", NOW) == int(NOW.timestamp()) - 86400
    assert parse_timestamp("-36h", NOW) == int(NOW.timestamp()) - 36 * 3600
    midnight = int(datetime(2026, 10, 8, tzinfo=timezone.utc).timestamp())
    assert parse_timestamp("2026-10-08T00:00:00Z", NOW) == midnight
    assert parse_timestamp("2026-10-08", NOW) == midnight


def test_write_records_jsonl_and_json():
    out = io.StringIO()
    assert write_records([{"a": 1}, {"b": 2}], out, "jsonl") == 2
    assert out.getvalue() == '{"a":1}\n{"b":2}\n'

    out = io.StringIO()
    write_records([{"a": 1}], out, "json")
    assert json.loads(out.getvalue()) == [{"a": 1}]


@responses.activate
def test_members_are_stamped_with_org(tmp_path, monkeypatch):
    monkeypatch.setenv("DEVIN_ENTERPRISE_API_KEY", "k")
    responses.get(
        f"{DEFAULT_BASE_URL}/organizations",
        json={"items": [{"org_id": "org-1", "name": "Finance"}], "has_next_page": False},
    )
    responses.get(
        f"{DEFAULT_BASE_URL}/organizations/org-1/members/users",
        json={"items": [{"user_id": "u-1", "email": "a@example.com"}], "has_next_page": False},
    )
    output = tmp_path / "members.jsonl"

    assert main(["-o", str(output), "members"]) == 0

    rows = [json.loads(line) for line in output.read_text().splitlines()]
    assert rows == [{"user_id": "u-1", "email": "a@example.com", "org_id": "org-1", "org_name": "Finance"}]


@responses.activate
def test_common_options_accepted_after_subcommand(tmp_path, monkeypatch):
    monkeypatch.setenv("DEVIN_ENTERPRISE_API_KEY", "k")
    responses.get(f"{DEFAULT_BASE_URL}/roles", json={"items": [{"role_id": "r-1"}], "has_next_page": False})
    output = tmp_path / "roles.json"

    assert main(["roles", "-o", str(output), "--format", "json"]) == 0

    assert json.loads(output.read_text()) == [{"role_id": "r-1"}]


@responses.activate
def test_api_failure_returns_nonzero(monkeypatch, caplog):
    monkeypatch.setenv("DEVIN_ENTERPRISE_API_KEY", "k")
    responses.get(f"{DEFAULT_BASE_URL}/roles", body=requests.ConnectionError("boom"))

    assert main(["roles"]) == 1
    assert "API request failed" in caplog.text


def test_missing_api_key_errors(monkeypatch, capsys):
    monkeypatch.delenv("DEVIN_ENTERPRISE_API_KEY", raising=False)
    try:
        main(["roles"])
    except SystemExit as exc:
        assert exc.code == 2
    assert "no API key" in capsys.readouterr().err
