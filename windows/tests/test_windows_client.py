from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from tokei_windows import collector
from tokei_windows.bridge import Store, _RefreshJob, _format_number
from tokei_windows.main import _centered_window_geometry


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

    def test_ledger_flush_uses_windows_lock_without_fcntl(self) -> None:
        if os.name != "nt":
            self.skipTest("Windows file locking behavior")
        original_ledger_file = collector._LEDGER_FILE
        original_data = collector._LEDGER_CACHE["data"]
        original_dirty = collector._LEDGER_CACHE["dirty"]
        with tempfile.TemporaryDirectory() as temporary:
            try:
                collector._LEDGER_FILE = os.path.join(temporary, "ledger.json")
                collector._LEDGER_CACHE["data"] = {"v": collector._LEDGER_VERSION, "tools": {}}
                collector._LEDGER_CACHE["dirty"] = True
                with patch.object(collector, "_load_ledger_from_disk", return_value={
                    "v": collector._LEDGER_VERSION,
                    "tools": {},
                }), patch.object(collector, "_save_ledger") as save_ledger:
                    collector.ledger_flush()
                save_ledger.assert_called_once()
                self.assertFalse(collector._LEDGER_CACHE["dirty"])
                self.assertTrue(Path(f"{collector._LEDGER_FILE}.lock").is_file())
            finally:
                collector._LEDGER_FILE = original_ledger_file
                collector._LEDGER_CACHE["data"] = original_data
                collector._LEDGER_CACHE["dirty"] = original_dirty

    def test_refresh_job_builds_dashboard_with_cached_scan_results(self) -> None:
        job = _RefreshJob("request-1", "30d", False, False)
        events = []
        job.signals.completed.connect(lambda *args: events.append(args))
        usage = {"claude": {"ranges": {"today": {"in": 100}}}}
        daily = {"daily": [{"claude": 1.25, "codex": 0.75}]}
        cache = {"cached": True}

        with patch.object(collector, "compute", return_value=usage) as compute, \
                patch.object(collector, "_load_dashboard_cache", return_value=cache), \
                patch.object(collector, "build_daily_costs", return_value=daily) as build_daily_costs, \
                patch.object(collector, "build_wrapped", return_value={"ready": True}) as build_wrapped:
            job.run()

        compute.assert_called_once_with()
        build_daily_costs.assert_called_once_with("30d", refresh=False, _cache=cache)
        build_wrapped.assert_called_once_with("30d", refresh=False, _cache=cache)
        self.assertEqual(len(events), 1)
        request_id, result, error = events[0]
        self.assertEqual(request_id, "request-1")
        self.assertEqual(error, "")
        self.assertEqual(result["usage"], usage)
        self.assertEqual(result["dashboard"]["wrapped"], {"ready": True})
        self.assertEqual(result["dashboard"]["daily"][0]["total_cost"], 2.0)

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


class WindowGeometryTests(unittest.TestCase):
    def test_window_is_centered_on_monitor_with_negative_origin(self) -> None:
        self.assertEqual(
            _centered_window_geometry((-1920, 0, 1920, 1080)),
            (-1570, 130, 1220, 820),
        )

    def test_window_shrinks_to_fit_a_smaller_display(self) -> None:
        self.assertEqual(
            _centered_window_geometry((-800, 20, 800, 600)),
            (-800, 20, 800, 600),
        )


if __name__ == "__main__":
    unittest.main()
