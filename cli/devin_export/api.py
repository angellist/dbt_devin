"""Thin client for the Devin Enterprise API (v3).

https://docs.devin.ai/api-reference/v3/overview

List endpoints return ``{"items": [...], "end_cursor": "...", "has_next_page": bool}``
and paginate with ``first`` (page size, max 200) and ``after`` (cursor).
"""

from __future__ import annotations

import logging
from collections.abc import Iterator
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

DEFAULT_BASE_URL = "https://api.devin.ai/v3/enterprise"
PAGE_SIZE = 200
MAX_PAGES = 500

LOG = logging.getLogger(__name__)


class DevinClient:
    def __init__(
        self,
        api_key: str,
        base_url: str = DEFAULT_BASE_URL,
        timeout: float = 60,
        session: requests.Session | None = None,
    ) -> None:
        if not api_key:
            raise ValueError("A Devin Enterprise API key is required")
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.session = session or _retry_session()
        self.session.headers.update({"Accept": "application/json", "Authorization": f"Bearer {api_key}"})

    def get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        response = self.session.get(f"{self.base_url}{path}", params=params, timeout=self.timeout)
        LOG.debug("GET %s -> %s", response.url, response.status_code)
        response.raise_for_status()
        return response.json()

    def iter_list(self, path: str, params: dict[str, Any] | None = None) -> Iterator[dict[str, Any]]:
        """Yield every item from a paginated list endpoint."""
        request_params = dict(params or {})
        request_params.setdefault("first", PAGE_SIZE)
        previous_cursor = None
        for page in range(1, MAX_PAGES + 1):
            payload = self.get(path, request_params)
            items = payload.get("items") or []
            LOG.info("%s page %d: %d records", path, page, len(items))
            yield from items
            cursor = payload.get("end_cursor")
            if not payload.get("has_next_page") or not cursor:
                return
            if cursor == previous_cursor:
                raise RuntimeError(f"Devin API returned a repeated cursor for {path}: {cursor}")
            previous_cursor = cursor
            request_params["after"] = cursor
        raise RuntimeError(f"Devin API pagination exceeded {MAX_PAGES} pages for {path}")

    def list(self, path: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        return list(self.iter_list(path, params))

    # --- endpoints ---------------------------------------------------------

    def sessions(self, updated_after: int, updated_before: int) -> list[dict[str, Any]]:
        """Sessions updated in [updated_after, updated_before) (Unix seconds).

        Windowing on updated_at rather than created_at re-captures ACU
        consumption, status and pull requests as a session progresses.
        """
        return self.list("/sessions", {"updated_after": updated_after, "updated_before": updated_before})

    def audit_logs(self, time_after: int, time_before: int) -> list[dict[str, Any]]:
        """Audit-log entries in [time_after, time_before) (Unix seconds)."""
        return self.list("/audit-logs", {"time_after": time_after, "time_before": time_before})

    def organizations(self) -> list[dict[str, Any]]:
        return self.list("/organizations")

    def org_members(self, org_id: str) -> list[dict[str, Any]]:
        return self.list(f"/organizations/{org_id}/members/users")

    def roles(self) -> list[dict[str, Any]]:
        return self.list("/roles")


def org_display_name(org: dict[str, Any]) -> str | None:
    return org.get("name")


def _retry_session() -> requests.Session:
    retry = Retry(
        total=10,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        respect_retry_after_header=True,
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    return session
