# devin-export

Command-line extractor for the [Devin Enterprise API](https://docs.devin.ai/enterprise/api). It emits raw
JSON (one object per line by default) that you land in your warehouse as `(data VARIANT, loaded_at TIMESTAMP)`
tables for the `devin` dbt package in the repository root.

```bash
pip install ./cli
export DEVIN_ENTERPRISE_API_KEY=...

devin-export sessions --updated-after 7d > sessions.jsonl
devin-export audit-logs --time-after 36h --time-before now > audit_logs.jsonl
devin-export organizations > organizations.jsonl
devin-export members > org_members.jsonl
devin-export roles > roles.jsonl
```

See the root `README.md` for the landing-table contract and scheduling guidance.

## Development

```bash
pip install -e "./cli[dev]"
ruff check cli && ruff format --check cli
pytest cli
```
