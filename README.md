# dbt_devin

Analytics-ready dbt models for [Devin](https://devin.ai) Enterprise usage, plus the
`devin-export` CLI that pulls the raw records from the Devin Enterprise API.

Answer questions like:

- How many sessions and ACUs per org, user, origin (Slack, webapp, API, automation…) per week?
- How many pull requests do sessions open, and how many get merged?
- Who was added to or removed from which Devin org, by whom, and with which roles?

Lifted from the models and extractor the AngelList data team runs in production.
Snowflake only for now (see [Warehouse support](#warehouse-support)).

## Status

v0.1: first public release, being adopted by the AngelList data team. Install by `git:` pin until it is
listed on the [dbt Package Hub](https://hub.getdbt.com); the Hub listing will
follow once the package has run against production data for a while. Issues and
PRs welcome.

## How it fits together

```
Devin Enterprise API ──devin-export──▶ JSON ──your loader──▶ raw landing tables ──dbt_devin──▶ marts
 /sessions                                                  (data VARIANT,              fct_devin_sessions
 /audit-logs                                                 loaded_at)                 fct_devin_pull_requests
 /organizations, /roles                                                                 fct_devin_org_membership_changes
 /organizations/{id}/members/users                                                      agg_devin_acu_daily
                                                                                        dim_devin_users
                                                                                        dim_devin_organizations
                                                                                        dim_devin_roles
```

The package deliberately stops at the API/warehouse seam: `devin-export` writes
JSON, you land it with whatever you already run (Airflow, cron, GitHub Actions,
Snowflake tasks), and the dbt package expects one landing table per feed.

## 1. Export: `devin-export`

```bash
pip install "devin-export @ git+https://github.com/angellist/dbt_devin#subdirectory=cli"
export DEVIN_ENTERPRISE_API_KEY=...   # a read-only enterprise service-user key

devin-export sessions --updated-after 7d            # sessions updated in the last 7 days
devin-export audit-logs --time-after 1d             # audit-log entries from the last day
devin-export organizations
devin-export members                                # every org's members, stamped with org_id / org_name
devin-export roles
```

Output is JSON Lines on stdout (`--format json` for a single array, `-o FILE`
to write a file). Time arguments accept epoch seconds, ISO-8601, `now`, or a
relative duration such as `7d` / `36h`.

Windowing guidance, so the dbt models stay correct:

| Feed | How to run | Why |
|---|---|---|
| `sessions` | Daily, rolling window (e.g. `--updated-after 7d`) | Sessions change after creation (ACUs, status, PRs). Re-exporting re-captures them; dbt keeps the latest load per `session_id`. Use a large window once to backfill. |
| `audit-logs` | Hourly or daily, contiguous windows (overlap is fine) | Entries are immutable; dbt dedupes on `audit_log_id`. |
| `organizations`, `roles` | Daily full snapshot | Small; dbt keeps the latest row per id. |
| `members` | Daily full snapshot | Snapshots are retained so removed users still resolve to a name and email. |

## 2. Land: the landing contract

One table per feed, append-only, in a schema the dbt package can read:

```sql
create schema if not exists raw.devin;

create table if not exists raw.devin.sessions      (data variant, loaded_at timestamp_ntz default current_timestamp());
create table if not exists raw.devin.audit_logs    (data variant, loaded_at timestamp_ntz default current_timestamp());
create table if not exists raw.devin.organizations (data variant, loaded_at timestamp_ntz default current_timestamp());
create table if not exists raw.devin.org_members   (data variant, loaded_at timestamp_ntz default current_timestamp());
create table if not exists raw.devin.roles         (data variant, loaded_at timestamp_ntz default current_timestamp());
```

`data` is one API record; `loaded_at` identifies the export it came from
(every row of one export must share the same `loaded_at`, which the column
default gives you when a file is loaded in a single `COPY`).

Minimal Snowflake load with the [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index):

```bash
devin-export sessions --updated-after 7d -o sessions.jsonl
snow stage copy sessions.jsonl @raw.devin.%sessions/
snow sql -q "copy into raw.devin.sessions (data) from @raw.devin.%sessions file_format = (type = json) purge = true"
```

Any other path works as long as the table shape matches: an Airflow task that
calls `devin_export.api.DevinClient` and `COPY`s from S3 (what AngelList runs),
Snowpipe on a bucket, a Python loader with `write_pandas`, etc. Different table
or column names are fine; point the package at them with the variables below.

## 3. Transform: the dbt package

```yaml
# packages.yml
packages:
  - git: "https://github.com/angellist/dbt_devin.git"
    revision: v0.1.0
```

```yaml
# dbt_project.yml
vars:
  devin_database: raw          # default: target.database
  devin_schema: devin          # default: devin
  # devin_loaded_at_column: airflow_loaded_at   # default: loaded_at
  # devin_sessions_identifier: devin_sessions   # per-table overrides, default: sessions, audit_logs, ...
  # devin__using_audit_logs: false              # disable feeds you do not land (sessions is required)
  # devin__include_session_title: true          # titles often echo prompts; off by default
```

Then `dbt deps && dbt build --select package:devin`.

### Models

| Model | Grain | Notes |
|---|---|---|
| `fct_devin_sessions` | one row per session | Latest capture per session; tags and PRs rolled up (`tag_list`, `pull_request_count`, `merged_pull_request_count`); `acus_consumed` is semi-additive (sum across sessions, never across loads). |
| `fct_devin_pull_requests` | one row per (session, PR URL) | Flattened from `sessions.pull_requests`, with GitHub owner/repo/number parsed from the URL so you can join to your own GitHub data. |
| `fct_devin_org_membership_changes` | one row per add/remove event | From the audit log; resolves org name, target user and role names from the other feeds when enabled. |
| `agg_devin_acu_daily` | one row per created date × org × user × origin | Daily rollup of `fct_devin_sessions` (sessions, ACUs, PRs); add `acu_cost_usd` by setting `devin_acu_cost_usd`. |
| `dim_devin_users` | one row per user | Current membership (orgs, roles) from the latest members snapshot plus session activity (`first_session_at`, `session_count_last_30d`, ...); removed seats keep a row with `is_current_member = false`. |
| `dim_devin_organizations` | one row per org | With `member_count` from the latest members snapshot. |
| `dim_devin_roles` | one row per role | Enterprise and org roles, with org name resolved. |
| `stg_devin__sessions`, `stg_devin__audit_logs`, `stg_devin__organizations`, `stg_devin__org_members`, `stg_devin__roles` | one row per record (deduped) | Typed columns out of the `data` VARIANT. `org_members` keeps every snapshot (`snapshot_at`). |

Staging models are views in `<target_schema>_devin_staging`; marts are tables
in `<target_schema>_devin`. Override with the usual `models: devin: ...` config.

### Example queries

ACUs and sessions per org per week:

```sql
select
    date_trunc('week', created_date) as created_week,
    org_id,
    sum(session_count) as sessions,
    sum(acus_consumed) as acus
from {{ ref('agg_devin_acu_daily') }}
group by 1, 2
order by 1, 2
```

Seats with no session in the last 30 days:

```sql
select user_email, user_full_name, role_names, last_session_at
from {{ ref('dim_devin_users') }}
where is_current_member and not is_active_last_30d
order by last_session_at nulls first
```

Pull-request merge rate by repo:

```sql
select
    github_repo_owner || '/' || github_repo_name as repo,
    count(distinct pr_url) as prs,
    count(distinct case when is_merged then pr_url end) as merged_prs
from {{ ref('fct_devin_pull_requests') }}
where github_repo_name is not null
group by 1
order by prs desc
```

Marts are plain full-refresh tables (no incremental logic); at Devin's volumes
(a few thousand sessions a day for a large enterprise) a full build takes
seconds, so there is nothing to tune.

### Variables

| Variable | Default | Purpose |
|---|---|---|
| `devin_database` | `target.database` | Database of the landing tables |
| `devin_schema` | `devin` | Schema of the landing tables |
| `devin_loaded_at_column` | `loaded_at` | Load-timestamp column name on the landing tables |
| `devin_<feed>_identifier` | `sessions`, `audit_logs`, `organizations`, `org_members`, `roles` | Landing table names |
| `devin__using_audit_logs`, `devin__using_organizations`, `devin__using_org_members`, `devin__using_roles` | `true` | Disable models and sources for feeds you do not land |
| `devin__include_session_title` | `false` | Add `session_title` to `fct_devin_sessions` |
| `devin__finished_statuses` | `["exit", "error"]` | Statuses treated as finished by `is_finished` / `finished_session_count`. Devin leaves most sessions `suspended`; add it to count those as done |
| `devin_acu_cost_usd` | unset | Your USD price per ACU; when set, adds `acu_cost_usd` to `agg_devin_acu_daily` |

## Warehouse support

Snowflake only. The staging layer relies on `VARIANT` path access,
`lateral flatten` and `qualify`. Contributions that route these through
`dbt_utils` cross-database macros are welcome.

## Requirements

- A Devin **Enterprise** plan and an API key for an enterprise service user
  with read access (sessions, audit logs, organizations, roles).
- dbt Core >= 1.10 or dbt Fusion, `dbt-snowflake`, and `dbt_utils` >= 1.0
  (installed automatically by `dbt deps`).
- Python >= 3.9 for `devin-export`.

## Contributing

```bash
pip install -e "./cli[dev]" && pytest cli && ruff check cli
DBT_PROFILES_DIR=.github dbt deps && dbt parse && sqlfluff lint models
```

CI runs the same (see `.github/workflows/ci.yml`). To exercise the models end
to end, create the landing tables from [section 2](#2-land-the-landing-contract)
in a dev schema, load a `devin-export` dump (or a few hand-written rows in the
same shape) and run `dbt build` with `devin_database` / `devin_schema` pointed
at it; there is no Devin sandbox, so the test data is whatever your own
enterprise exports.

Releases are git tags `vX.Y.Z` matching `version:` in `dbt_project.yml` and
`cli/pyproject.toml`, with notes in the GitHub release. Pin tags in
`packages.yml`; `main` may change between releases.

## License

Apache-2.0; see `LICENSE` and `NOTICE`. Copyright AngelList.

"Devin" is a trademark of Cognition AI, Inc., used here only to describe the
product this package reads data from. This project is independent and is not
affiliated with, sponsored by, or endorsed by Cognition AI.
