from __future__ import annotations

import importlib.util
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest


TOOL_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "bc_ai_knowledge_metrics", TOOL_ROOT / "Read-CopilotMetrics.py"
)
assert SPEC and SPEC.loader
METRICS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(METRICS)


class MetricsAdapterTests(unittest.TestCase):
    def test_missing_database_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = METRICS.snapshot(Path(directory) / "missing.db")
        self.assertEqual("unavailable", result["status"])

    def test_collects_only_matching_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            workspace.mkdir()
            database = root / "session-store.db"
            with closing(sqlite3.connect(database)) as connection:
                connection.executescript(
                    """
                    CREATE TABLE schema_version (version INTEGER);
                    INSERT INTO schema_version VALUES (8);
                    CREATE TABLE sessions (id TEXT, cwd TEXT);
                    CREATE TABLE assistant_usage_events (
                        id INTEGER, session_id TEXT, input_tokens INTEGER,
                        output_tokens INTEGER, cache_read_tokens INTEGER,
                        cache_write_tokens INTEGER, reasoning_tokens INTEGER,
                        total_nano_aiu INTEGER, request_multiplier REAL,
                        duration_ms INTEGER
                    );
                    CREATE TABLE forge_trajectory_events (session_id TEXT, event_type TEXT);
                    """
                )
                connection.executemany(
                    "INSERT INTO sessions VALUES (?, ?)",
                    [("target", str(workspace)), ("other", str(root / "other"))],
                )
                connection.executemany(
                    "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        (11, "target", 100, 20, 5, 2, 3, 40, 1.0, 500),
                        (12, "target", 10, 4, 1, 0, 1, 8, 0.5, 100),
                        (13, "other", 999, 999, 0, 0, 0, 0, 1.0, 1000),
                    ],
                )
                connection.execute("INSERT INTO forge_trajectory_events VALUES ('target', 'tool_call')")
                connection.commit()

            result = METRICS.collect(database, 10, str(workspace))

        self.assertEqual("measured", result["status"])
        self.assertEqual(["target"], result["session_ids"])
        self.assertEqual(110, result["input_tokens"])
        self.assertEqual(24, result["output_tokens"])
        self.assertEqual(48, result["total_nano_aiu"])
        self.assertEqual(1, result["tool_activity"]["tool_call"])


if __name__ == "__main__":
    unittest.main()