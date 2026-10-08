"""``devin-export``: dump Devin Enterprise API records as JSON for warehouse loading.

Every command writes one JSON object per record (JSON Lines by default) so
the output can be ``PUT`` to a stage and ``COPY INTO`` a
``(data VARIANT, loaded_at TIMESTAMP)`` table, or piped into any loader.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from collections.abc import Iterable
from datetime import datetime, timedelta, timezone
from typing import Any, TextIO

from devin_export.api import DEFAULT_BASE_URL, DevinClient, org_display_name

API_KEY_ENV = "DEVIN_ENTERPRISE_API_KEY"
BASE_URL_ENV = "DEVIN_API_BASE_URL"

_DURATION = re.compile(r"^(?P<n>\d+)(?P<unit>[smhdw])$")
_UNIT_SECONDS = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}


def parse_timestamp(value: str, now: datetime | None = None) -> int:
    """Unix seconds from an epoch, an ISO-8601 timestamp, ``now`` or a relative ``-7d`` / ``7d``."""
    now = now or datetime.now(timezone.utc)
    value = value.strip()
    if value == "now":
        return int(now.timestamp())
    if value.isdigit():
        return int(value)
    match = _DURATION.match(value.lstrip("-"))
    if match:
        seconds = int(match["n"]) * _UNIT_SECONDS[match["unit"]]
        return int((now - timedelta(seconds=seconds)).timestamp())
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def write_records(records: Iterable[dict[str, Any]], out: TextIO, fmt: str) -> int:
    records = list(records)
    if fmt == "json":
        json.dump(records, out)
        out.write("\n")
    else:
        for record in records:
            out.write(json.dumps(record, separators=(",", ":")))
            out.write("\n")
    return len(records)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="devin-export",
        description="Export Devin Enterprise API records as JSON for warehouse loading.",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        help=f"Devin Enterprise API key (default: ${API_KEY_ENV})",
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help=f"API base URL (default: ${BASE_URL_ENV} or {DEFAULT_BASE_URL})",
    )
    parser.add_argument("-o", "--output", default="-", help="Output file (default: stdout)")
    parser.add_argument(
        "--format",
        choices=["jsonl", "json"],
        default="jsonl",
        help="jsonl: one object per line (default); json: a single JSON array",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Log each API page to stderr")

    sub = parser.add_subparsers(dest="command", required=True)

    window_help = "Epoch seconds, ISO-8601, 'now', or a relative duration like 7d / 36h"

    sessions = sub.add_parser("sessions", help="Sessions updated in a time window")
    sessions.add_argument("--updated-after", default="7d", help=f"Window start (default: 7d). {window_help}")
    sessions.add_argument("--updated-before", default="now", help=f"Window end (default: now). {window_help}")

    audit = sub.add_parser("audit-logs", help="Audit-log entries in a time window")
    audit.add_argument("--time-after", default="1d", help=f"Window start (default: 1d). {window_help}")
    audit.add_argument("--time-before", default="now", help=f"Window end (default: now). {window_help}")

    sub.add_parser("organizations", help="All organizations in the enterprise")

    members = sub.add_parser("members", help="Direct members of each organization (stamped with org_id/org_name)")
    members.add_argument("--org", action="append", dest="org_ids", help="Org ID to export (repeatable; default: all)")

    sub.add_parser("roles", help="All enterprise and org roles")

    return parser


def run(args: argparse.Namespace, client: DevinClient) -> list[dict[str, Any]]:
    if args.command == "sessions":
        after, before = parse_timestamp(args.updated_after), parse_timestamp(args.updated_before)
        return client.sessions(updated_after=after, updated_before=before)
    if args.command == "audit-logs":
        after, before = parse_timestamp(args.time_after), parse_timestamp(args.time_before)
        return client.audit_logs(time_after=after, time_before=before)
    if args.command == "organizations":
        return client.organizations()
    if args.command == "roles":
        return client.roles()
    if args.command == "members":
        orgs = client.organizations()
        names = {org["org_id"]: org_display_name(org) for org in orgs}
        org_ids = args.org_ids or list(names)
        records: list[dict[str, Any]] = []
        for org_id in org_ids:
            for member in client.org_members(org_id):
                member["org_id"] = org_id
                member["org_name"] = names.get(org_id)
                records.append(member)
        return records
    raise ValueError(f"Unknown command {args.command}")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        stream=sys.stderr,
        format="%(levelname)s %(message)s",
    )

    api_key = args.api_key or os.environ.get(API_KEY_ENV, "")
    if not api_key:
        parser.error(f"no API key: pass --api-key or set ${API_KEY_ENV}")
    base_url = args.base_url or os.environ.get(BASE_URL_ENV) or DEFAULT_BASE_URL

    client = DevinClient(api_key=api_key, base_url=base_url)
    records = run(args, client)

    if args.output == "-":
        count = write_records(records, sys.stdout, args.format)
    else:
        with open(args.output, "w", encoding="utf-8") as handle:
            count = write_records(records, handle, args.format)
    logging.getLogger(__name__).info("%s: wrote %d records", args.command, count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
