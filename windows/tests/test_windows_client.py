from __future__ import annotations

import json
import os
import struct
import tempfile
import time
import unittest
from contextlib import contextmanager
from datetime import datetime
from email.utils import formatdate
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from tokei_windows import collector
from tokei_windows.bridge import (
    Store,
    _RefreshJob,
    _format_integer,
    _format_number,
    _normalize_refresh_seconds,
    _qml_safe,
    _top_tools,
)
from tokei_windows.main import _centered_window_geometry, _floating_widget_geometry


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
        large_total = 12345678901234567890
        daily = {
            "daily": [{"date": "2026-09-24", "tokens": large_total, "claude": 1.25, "codex": 0.75}],
            "models": [{"name": "large-model", "tokens": large_total}],
        }
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
        self.assertEqual(result["dashboard"]["daily"][0]["date_label"], "09-24")
        self.assertEqual(result["dashboard"]["daily"][0]["tokens_display"], "12,345,678,901,234,567,890")
        self.assertEqual(result["dashboard"]["models"][0]["tokens_display"], "12,345,678,901,234,567,890")

    def test_windows_project_process_discovery_has_a_safe_empty_result(self) -> None:
        # The helper should return a list even when no supported CLI server is running.
        projects = collector.build_projects(refresh=False)
        self.assertIsInstance(projects, list)


_ORG = "b9351e35-0000-4000-8000-000000000000"


def _cache_addr(file_type: int, file_number: int, start: int, blocks: int) -> int:
    return 0x80000000 | (file_type << 28) | ((blocks - 1) << 24) | (file_number << 16) | start


