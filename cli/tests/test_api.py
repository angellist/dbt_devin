import pytest
import responses

from devin_export.api import DEFAULT_BASE_URL, DevinClient, org_display_name


@pytest.fixture
def client():
    return DevinClient(api_key="test-key")


@responses.activate
def test_iter_list_follows_cursors(client):
    responses.get(
        f"{DEFAULT_BASE_URL}/sessions",
        json={"items": [{"session_id": "a"}], "end_cursor": "c1", "has_next_page": True},
        match=[responses.matchers.query_param_matcher({"first": "200", "updated_after": "1", "updated_before": "2"})],
    )
    responses.get(
        f"{DEFAULT_BASE_URL}/sessions",
        json={"items": [{"session_id": "b"}], "end_cursor": None, "has_next_page": False},
        match=[
            responses.matchers.query_param_matcher(
                {"first": "200", "after": "c1", "updated_after": "1", "updated_before": "2"}
            )
        ],
    )

    assert client.sessions(updated_after=1, updated_before=2) == [{"session_id": "a"}, {"session_id": "b"}]
    assert responses.calls[0].request.headers["Authorization"] == "Bearer test-key"


@responses.activate
def test_iter_list_rejects_repeated_cursor(client):
    responses.get(
        f"{DEFAULT_BASE_URL}/roles",
        json={"items": [{"role_id": "r"}], "end_cursor": "same", "has_next_page": True},
    )
    responses.get(
        f"{DEFAULT_BASE_URL}/roles",
        json={"items": [{"role_id": "r"}], "end_cursor": "same", "has_next_page": True},
    )
    with pytest.raises(RuntimeError, match="repeated cursor"):
        client.roles()


def test_requires_api_key():
    with pytest.raises(ValueError):
        DevinClient(api_key="")


@pytest.mark.parametrize(
    ("org", "expected"),
    [
        ({"name": "Finance"}, "Finance"),
        ({"name": "Finance", "org_name": "Legacy"}, "Finance"),
        ({"name": ""}, ""),
        ({"name": None}, None),
        ({}, None),
        ({"org_name": "Legacy"}, None),
    ],
)
def test_org_display_name_uses_name_only(org, expected):
    assert org_display_name(org) == expected
