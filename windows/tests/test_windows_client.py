from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from tokei_windows import collector
from tokei_windows.bridge import Store, _format_number


class WindowsCollectorTests(unittest.TestCase):
    def test_keep_awake_uses_continuous_execution_state_flags(self) -> None:
        with patch("tokei_windows.bridge.os.name", "nt"), patch("ctypes.windll", create=True) as windll:
            windll.kernel32.SetThreadExecutionState.return_value = 0x80000000
            self.assertTrue(Store._set_keep_awake(True))
            windll.kernel32.SetThreadExecutionState.assert_called_once_with(0x80000001)

    def test_mutable_price_files_use_a_writable_user_copy_on_windows(self) -> None:
        if os.name != "nt":
            self.skipTest("Windows user data behavior")
        original_user_dir = collector._USER_DIR
        with tempfile.TemporaryDirectory() as temporary:
            try:
                collector._USER_DIR = temporary
                price_path = Path(collector._writable_path("pricing.json"))
                self.assertEqual(price_path.parent, Path(temporary))
                self.assertTrue(price_path.is_file())
                self.assertIsInstance(json.loads(price_path.read_text(encoding="utf-8")), dict)
            finally:
                collector._USER_DIR = original_user_dir

    def test_windows_project_process_discovery_has_a_safe_empty_result(self) -> None:
        # The helper should return a list even when no supported CLI server is running.
        projects = collector.build_projects(refresh=False)
        self.assertIsInstance(projects, list)


class DashboardPresentationTests(unittest.TestCase):
    def test_cards_mark_expired_quota_values(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                "claude": {
                    "ranges": {"today": {"in": 1200, "cost": 0.18}},
                    "q5": 38.0,
                    "q5_stale": True,
                }
            },
            _settings={"card_period": "today"},
        )
        cards = Store._build_cards(state)
        claude = next(card for card in cards if card["key"] == "claude")
        self.assertEqual(claude["quotas"][0]["label"], "5 小时")
        self.assertTrue(claude["quotas"][0]["stale"])
        self.assertEqual(claude["metrics"][0]["value"], "1,200")

    def test_tray_summary_is_short_and_includes_today_usage(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                "claude": {"ranges": {"today": {"in": 1000, "out": 250, "cost": 1.25}}},
                "codex": {"ranges": {"today": {"in": 500, "cost": 0.5}}, "p5": 42, "pw": 67},
            },
            _last_updated="2026-09-25 19:00:00",
        )
        summary = Store._make_summary(state)
        self.assertLessEqual(len(summary), 127)
        self.assertIn("1,750 Token", summary)
        self.assertIn("$1.75", summary)
        self.assertIn("5h", summary)

    def test_number_format_is_readable_at_a_glance(self) -> None:
        self.assertEqual(_format_number(1_250_000), "1.2M")
        self.assertEqual(_format_number(24_500), "24.5K")
        self.assertEqual(_format_number(1234), "1,234")


if __name__ == "__main__":
    unittest.main()
