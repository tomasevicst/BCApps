"""Read aggregate GitHub Copilot CLI usage metrics without session content."""

from __future__ import annotations

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
from typing import Any


ADAPTER_VERSION = "1.0"
USAGE_COLUMNS = {
    "id",
    "session_id",
    "input_tokens",
    "output_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "reasoning_tokens",
    "total_nano_aiu",
    "request_multiplier",
    "duration_ms",
}


def unavailable(reason: str, max_usage_event_id: int = 0) -> dict[str, Any]:
    return {
        "adapter_version": ADAPTER_VERSION,
        "status": "unavailable",
        "reason": reason,
        "max_usage_event_id": max_usage_event_id,
    }


def normalize_path(value: str) -> str:
    return os.path.normcase(os.path.normpath(os.path.abspath(value)))


def open_database(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)


def table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')}


def validate_schema(connection: sqlite3.Connection) -> tuple[bool, str, int | None]:
    tables = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }
    if not {"assistant_usage_events", "sessions"}.issubset(tables):
        return False, "Required Copilot CLI tables are absent.", None
    missing_usage = USAGE_COLUMNS - table_columns(connection, "assistant_usage_events")
    missing_sessions = {"id", "cwd"} - table_columns(connection, "sessions")
    if missing_usage or missing_sessions:
        missing = sorted(missing_usage | missing_sessions)
        return False, f"Required Copilot CLI columns are absent: {', '.join(missing)}", None
    schema_version = None
    if "schema_version" in tables:
        row = connection.execute("SELECT MAX(version) FROM schema_version").fetchone()
        schema_version = row[0] if row else None
    return True, "", schema_version


def snapshot(database: Path) -> dict[str, Any]:
    if not database.is_file():
        return unavailable(f"Copilot CLI session store does not exist: {database}")
    try:
        with closing(open_database(database)) as connection:
            valid, reason, schema_version = validate_schema(connection)
            if not valid:
                return unavailable(reason)
            row = connection.execute("SELECT COALESCE(MAX(id), 0) FROM assistant_usage_events").fetchone()
            return {
                "adapter_version": ADAPTER_VERSION,
                "status": "measured",
                "reason": None,
                "database_schema_version": schema_version,
                "max_usage_event_id": int(row[0]),
            }
    except (OSError, sqlite3.Error) as error:
        return unavailable(f"Cannot read Copilot CLI session store: {type(error).__name__}")


def collect(database: Path, since_id: int, workspace: str) -> dict[str, Any]:
    initial = snapshot(database)
    if initial["status"] == "unavailable":
        initial["max_usage_event_id"] = since_id
        return initial

    target = normalize_path(workspace)
    try:
        with closing(open_database(database)) as connection:
            rows = connection.execute(
                """
                SELECT a.id, a.session_id, s.cwd, a.input_tokens, a.output_tokens,
                       a.cache_read_tokens, a.cache_write_tokens, a.reasoning_tokens,
                       a.total_nano_aiu, a.request_multiplier, a.duration_ms
                FROM assistant_usage_events AS a
                JOIN sessions AS s ON s.id = a.session_id
                WHERE a.id > ?
                ORDER BY a.id
                """,
                (since_id,),
            ).fetchall()
            matching = [row for row in rows if row[2] and normalize_path(row[2]) == target]
            if not matching:
                result = unavailable("No uniquely attributable usage events were found.", initial["max_usage_event_id"])
                result["database_schema_version"] = initial.get("database_schema_version")
                return result

            session_ids = sorted({row[1] for row in matching})
            status = "measured" if len(session_ids) == 1 else "partial"
            activity: dict[str, int] = {}
            tables = {
                row[0]
                for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
            }
            if "forge_trajectory_events" in tables:
                placeholders = ",".join("?" for _ in session_ids)
                for event_type, count in connection.execute(
                    f"SELECT event_type, COUNT(*) FROM forge_trajectory_events WHERE session_id IN ({placeholders}) GROUP BY event_type",
                    session_ids,
                ):
                    activity[event_type or "unknown"] = count

            def total(index: int) -> int:
                return sum(int(row[index] or 0) for row in matching)

            return {
                "adapter_version": ADAPTER_VERSION,
                "status": status,
                "reason": None if status == "measured" else "Multiple new sessions matched the evaluation workspace.",
                "database_schema_version": initial.get("database_schema_version"),
                "max_usage_event_id": initial["max_usage_event_id"],
                "session_ids": session_ids,
                "usage_event_count": len(matching),
                "input_tokens": total(3),
                "output_tokens": total(4),
                "cache_read_tokens": total(5),
                "cache_write_tokens": total(6),
                "reasoning_tokens": total(7),
                "total_nano_aiu": total(8),
                "request_multiplier_sum": sum(float(row[9] or 0) for row in matching),
                "model_duration_ms": total(10),
                "tool_activity": activity,
            }
    except (OSError, sqlite3.Error) as error:
        return unavailable(f"Cannot collect Copilot CLI metrics: {type(error).__name__}", since_id)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("snapshot", "collect"))
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--since-id", type=int, default=0)
    parser.add_argument("--workspace")
    args = parser.parse_args()

    if args.mode == "snapshot":
        result = snapshot(args.database)
    elif not args.workspace:
        result = unavailable("--workspace is required for collect.", args.since_id)
    else:
        result = collect(args.database, args.since_id, args.workspace)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())