class _BlockfileCache:
    """Minimal Chromium blockfile cache: EntryStore + bodies in data_1, headers in data_2."""

    def __init__(self, root: str) -> None:
        self.root = Path(root)
        self.block_sizes = {1: 256, 2: 1024}
        self.blocks: dict[int, dict[int, bytes]] = {1: {}, 2: {}}
        self.allocated: dict[int, set[int]] = {1: set(), 2: set()}
        self.next_block = {1: 0, 2: 0}

    def _store(self, file_number: int, payload: bytes, allocated: bool = True) -> tuple[int, int]:
        count = max(1, -(-len(payload) // self.block_sizes[file_number]))
        start = self.next_block[file_number]
        self.next_block[file_number] += count
        self.blocks[file_number][start] = payload
        if allocated:
            self.allocated[file_number].update(range(start, start + count))
        return start, count

    def add_usage(self, query: str, fetched: int, payload: dict, allocated: bool = True) -> None:
        import zstandard

        key = f"1/0/https://claude.ai/api/organizations/{_ORG}/usage{query}".encode()
        raw_headers = (f"HTTP/1.1 200\0date: {formatdate(fetched, usegmt=True)}\0"
                       "content-type: application/json\0content-encoding: zstd\0\0").encode()
        head = struct.pack("<IIi3qi", 0, 0x80000003, 6, 0, 0, 0, len(raw_headers)) + raw_headers
        body = zstandard.ZstdCompressor().compress(json.dumps(payload).encode())
        head_start, head_blocks = self._store(2, head)
        body_start, body_blocks = self._store(1, body)
        entry = bytearray(256)
        struct.pack_into("<i", entry, 32, len(key))
        struct.pack_into("<4i", entry, 40, len(head), len(body), 0, 0)
        struct.pack_into("<4I", entry, 56, _cache_addr(3, 2, head_start, head_blocks),
                         _cache_addr(2, 1, body_start, body_blocks), 0, 0)
        entry[96:96 + len(key)] = key
        self._store(1, bytes(entry), allocated)

    def write(self) -> None:
        (self.root / "index").write_bytes(bytes(368))
        (self.root / "data_0").write_bytes(self._header(0, 36, set()))
        for number, block_size in self.block_sizes.items():
            content = bytearray(self._header(number, block_size, self.allocated[number]))
            content.extend(bytes(self.next_block[number] * block_size))
            for start, payload in self.blocks[number].items():
                offset = 8192 + start * block_size
                content[offset:offset + len(payload)] = payload
            (self.root / f"data_{number}").write_bytes(bytes(content))

    @staticmethod
    def _header(number: int, block_size: int, allocated: set[int]) -> bytes:
        header = bytearray(8192)
        struct.pack_into("<IIhhi", header, 0, 0xC104CAC3, 0x30000, number, 0, block_size)
        for block in allocated:
            header[80 + block // 8] |= 1 << (block % 8)
        return bytes(header)


@contextmanager
def _held_like_chromium(path: Path):
    """Chromium keeps cache files open with DELETE access, so plain open() gets a sharing violation."""
    if os.name != "nt":
        yield
        return
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateFileW.restype = wintypes.HANDLE
    kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
                                     wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    handle = kernel32.CreateFileW(str(path), 0x80000000 | 0x40000000 | 0x00010000, 0x7, None, 3, 0, None)
    try:
        yield
    finally:
        kernel32.CloseHandle(handle)


def _usage_payload(five_hour: float, seven_day: float) -> dict:
    return {
        "five_hour": {"utilization": five_hour, "resets_at": "2026-09-27T23:40:00.447364+00:00"},
        "seven_day": {"utilization": seven_day, "resets_at": "2026-10-01T06:00:00.447402+00:00"},
        "limits": [{"kind": "session", "percent": five_hour}],
    }


class ClaudeChannelClassificationTests(unittest.TestCase):
    @staticmethod
    def _line(mid, request_id, model):
        record = {"type": "assistant", "timestamp": "2026-09-28T01:00:00Z",
                  "message": {"id": mid, "model": model,
                              "usage": {"input_tokens": 10, "output_tokens": 2}}}
        if request_id is not None:
            record["requestId"] = request_id
        return json.dumps(record)

    def test_only_full_official_signature_is_official(self) -> None:
        official = collector._claude_usage(
            self._line("msg_01XYZ", "req_01ABC", "claude-opus-5-5"), want_dt=True)
        relay = collector._claude_usage(
            self._line("9749d2b1c0", None, "deepseek-v4.1-flash"), want_dt=True)
        missing_request_id = collector._claude_usage(
            self._line("msg_01HALF", None, "claude-opus-5-5"), want_dt=True)
        relayed_claude = collector._claude_usage(
            self._line("msg_01RELAY", "req_01RELAY", "deepseek-v4.1-flash"), want_dt=True)
        self.assertIs(official["official"], True)
        self.assertIs(relay["official"], False)
        self.assertIs(missing_request_id["official"], False)
        self.assertIs(relayed_claude["official"], False)


class _ClaudeChannelFixture(unittest.TestCase):
    """T2/T3 共用夹具:临时 CLAUDE_DIR + 临时扫描缓存/账本,外加造记录的小工具。"""

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.sessions = self.root / "projects"
        self.sessions.mkdir()
        self.ledger_path = self.root / "ledger.json"
        for name, value in (("CLAUDE_DIR", str(self.sessions)),
                            ("_SCAN_CACHE_FILE", str(self.root / "scan.json")),
                            ("_LEDGER_FILE", str(self.ledger_path))):
            patcher = patch.object(collector, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        # 缺文件的账本会自愈:从同步快照里把真机账本捞回(见 _load_ledger_from_disk)。
        # 一旦配置了 device_id + sync_dir,真机历史就会进夹具,必须把配置读空。
        patcher = patch.object(collector, "_load_tokei_config", lambda: {})
        patcher.start()
        self.addCleanup(patcher.stop)
        self._reset_ledger_cache()
        self.addCleanup(self._reset_ledger_cache)

    @staticmethod
    def _reset_ledger_cache() -> None:
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})

    def _write(self, name: str, records: list[dict]) -> None:
        project = self.sessions / "E--proj"
        project.mkdir(exist_ok=True)
        (project / name).write_text(
            "\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n",
            encoding="utf-8")

    @staticmethod
    def _assistant(inp, out, mid="msg_01XYZ", request_id="req_01ABC",
                   model="claude-opus-5-5") -> dict:
        record = {"type": "assistant", "cwd": "E:\\proj",
                  "timestamp": datetime.now().astimezone().isoformat(),
                  "message": {"id": mid, "model": model,
                              "usage": {"input_tokens": inp, "output_tokens": out}}}
        if request_id is not None:
            record["requestId"] = request_id
        return record


class ClaudeChannelScanTests(_ClaudeChannelFixture):
    def test_scan_splits_channel_tokens_and_cache_namespaces(self) -> None:
        self._write("desktop.jsonl", [self._assistant(100, 50)])
        self._write("relay.jsonl", [self._assistant(10, 5, mid="9749d2b1c0",
                                                    request_id=None,
                                                    model="deepseek-v4.1-flash")])
        cache = collector._load_scan_cache()
        result = collector.scan_claude(collector.range_bounds(), cache)
        today, desktop = result["ranges"]["today"], result["desktop_ranges"]["today"]
        self.assertEqual((today["in"], today["out"]), (10, 5))
        self.assertEqual((desktop["in"], desktop["out"]), (100, 50))
        api_events = [event for entry in cache["claude"].values()
                      for event in entry.get("events") or []]
        desktop_events = [event for entry in cache["claude_desktop"].values()
                          for event in entry.get("events") or []]
        self.assertEqual([event["model"] for event in api_events], ["deepseek-v4.1-flash"])
        self.assertEqual([event["model"] for event in desktop_events], ["claude-opus-5-5"])
        self.assertNotIn("relay.jsonl",
                         {os.path.basename(p) for p in cache["claude_desktop"]})
        self.assertNotIn("desktop.jsonl",
                         {os.path.basename(p) for p in cache["claude"]})
        # cur / desktop_cur 只服务 collector 的命令行输出(界面不读),这里只查结构
        self.assertEqual(sorted(result["desktop_cur"]), ["cr", "cw", "in", "name", "out"])

    def test_steady_state_scan_does_not_reparse(self) -> None:
        self._write("relay.jsonl", [self._assistant(10, 5, mid="9749d2b1c0",
                                                    request_id=None,
                                                    model="deepseek-v4.1-flash")])
        self._write("empty.jsonl", [])   # 两个渠道都没事件的文件同样不能再被重读
        cache = collector._load_scan_cache()
        collector.scan_claude(collector.range_bounds(), cache)
        cache["_dirty"] = False
        collector.scan_claude(collector.range_bounds(), cache)
        self.assertFalse(cache.get("_dirty"))
        self.assertNotIn("empty.jsonl", {os.path.basename(p) for p in cache["claude"]})
        self.assertNotIn("empty.jsonl", {os.path.basename(p) for p in cache["claude_desktop"]})


class ClaudeLedgerSplitMigrationTests(_ClaudeChannelFixture):
    def setUp(self) -> None:
        super().setUp()
        self.day = datetime.now().astimezone().date().isoformat()

    def _seed_mixed_ledger(self, desktop_in: int, relay_in: int) -> None:
        """旧版账本:claude 的一天里混着中继与官方,且带按文件来源。"""
        mixed = {"in": desktop_in + relay_in, "out": 0, "cr": 0, "cw": 0, "cost": 1.0,
                 "models": {"claude-opus-5-5": {"in": desktop_in, "out": 0, "cr": 0,
                                                "cw": 0, "cost": 1.0}},
                 "_sources": {"legacy.jsonl": {"in": desktop_in + relay_in, "out": 0,
                                               "cr": 0, "cw": 0, "cost": 1.0}}}
        self.ledger_path.write_text(json.dumps({"v": 1, "tools": {"claude": {self.day: mixed}}}),
                                    encoding="utf-8")
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})

    def _scan_and_flush(self) -> dict:
        cache = collector._load_scan_cache()
        collector.scan_claude(collector.range_bounds(), cache)
        collector.ledger_flush()
        return json.loads(self.ledger_path.read_text(encoding="utf-8"))

    def test_migration_moves_the_desktop_share_out_of_relay_ledger(self) -> None:
        self._seed_mixed_ledger(desktop_in=90, relay_in=10)
        self._write("desktop.jsonl", [self._assistant(90, 0)])
        self._write("relay.jsonl", [self._assistant(10, 0, mid="9749d2b1c0",
                                                    request_id=None,
                                                    model="deepseek-v4.1-flash")])
        stored = self._scan_and_flush()
        self.assertEqual(stored["claude_split"], 2)
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 90)

    def test_migration_runs_once(self) -> None:
        self._seed_mixed_ledger(desktop_in=90, relay_in=10)
        self._write("desktop.jsonl", [self._assistant(90, 0)])
        self._write("relay.jsonl", [self._assistant(10, 0, mid="9749d2b1c0",
                                                    request_id=None,
                                                    model="deepseek-v4.1-flash")])
        self._scan_and_flush()
        stored = self._scan_and_flush()
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 90)

    def test_flush_of_a_stale_memo_does_not_resurrect_the_split(self) -> None:
        """迁移前就载入账本的另一个进程(tray),其 flush 不能按旧来源把官方份额加回来。"""
        desktop_days = {self.day: {"in": 90, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        self._seed_mixed_ledger(desktop_in=90, relay_in=10)
        stale_memo = collector._load_ledger()        # 另一个进程:迁移前载入的内存账本
        stale_memo["tools"]["claude_desktop"] = dict(desktop_days)   # 它自己已对账出的官方天
        collector._migrate_claude_ledger_split(desktop_days)
        collector._LEDGER_CACHE.update({"data": stale_memo, "dirty": True})  # 它随后落盘
        collector.ledger_flush()
        stored = json.loads(self.ledger_path.read_text(encoding="utf-8"))
        self.assertEqual(stored["claude_split"], 2)
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 90)

    def test_fresh_ledger_still_gets_the_migration_marker(self) -> None:
        """全新装机(无账本文件)也必须落标记,否则下一轮会把官方份额从中继天里错减掉。"""
        desktop_days = {self.day: {"in": 90, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        with patch.object(collector, "_load_tokei_config", lambda: {}):
            self.assertFalse(self.ledger_path.exists())
            self.assertFalse(collector._migrate_claude_ledger_split({}))
            self.assertFalse(self.ledger_path.exists())     # 空 desktop_days:早退,不写盘
            self.assertTrue(collector._migrate_claude_ledger_split(desktop_days))
        stored = json.loads(self.ledger_path.read_text(encoding="utf-8"))
        self.assertEqual(stored["claude_split"], 2)
        self.assertEqual(stored["tools"]["claude"], {})     # 没有存量天可减

    def test_unreadable_ledger_is_neither_migrated_nor_overwritten(self) -> None:
        """账本在、但读不出来:不迁移、不落标记、不覆盖,下一轮再试。"""
        desktop_days = {self.day: {"in": 90, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        corrupt = '{"v": 1, "tools": {"claude": {'
        self.ledger_path.write_text(corrupt, encoding="utf-8")
        with patch.object(collector, "_load_tokei_config", lambda: {}):
            self.assertFalse(collector._migrate_claude_ledger_split(desktop_days))
        self.assertEqual(self.ledger_path.read_text(encoding="utf-8"), corrupt)


class ClaudeQuotaChannelTests(unittest.TestCase):
    def test_quota_reading_prefers_desktop_key_and_falls_back_for_legacy_peers(self) -> None:
        desktop = {"claude_desktop": {"q7": 12.0, "q7_reset": 2_000_000_000, "q_updated": 7}}
        self.assertEqual(collector._quota_tool_reading(desktop, "claude_desktop")[:2],
                         (12.0, 2_000_000_000))
        legacy = {"claude": {"q7": 9.0, "q7_reset": 2_000_000_000, "q_updated": 7}}
        self.assertEqual(collector._quota_tool_reading(legacy, "claude_desktop")[:2],
                         (9.0, 2_000_000_000))
        stale = {"claude_desktop": {"q7": 9.0, "q7_reset": 2_000_000_000, "q7_stale": True}}
        self.assertIsNone(collector._quota_tool_reading(stale, "claude_desktop"))

    def test_legacy_anchor_tool_key_is_renamed_once(self) -> None:
        anchors = {"claude": [{"reset": 123, "max_used": 5}], "codex": [{"reset": 9}]}
        self.assertTrue(collector._rename_legacy_quota_anchors(anchors))
        self.assertEqual(anchors["claude_desktop"], [{"reset": 123, "max_used": 5}])
        self.assertNotIn("claude", anchors)
        self.assertIn("codex", anchors)
        self.assertFalse(collector._rename_legacy_quota_anchors(anchors))

    def test_quota_window_counts_only_official_events(self) -> None:
        now = int(time.time())
        relay = {"timestamp": datetime.fromtimestamp(now - 60).astimezone().isoformat(),
                 "in": 1000, "out": 0, "cr": 0, "cw": 0}
        official = {"timestamp": datetime.fromtimestamp(now - 60).astimezone().isoformat(),
                    "in": 40, "out": 2, "cr": 3, "cw": 5}
        cache = {"claude": {"relay.jsonl": {"events": [relay]}},
                 "claude_desktop": {"desktop.jsonl": {"events": [official]}}}
        amounts = [amount for _ts, _day, amount
                   in collector._quota_claude_events(cache, "claude_desktop")]
        self.assertEqual(amounts, [50])

    def test_only_the_desktop_ledger_feeds_the_claude_cycle(self) -> None:
        """T4 之前的 peer 账本日表是混合口径(中继+官方),归不到任何渠道 → 一律不计。"""
        day = {"2026-09-27": {"in": 100, "out": 5, "cr": 0, "cw": 0, "cost": 1.0}}
        self.assertEqual(collector._quota_daily_from_tools({"claude": day}), {})
        self.assertEqual(collector._quota_daily_from_tools({"claude_desktop": day}),
                         {"2026-09-27": {"cd": 105, "x": 0, "g": 0}})


class ClaudeChannelPagesTests(unittest.TestCase):
    day = "2026-09-27"

    def setUp(self) -> None:
        # 页面聚合会读账本兜底;测试要把账本指到空文件,否则会掺进真机历史数据。
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        patcher = patch.object(collector, "_LEDGER_FILE",
                               str(Path(temporary.name) / "ledger.json"))
        patcher.start()
        self.addCleanup(patcher.stop)
        # 缺文件的账本会自愈:从同步快照里把真机账本捞回来(见 _load_ledger_from_disk)。
        # 一旦配置了 device_id + sync_dir,真机历史就会 max 进夹具,必须把配置读空。
        patcher = patch.object(collector, "_load_tokei_config", lambda: {})
        patcher.start()
        self.addCleanup(patcher.stop)
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})
        self.addCleanup(lambda: collector._LEDGER_CACHE.update({"data": None, "dirty": False}))

    def _cache(self) -> dict:
        return {
            "claude": {"relay.jsonl": {
                "days": {self.day: {"in": 10, "out": 1, "cr": 2, "cw": 0, "cost": 0.5,
                                    "models": {"deepseek-v4.1-flash": {"in": 10, "out": 1,
                                                                       "cr": 2, "cw": 0,
                                                                       "cost": 0.5}}}}}},
            "claude_desktop": {"desktop.jsonl": {
                "proj": "E:\\tokei-windows",
                "days": {self.day: {"in": 90, "out": 3, "cr": 5, "cw": 0, "cost": 2.0,
                                    "models": {"claude-opus-5-5": {"in": 90, "out": 3,
                                                                   "cr": 5, "cw": 0,
                                                                   "cost": 2.0}}}}}},
        }

    def test_daily_costs_split_the_two_claude_channels(self) -> None:
        result = collector.build_daily_costs("all", refresh=False, _cache=self._cache())
        row = next(point for point in result["daily"] if point["date"] == self.day)
        self.assertEqual(row["claude"], 0.5)
        self.assertEqual(row["claude_desktop"], 2.0)
        self.assertEqual((row["c_in"], row["cd_in"]), (10, 90))
        self.assertEqual((row["cd_out"], row["cd_cr"], row["cd_cw"]), (3, 5, 0))
        self.assertAlmostEqual(row["total"], 2.5, places=2)
        names = {model["name"] for model in result["models"]}
        # nice_model("claude-opus-5-5") == "Opus 5.5";中继模型名保持原样
        self.assertIn("Opus 5.5 (Claude Desktop)", names)
        self.assertIn("Deepseek V4.1 Flash", names)
        by_name = {model["name"]: model for model in result["models"]}
        self.assertEqual(by_name["Opus 5.5 (Claude Desktop)"]["tool"], "claude_desktop")
        self.assertEqual(by_name["Deepseek V4.1 Flash"]["tool"], "claude")

    def test_desktop_ledger_cost_column_is_merged_as_high_water(self) -> None:
        ledger = {"v": 1, "tools": {"claude_desktop": {
            self.day: {"in": 90, "out": 3, "cr": 5, "cw": 0, "cost": 9.5, "models": {}}}}}
        with open(collector._LEDGER_FILE, "w", encoding="utf-8") as fh:
            json.dump(ledger, fh)
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})
        result = collector.build_daily_costs("all", refresh=False, _cache=self._cache())
        row = next(point for point in result["daily"] if point["date"] == self.day)
        # 账本是同一份数据的高水位存档:9.5 > 实时 2.0,取 max 而不是相加。
        self.assertEqual(row["claude_desktop"], 9.5)
        # 账本 token(98)不高于实时(98),token 列保持实时口径。
        self.assertEqual(row["cd_in"], 90)
        self.assertEqual(row["tokens"], 111)

    def test_project_footprint_includes_the_desktop_channel(self) -> None:
        rows = list(collector._project_contributions(self._cache()))
        desktop_rows = [row for row in rows if row["tool"] == "claude_desktop"]
        self.assertEqual(len(desktop_rows), 1)
        self.assertEqual(desktop_rows[0]["tokens"], 98)
        self.assertEqual(desktop_rows[0]["label"], "Claude Code Desktop")

    def test_yearly_review_totals_include_the_desktop_channel(self) -> None:
        wrapped = collector.build_wrapped("all", refresh=False, _cache=self._cache())
        self.assertEqual(wrapped["total_tokens"], 111)


class ClaudeDesktopCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        try:
            import zstandard  # noqa: F401
        except ImportError:
            self.skipTest("zstandard is required to build the cached /usage body")
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.cache_dir = Path(temporary.name) / "Cache_Data"
        self.cache_dir.mkdir()
        environment = patch.dict(os.environ, {"TOKEI_CLAUDE_CACHE_DIR": str(self.cache_dir)})
        environment.start()
        self.addCleanup(environment.stop)
        os.environ.pop("TOKEI_CLAUDE_QUOTA_JSON", None)
        for name, value in (("CLAUDE_CACHE", str(self.cache_dir)),
                            ("CLAUDE_CACHE_DIRS", [str(self.cache_dir)]),
                            ("CLAUDE_QUOTA_CACHE", str(Path(temporary.name) / "claude_quota_cache.json"))):
            patcher = patch.object(collector, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_quota_comes_from_newest_live_usage_entry_in_windows_blockfile_cache(self) -> None:
        now = int(time.time())
        cache = _BlockfileCache(str(self.cache_dir))
        cache.add_usage("", now - 600, _usage_payload(5.0, 1.0))
        cache.add_usage("?skip_spend=1", now - 60, _usage_payload(10.0, 2.0))
        cache.add_usage("?cedar_ember=1&skip_spend=1", now - 30, _usage_payload(99.0, 99.0), allocated=False)
        cache.write()

        with _held_like_chromium(self.cache_dir / "data_1"):
            if os.name == "nt":
                with self.assertRaises(PermissionError):
                    open(self.cache_dir / "data_1", "rb").close()
            plan = collector.scan_claude_plan()

        self.assertEqual(plan.get("q5"), 10.0)
        self.assertEqual(plan.get("q7"), 2.0)
        self.assertEqual(plan.get("q5_reset"), collector._iso_to_epoch("2026-09-27T23:40:00.447364+00:00"))
        self.assertEqual(plan.get("q_updated"), now - 60)

    def test_last_blockfile_snapshot_survives_a_missing_usage_entry(self) -> None:
        now = int(time.time())
        cache = _BlockfileCache(str(self.cache_dir))
        cache.add_usage("?skip_spend=1", now - 60, _usage_payload(10.0, 2.0))
        cache.write()
        self.assertEqual(collector.scan_claude_plan().get("q5"), 10.0)

        _BlockfileCache(str(self.cache_dir)).write()
        plan = collector.scan_claude_plan()
        self.assertEqual(plan.get("q5"), 10.0)
        self.assertEqual(plan.get("q_updated"), now - 60)


class DashboardPresentationTests(unittest.TestCase):
    def test_desktop_card_marks_expired_quota_values(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                "claude_desktop": {
                    "ranges": {"today": {"in": 1200, "cost": 0.18}},
                    "q5": 38.0,
                    "q5_stale": True,
                }
            },
            _settings={"card_period": "today"},
        )
        cards = Store._build_cards(state)
        claude = next(card for card in cards if card["key"] == "claude_desktop")
        self.assertEqual(claude["quotas"][0]["label"], "5 小时")
        self.assertTrue(claude["quotas"][0]["stale"])
        self.assertEqual(claude["metrics"][0]["value"], "1,200")

    def test_claude_quota_values_are_used_percentages(self) -> None:
        state = SimpleNamespace(
            _snapshot={"claude_desktop": {"ranges": {"today": {}}, "q5": 10.0, "q7": 2.0, "qf": 40.0}},
            _settings={"card_period": "today"},
        )
        cards = Store._build_cards(state)
        claude = next(card for card in cards if card["key"] == "claude_desktop")
        self.assertEqual(
            [(quota["label"], quota["used"], quota["remaining"]) for quota in claude["quotas"]],
            [("5 小时", 10.0, 90.0), ("周额度", 2.0, 98.0), ("Fable 周", 40.0, 60.0)],
        )

    def test_only_the_desktop_card_carries_subscription_bars(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                # 中继卡即使带 q5/q7 也必须忽略:订阅额度只挂官方桌面通道。
                "claude": {"ranges": {"today": {"in": 1000, "out": 500, "cost": 0.12}},
                           "q5": 20.0, "q7": 3.0},
                "claude_desktop": {"ranges": {"today": {"in": 2000, "out": 100, "cost": 0.30}},
                                   "q5": 20.0, "q7": 3.0},
            },
            _settings={"card_period": "today"},
        )
        cards = {card["key"]: card for card in Store._build_cards(state)}
        self.assertEqual(cards["claude"]["quotas"], [])
        self.assertEqual(cards["claude"]["title"], "Claude Code")
        self.assertEqual(cards["claude"]["total_tokens"], 1500)
        self.assertEqual(cards["claude_desktop"]["title"], "Claude Code Desktop")
        self.assertEqual(cards["claude_desktop"]["total_tokens"], 2100)
        self.assertEqual([quota["remaining"] for quota in cards["claude_desktop"]["quotas"]],
                         [80.0, 97.0])

    def test_cards_sum_token_fields_for_selected_period(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                "claude": {
                    "ranges": {
                        "today": {"in": 3, "out": 5},
                        "week": {"in": 12345678901234567890, "out": 10, "cached": 20, "reason": 30},
                    },
                },
            },
            _settings={"card_period": "week"},
        )
        cards = Store._build_cards(state)
        claude = next(card for card in cards if card["key"] == "claude")
        self.assertEqual(claude["total_tokens"], 12345678901234567950)
        self.assertEqual(claude["total_tokens_display"], "12,345,678,901,234,567,950")

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

    def test_large_integer_format_does_not_use_scientific_notation(self) -> None:
        self.assertEqual(_format_integer("1.234567890123456789e19"), "12,345,678,901,234,567,890")
        self.assertEqual(_qml_safe({"tokens": 12345678901234567890}), {"tokens": "12345678901234567890"})

    def test_floating_widget_ranks_only_tools_with_token_data(self) -> None:
        snapshot = {
            "claude": {"ranges": {"today": {"in": 100, "out": 50}}},
            "codex": {"ranges": {"today": {"in": 900}}},
            "gemini": {"ranges": {"today": {"in": 300}}},
            "cursor": {"ranges": {"today": {"in": 0}}},
        }
        tools = _top_tools(snapshot)
        self.assertEqual([tool["key"] for tool in tools], ["codex", "gemini", "claude"])
        self.assertEqual(tools[0]["tokens_display"], "900")

    def test_refresh_interval_defaults_to_one_minute_and_is_bounded(self) -> None:
        self.assertEqual(_normalize_refresh_seconds(None), 60)
        self.assertEqual(_normalize_refresh_seconds(30), 60)
        self.assertEqual(_normalize_refresh_seconds(120), 120)
        self.assertEqual(_normalize_refresh_seconds(900), 300)


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

    def test_floating_widget_starts_inside_the_available_screen_area(self) -> None:
        self.assertEqual(
            _floating_widget_geometry((-1920, 0, 1920, 1080)),
            (-384, 24, 360, 224),
        )
        self.assertEqual(
            _floating_widget_geometry((0, 0, 280, 160)),
            (24, 24, 232, 112),
        )


if __name__ == "__main__":
    unittest.main()
