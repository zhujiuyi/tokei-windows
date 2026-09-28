# Claude 卡片按客户端归属 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「Claude Code Desktop」卡片统计 Claude 桌面客户端的全部用量（含未登录时经第三方 API 的部分），同时让额度历史周期仍只统计官方通道。

**Architecture:** 扫描缓存与账本的命名空间从「计费渠道」维度换成「客户端」维度（键名不变：`claude` = 非桌面客户端，`claude_desktop` = 桌面客户端），新增第三个只服务订阅额度的派生命名空间 `claude_official`（官方通道事件）。分类在 `scan_claude` 一次解析后按 `entrypoint` 分三组，其余按命名空间的通用通路（live 聚合 / 账本对账 / 桶写入）不变。账本做一次 `claude_split: 2 → 3` 迁移，把桌面客户端的第三方份额从 `claude` 挪走。

**Tech Stack:** Python 3.13（`windows/.venv`）、unittest、PySide6/QML（本次不改界面层）。

**Spec:** `docs/superpowers/specs/2026-09-29-claude-client-attribution-design.md`

## Global Constraints

- 只改 `windows/tokei_windows/collector.py` 与 `windows/tests/test_windows_client.py`；`bridge.py`、`qml/*`、`PROVIDERS`、卡片标题一律不动。
- 分类判据（唯一口径）：`desktop = entrypoint 以 "claude-desktop" 开头`；`official = message.id 以 "msg_" 开头 且 requestId 以 "req_" 开头 且 model 以 "claude-" 开头`（只服务额度，不参与归属）。
- `_CLAUDE_PARSER_VERSION` 3 → 4（强制重解析）；`_SCAN_CACHE_VERSION` 不动。
- `_CLAUDE_SPLIT_MIGRATION` 2 → 3；标记写入沿用 gen 2 的语义：载荷为空时早退、不写盘、不落标记。
- `_QUOTA_TOOLS`、`_QUOTA_TOOL_ALIASES`、`~/.tokei/quota_cycles.json` 锚点键、`compute()` 输出的 `claude_desktop.q5/q7/qf` 键名全部不变。
- 测试命令（在 `windows/` 下）：`./.venv/Scripts/python.exe -m unittest discover -s tests -t tests`；基线 35 项全绿，改完必须仍全绿。
- 注释与文档一律中文，风格对齐现有代码（讲清「为什么」与已知偏差）。
- 提交：按仓库惯例在最后一个任务里一次性提交（代码 + 文档），不要每个任务各提交一次。

---

### Task 1: 归属改按客户端 + 官方命名空间

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`_CLAUDE_PARSER_VERSION` 786；常量块 1738–1746；`scan_claude` 1954–2086；`_claude_usage` 2114–2126）
- Test: `windows/tests/test_windows_client.py`（夹具 `_ClaudeChannelFixture` 264–311；新增两条用例）

**Interfaces:**
- Consumes: 无（本任务打底）。
- Produces（后续任务依赖的准确名字）：
  - `collector._CLAUDE_CHANNELS = (("claude", False), ("claude_desktop", True))` —— 值改语义为「是否桌面客户端」。
  - `collector._QUOTA_CACHE_KEY = "claude_official"` —— 订阅额度专用缓存/账本键。
  - `collector._CLAUDE_NAMESPACES = ("claude", "claude_desktop", "claude_official")`。
  - `collector._LEDGER_VIEW_ONLY_TOOLS = frozenset({"claude_official"})` —— 泛化遍历账本时要跳过的派生视图键。
  - `collector._claude_desktop_client(entrypoint) -> bool`。
  - 扫描缓存事件字典新增字段 `entrypoint`（str 或 None）。

- [ ] **Step 1: 用例夹具加上 entrypoint**

`windows/tests/test_windows_client.py` 里 `_ClaudeChannelFixture._assistant` 改为：

```python
    @staticmethod
    def _assistant(inp, out, mid="msg_01XYZ", request_id="req_01ABC",
                   model="claude-opus-5-5", entrypoint="claude-desktop") -> dict:
        record = {"type": "assistant", "cwd": "E:\\proj", "entrypoint": entrypoint,
                  "timestamp": datetime.now().astimezone().isoformat(),
                  "message": {"id": mid, "model": model,
                              "usage": {"input_tokens": inp, "output_tokens": out}}}
        if request_id is not None:
            record["requestId"] = request_id
        return record
```

**把所有「中继」用例显式传 `entrypoint="sdk-cli"`**（默认值现在是桌面客户端，不传就会归属错误）。涉及 `ClaudeChannelScanTests`、`ClaudeLedgerSplitMigrationTests` 里所有 `request_id=None` 的调用：

```python
        self._write("relay.jsonl", [self._assistant(10, 5, mid="9749d2b1c0",
                                                    request_id=None,
                                                    model="deepseek-v4.1-flash",
                                                    entrypoint="sdk-cli")])
```

- [ ] **Step 2: 写失败用例**

加进 `ClaudeChannelScanTests`：

```python
    def test_desktop_client_relay_usage_lands_in_the_desktop_namespace(self) -> None:
        """未登录的桌面客户端经第三方 API 出网:归属只看客户端,不看出网渠道。"""
        self._write("desktop-relay.jsonl", [
            self._assistant(30, 7, mid="2f08dd23-4a33", request_id=None,
                            model="deepseek-v4.1-flash", entrypoint="claude-desktop-3p")])
        cache = collector._load_scan_cache()
        result = collector.scan_claude(collector.range_bounds(), cache)
        today = result["ranges"]["today"]
        self.assertEqual((today["in"], today["out"]), (0, 0))
        desktop = result["desktop_ranges"]["today"]
        self.assertEqual((desktop["in"], desktop["out"]), (30, 7))
        events = [event for entry in cache["claude_desktop"].values()
                  for event in entry.get("events") or []]
        self.assertEqual([event["entrypoint"] for event in events], ["claude-desktop-3p"])
        self.assertNotIn("desktop-relay.jsonl",
                         {os.path.basename(p) for p in cache["claude"]})

    def test_official_namespace_holds_only_official_events(self) -> None:
        """订阅额度口径的派生命名空间:只收 official,且是桌面卡数据的子集。"""
        self._write("mixed.jsonl", [
            self._assistant(100, 50),
            self._assistant(30, 7, mid="2f08dd23-4a33", request_id=None,
                            model="deepseek-v4.1-flash", entrypoint="claude-desktop-3p"),
            self._assistant(9, 1, mid="9749d2b1c0", request_id=None,
                            model="deepseek-v4.1-flash", entrypoint="sdk-cli")])
        cache = collector._load_scan_cache()
        collector.scan_claude(collector.range_bounds(), cache)
        official = [event for entry in cache[collector._QUOTA_CACHE_KEY].values()
                    for event in entry.get("events") or []]
        self.assertEqual([event["model"] for event in official], ["claude-opus-5-5"])
        self.assertTrue(all(event["official"] for event in official))
        desktop = [event for entry in cache["claude_desktop"].values()
                   for event in entry.get("events") or []]
        self.assertEqual(sorted(event["in"] for event in desktop), [30, 100])
```

再加进 `ClaudeChannelPagesTests`（它已有 `day`、`_cache()` 与临时 `_LEDGER_FILE`）：

```python
    def test_official_view_is_not_counted_twice_in_pages(self) -> None:
        """claude_official 是订阅口径的派生视图:趋势/回顾的总量不能再加一遍。"""
        ledger = {"v": 1, "tools": {
            "claude_desktop": {self.day: {"in": 90, "out": 3, "cr": 5, "cw": 0,
                                          "cost": 2.0, "models": {}}},
            collector._QUOTA_CACHE_KEY: {self.day: {"in": 90, "out": 3, "cr": 5, "cw": 0,
                                                    "cost": 2.0, "models": {}}}}}
        with open(collector._LEDGER_FILE, "w", encoding="utf-8") as fh:
            json.dump(ledger, fh)
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})
        result = collector.build_daily_costs("all", refresh=False, _cache=self._cache())
        row = next(point for point in result["daily"] if point["date"] == self.day)
        self.assertEqual(row["tokens"], 111)      # 13 + 98,派生视图不加倍
        wrapped = collector.build_wrapped("all", refresh=False, _cache=self._cache())
        self.assertEqual(wrapped["total_tokens"], 111)
```

同时给 `test_steady_state_scan_does_not_reparse` 补一行断言：

```python
        self.assertNotIn("empty.jsonl",
                         {os.path.basename(p) for p in cache[collector._QUOTA_CACHE_KEY]})
```

- [ ] **Step 3: 跑用例确认失败**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: FAIL —— `test_desktop_client_relay_usage_lands_in_the_desktop_namespace` 里 `desktop_ranges.today.in` 得到 0（当前判据按 `official` 分，3p 记录被判为中继）；`test_official_namespace_holds_only_official_events` 报 `KeyError: 'claude_official'`。

- [ ] **Step 4: 实现（collector.py 三处）**

(4a) 786 行：

```python
_CLAUDE_PARSER_VERSION = 4
```

(4b) 常量块（原 1738–1746 的注释与 `_CLAUDE_CHANNELS` 段落）替换为：

```python
# 两个卡片命名空间按「客户端」划分(键 = 扫描缓存命名空间 + 账本工具键;值 = 是否桌面客户端):
#   claude          —— 非桌面客户端(cli / sdk-cli 等,任意计费渠道)
#   claude_desktop  —— Claude 桌面客户端(官方 + 第三方;未登录时经第三方 API 出网也算它)
# 计费渠道另由事件上的 official 表示,只服务订阅额度,不参与卡片归属。
_CLAUDE_CHANNELS = (("claude", False), ("claude_desktop", True))
# 订阅额度口径的派生视图:官方通道事件。客户端归属与计费渠道是正交的两个维度,
# 所以它既属于某张卡片、又单独进这个命名空间,只被额度历史读取。
_QUOTA_CACHE_KEY = "claude_official"
_CLAUDE_NAMESPACES = tuple(key for key, _desktop in _CLAUDE_CHANNELS) + (_QUOTA_CACHE_KEY,)
# 账本里只作「视图」存在的工具键:它们的数据已随所属工具的账本天计入,
# 泛化遍历账本的地方(趋势/年度回顾)必须跳过,否则同一份额会被算两遍。
_LEDGER_VIEW_ONLY_TOOLS = frozenset({_QUOTA_CACHE_KEY})
# 桌面客户端的入口前缀(claude-desktop / claude-desktop-3p;将来的新变体自动命中)。
_CLAUDE_DESKTOP_ENTRYPOINT = "claude-desktop"


def _claude_desktop_client(entrypoint):
    """事件是否来自 Claude 桌面客户端。归属只认客户端,与出网渠道(官方/中继)无关。"""
    return isinstance(entrypoint, str) and entrypoint.startswith(_CLAUDE_DESKTOP_ENTRYPOINT)
```

(4c) `_claude_usage` 的 `res` 字典里，在 `"official"` 那行之前插入：

```python
           "entrypoint": o.get("entrypoint"),
```

(4d) `scan_claude`：docstring 改为

```python
    """Claude 一次解析,按客户端拆成三个命名空间。

    - claude          —— 非桌面客户端(cli / sdk-cli 等;任意计费渠道)
    - claude_desktop  —— Claude 桌面客户端的全部用量(官方 + 第三方 API)
    - claude_official —— 官方通道事件(订阅额度口径的派生视图,不进任何卡片)
    归属只看事件自身的 entrypoint(_claude_desktop_client),与出网渠道无关。
    """
```

(4e) `scan_claude` 里三个 dict 改用 `_CLAUDE_NAMESPACES`：

```python
    file_caches = {key: cache.setdefault(key, {}) for key in _CLAUDE_NAMESPACES}
```
```python
    buckets = {key: _claude_empty_ranges() for key in _CLAUDE_NAMESPACES}
```

(4f) 解析循环里事件字典加 `entrypoint`，并把「按 official 二分」换成「按客户端分三组」：

```python
                            "line": line_number, "official": u.get("official") is True,
                            "entrypoint": u.get("entrypoint"),
                        })
                        if proj is None and u.get("cwd"):
                            proj = u["cwd"]
            except OSError:
                continue
            groups = {key: [] for key in _CLAUDE_NAMESPACES}
            for event in events:
                desktop = _claude_desktop_client(event.get("entrypoint"))
                for key, is_desktop in _CLAUDE_CHANNELS:
                    if is_desktop is desktop:
                        groups[key].append(event)
                if event.get("official"):
                    groups[_QUOTA_CACHE_KEY].append(event)
            for key in _CLAUDE_NAMESPACES:
                own = groups[key]
                own = [event for _source, event in
                       _dedupe_claude_events((f, item) for item in own)] if own else []
                if own:
                    file_caches[key][f] = {"sig": sig, "events": own, "proj": proj,
                                           "parser_version": _CLAUDE_PARSER_VERSION}
                else:
                    # 该命名空间在本文件无事件:不留空条目(已有条目要删除)。
                    file_caches[key].pop(f, None)
            parse_sigs[f] = [sig, _CLAUDE_PARSER_VERSION]
            changed = True
```

(4g) 扫描收尾段：

```python
    live = {key: _claude_live_days(file_caches[key], classify, buckets[key])
            for key in _CLAUDE_NAMESPACES}
    _migrate_claude_ledger_split(live["claude_desktop"])
    for key in _CLAUDE_NAMESPACES:
        _claude_channel_into(buckets[key], key, file_caches[key], live[key], classify)
    curs = {key: _claude_current_session(file_caches[key], cur_file)
            for key, _desktop in _CLAUDE_CHANNELS}
    return _claude_scan_result(buckets, curs)
```

（`_migrate_claude_ledger_split` 的签名在 Task 3 才换，本步保持单参数调用不动。）

(4h) 泛化遍历账本的两处加跳过（14353 的 `build_daily_costs`、14924 的 `build_wrapped`）。
这两处按「所有账本工具键」累加 token，派生视图会让官方份额算两遍：

```python
    for tool, tool_days in _load_ledger().get("tools", {}).items():
        if tool in _LEDGER_VIEW_ONLY_TOOLS:
            # 订阅口径的派生视图:份额已随所属工具的账本天计入
            continue
        if not isinstance(tool_days, dict):
            continue
```

- [ ] **Step 5: 跑用例确认通过**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: PASS（35 + 2 = 37 项；`test_quota_window_counts_only_official_events` 仍绿，因为它显式传了 `"claude_desktop"` 键）。

---

### Task 2: 额度读侧只吃官方命名空间

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`_QUOTA_TOOLS` 注释 15110–15113；`_quota_day_tokens` 15162；`_quota_daily_from_tools` 15178；`_quota_claude_events` 15220；`build_quota_detail` 15554）
- Test: `windows/tests/test_windows_client.py`（`ClaudeQuotaChannelTests` 416–433）

**Interfaces:**
- Consumes: Task 1 的 `_QUOTA_CACHE_KEY` 与 `cache["claude_official"]` 命名空间。
- Produces: `collector._QUOTA_LEDGER_KEY = {"claude_desktop": "claude_official"}`；`collector._quota_claude_events(cache=None, cache_key=collector._QUOTA_CACHE_KEY)`。

- [ ] **Step 1: 改失败用例**

`ClaudeQuotaChannelTests.test_quota_window_counts_only_official_events` 改为读官方命名空间（默认参数）：

```python
    def test_quota_window_counts_only_official_events(self) -> None:
        now = int(time.time())
        relay = {"timestamp": datetime.fromtimestamp(now - 60).astimezone().isoformat(),
                 "in": 1000, "out": 0, "cr": 0, "cw": 0}
        official = {"timestamp": datetime.fromtimestamp(now - 60).astimezone().isoformat(),
                    "in": 40, "out": 2, "cr": 3, "cw": 5}
        cache = {"claude": {"relay.jsonl": {"events": [relay]}},
                 "claude_desktop": {"desktop.jsonl": {"events": [official]}},
                 collector._QUOTA_CACHE_KEY: {"official.jsonl": {"events": [official]}}}
        amounts = [amount for _ts, _day, amount in collector._quota_claude_events(cache)]
        self.assertEqual(amounts, [50])
```

`test_only_the_desktop_ledger_feeds_the_claude_cycle` 改为（顺带改名字）：

```python
    def test_cycle_tokens_come_from_the_official_ledger_key(self) -> None:
        """桌面卡的 claude_desktop 键是客户端全部用量,不能当订阅用量;订阅口径在 claude_official。"""
        day = {"2026-09-27": {"in": 100, "out": 5, "cr": 0, "cw": 0, "cost": 1.0}}
        self.assertEqual(collector._quota_daily_from_tools({"claude_desktop": day}), {})
        self.assertEqual(collector._quota_daily_from_tools({collector._QUOTA_CACHE_KEY: day}),
                         {"2026-09-27": {"cd": 105, "x": 0, "g": 0}})
```

- [ ] **Step 2: 跑用例确认失败**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: FAIL —— 第一条用例 `claude_official` 键被当成未知命名空间读出 `[]`（默认参数还是 `"claude_desktop"`，会读到 desktop.jsonl 的 50 其实相同？若相同则第二条用例必失败：`_quota_daily_from_tools` 仍从 `claude_desktop` 取数，第一条断言会拿到 `{"2026-09-27": {...}}` 而不是 `{}`）。第二条必须失败。

- [ ] **Step 3: 实现**

(3a) `_QUOTA_TOOLS` 上方注释（15110–15113）改为：

```python
# 有周额度窗口的三个工具 → 日表里的短键。
# 工具键仍叫 claude_desktop(锚点文件、peer 读数键都用它),但账本日表要读
# claude_official —— 官方通道口径,见 _QUOTA_LEDGER_KEY。
_QUOTA_TOOLS = (("claude_desktop", "cd"), ("codex", "x"), ("grok", "g"))
# 旧版本 peer 的额度读数与锚点还挂在 claude 键上,读到要认。
_QUOTA_TOOL_ALIASES = {"claude": "claude_desktop"}
# 额度工具键 → 账本工具键。桌面卡是客户端口径(含第三方),订阅周期只认官方通道。
_QUOTA_LEDGER_KEY = {"claude_desktop": _QUOTA_CACHE_KEY}
```

(3b) `_quota_day_tokens` 的 `claude_desktop` 分支注释改为：

```python
    if tool == "claude_desktop":
        # 订阅口径的日表来自 claude_official(官方通道);桌面卡那个键含第三方用量,不参与。
        return sum(int(entry.get(k, 0) or 0) for k in ("in", "out", "cr", "cw"))
```

(3c) `_quota_daily_from_tools`：

```python
def _quota_daily_from_tools(tools):
    """账本日表 → {日: {"cd": …, "x": …, "g": …}}。"""
    out = {}
    for tool, key in _QUOTA_TOOLS:
        ledger_days = tools.get(_QUOTA_LEDGER_KEY.get(tool, tool)) or {}
        for day, entry in ledger_days.items():
            if isinstance(entry, dict):
                out.setdefault(day, {k: 0 for _t, k in _QUOTA_TOOLS})[key] = \
                    _quota_day_tokens(tool, entry)
    return out
```

(3d) `_quota_claude_events` 默认键换成官方命名空间，docstring 补一句：

```python
def _quota_claude_events(cache=None, cache_key=_QUOTA_CACHE_KEY):
    """去重后的 Claude 事件 → [(epoch, 本地日, tokens)]。去重逻辑与 scan_claude 一致。

    默认读订阅额度专用的官方命名空间(见 scan_claude 的 claude_official)。
    """
```

(3e) `build_quota_detail` 里：

```python
            events[tool] = (_quota_claude_events(cache)
                            if tool == "claude_desktop"
                            else _quota_codex_events(codex_spans, cache) if tool == "codex"
                            else None)
```

- [ ] **Step 4: 跑用例确认通过**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: PASS（37 项）。并确认没有别的调用点还传旧键：

Run: `cd E:/tokei-windows/windows && grep -n "_quota_claude_events(\|_quota_daily_from_tools(" tokei_windows/collector.py tests/test_windows_client.py`
Expected: 只剩 `build_quota_detail`（不传键）与测试里的新写法。

---

### Task 3: 一次性迁移 claude_split 2 → 3

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`_CLAUDE_SPLIT_MIGRATION` 1743–1746；新增 `_claude_subset_live_days`（放在 `_claude_live_days` 之后，约 1846 行）；`_migrate_claude_ledger_split` 1894–1951；`scan_claude` 的迁移调用点）
- Test: `windows/tests/test_windows_client.py`（`ClaudeLedgerSplitMigrationTests` 314–394）

**Interfaces:**
- Consumes: Task 1 的命名空间与 `_claude_desktop_client`；`_claude_refresh_aggregates`、`_claude_live_days`、`_ledger_values(..., subtract=True)`。
- Produces: `collector._migrate_claude_ledger_split(desktop_days, desktop_relay_days) -> bool`；`collector._claude_subset_live_days(fc, keep, classify, bucket) -> dict`。

- [ ] **Step 1: 改/写失败用例**

`ClaudeLedgerSplitMigrationTests` 整体替换为（保留原有四类场景，换成 gen 3 语义 + 两条新用例）：

```python
class ClaudeLedgerSplitMigrationTests(_ClaudeChannelFixture):
    """claude_split 2 → 3:把桌面客户端的份额(含第三方)从 claude 挪到 claude_desktop。

    gen 2 已减过官方份额,所以从 marker=2 出发只减「桌面非官方」;
    9-28 之前的混合账本(无标记)要整块减掉桌面份额。
    """

    def setUp(self) -> None:
        super().setUp()
        self.day = datetime.now().astimezone().date().isoformat()

    def _seed_ledger(self, claude_in: int, marker=None) -> None:
        """存量账本:claude 的这一天含桌面客户端的份额。"""
        day = {"in": claude_in, "out": 0, "cr": 0, "cw": 0, "cost": 1.0, "models": {},
               "_sources": {"legacy.jsonl": {"in": claude_in, "out": 0, "cr": 0, "cw": 0,
                                             "cost": 1.0}}}
        ledger = {"v": 1, "tools": {"claude": {self.day: day}}}
        if marker is not None:
            ledger["claude_split"] = marker
        self.ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
        collector._LEDGER_CACHE.update({"data": None, "dirty": False})

    def _scan_and_flush(self) -> dict:
        cache = collector._load_scan_cache()
        collector.scan_claude(collector.range_bounds(), cache)
        collector.ledger_flush()
        return json.loads(self.ledger_path.read_text(encoding="utf-8"))

    def _write_desktop_client_relay(self, inp: int) -> None:
        self._write("desktop-relay.jsonl", [
            self._assistant(inp, 0, mid="2f08dd23-4a33", request_id=None,
                            model="deepseek-v4.1-flash", entrypoint="claude-desktop-3p")])

    def _write_cli_relay(self, inp: int) -> None:
        self._write("relay.jsonl", [
            self._assistant(inp, 0, mid="9749d2b1c0", request_id=None,
                            model="deepseek-v4.1-flash", entrypoint="sdk-cli")])

    def test_gen2_ledger_loses_only_the_desktop_relay_share(self) -> None:
        self._seed_ledger(claude_in=40, marker=2)
        self._write_desktop_client_relay(30)
        self._write_cli_relay(10)
        stored = self._scan_and_flush()
        self.assertEqual(stored["claude_split"], 3)
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 30)
        # 这一天没有官方事件,订阅口径为空
        self.assertNotIn(self.day, stored["tools"].get(collector._QUOTA_CACHE_KEY, {}))

    def test_pre_split_ledger_loses_the_whole_desktop_share(self) -> None:
        """9-28 之前的混合账本(无标记):官方 + 非官方一起搬走。"""
        self._seed_ledger(claude_in=100)
        self._write("desktop.jsonl", [self._assistant(90, 0)])
        self._write_cli_relay(10)
        stored = self._scan_and_flush()
        self.assertEqual(stored["claude_split"], 3)
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 90)
        self.assertEqual(stored["tools"][collector._QUOTA_CACHE_KEY][self.day]["in"], 90)

    def test_migration_runs_once(self) -> None:
        self._seed_ledger(claude_in=40, marker=2)
        self._write_desktop_client_relay(30)
        self._write_cli_relay(10)
        self._scan_and_flush()
        stored = self._scan_and_flush()
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 30)

    def test_migration_conserves_the_card_totals(self) -> None:
        self._seed_ledger(claude_in=40, marker=2)
        self._write_desktop_client_relay(30)
        self._write_cli_relay(10)
        stored = self._scan_and_flush()
        cards = (stored["tools"]["claude"][self.day]["in"]
                 + stored["tools"]["claude_desktop"][self.day]["in"])
        self.assertEqual(cards, 40)

    def test_flush_of_a_stale_memo_does_not_resurrect_the_split(self) -> None:
        """迁移前就载入账本的另一个进程(tray),其 flush 不能按旧来源把桌面份额加回来。"""
        desktop_days = {self.day: {"in": 30, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        desktop_relay_days = dict(desktop_days)
        self._seed_ledger(claude_in=40, marker=2)
        stale_memo = collector._load_ledger()        # 另一个进程:迁移前载入的内存账本
        stale_memo["tools"]["claude_desktop"] = dict(desktop_days)
        collector._migrate_claude_ledger_split(desktop_days, desktop_relay_days)
        collector._LEDGER_CACHE.update({"data": stale_memo, "dirty": True})  # 它随后落盘
        collector.ledger_flush()
        stored = json.loads(self.ledger_path.read_text(encoding="utf-8"))
        self.assertEqual(stored["claude_split"], 3)
        self.assertEqual(stored["tools"]["claude"][self.day]["in"], 10)
        self.assertEqual(stored["tools"]["claude_desktop"][self.day]["in"], 30)

    def test_fresh_ledger_still_gets_the_migration_marker(self) -> None:
        """全新装机(无账本文件)也必须落标记,否则下一轮会把桌面份额从中继天里错减掉。"""
        desktop_days = {self.day: {"in": 30, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        with patch.object(collector, "_load_tokei_config", lambda: {}):
            self.assertFalse(self.ledger_path.exists())
            self.assertFalse(collector._migrate_claude_ledger_split({}, {}))
            self.assertFalse(self.ledger_path.exists())     # 空载荷:早退,不写盘
            self.assertTrue(collector._migrate_claude_ledger_split(desktop_days, desktop_days))
        stored = json.loads(self.ledger_path.read_text(encoding="utf-8"))
        self.assertEqual(stored["claude_split"], 3)
        self.assertEqual(stored["tools"]["claude"], {})     # 没有存量天可减

    def test_unreadable_ledger_is_neither_migrated_nor_overwritten(self) -> None:
        """账本在、但读不出来:不迁移、不落标记、不覆盖,下一轮再试。"""
        desktop_days = {self.day: {"in": 30, "out": 0, "cr": 0, "cw": 0,
                                   "cost": 0.0, "models": {}}}
        corrupt = '{"v": 1, "tools": {"claude": {'
        self.ledger_path.write_text(corrupt, encoding="utf-8")
        with patch.object(collector, "_load_tokei_config", lambda: {}):
            self.assertFalse(collector._migrate_claude_ledger_split(
                desktop_days, dict(desktop_days)))
        self.assertEqual(self.ledger_path.read_text(encoding="utf-8"), corrupt)
```

注意 `test_gen2_ledger_loses_only_the_desktop_relay_share` 里 `stored["tools"]` 只有 `claude` 被种下：`claude_desktop` 的新值 30 完全来自实时对账，`claude_official` 这天没有条目。

- [ ] **Step 2: 跑用例确认失败**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: FAIL —— `_migrate_claude_ledger_split() takes 1 positional argument but 2 were given`（旧签名），以及 `claude_split` 期望 3 得到 2。

- [ ] **Step 3: 实现**

(3a) `_CLAUDE_SPLIT_MIGRATION` 段落（1743–1746）替换为：

```python
# 账本一次性迁移。代次说明:
#   gen 2(2026-09-28):把 claude 里官方通道的存量份额挪到 claude_desktop(那时命名空间按渠道分)。
#   gen 3(2026-09-29):命名空间改按客户端分,把桌面客户端的份额(官方之外的部分)再挪一次;
#                      若磁盘标记缺失(9-28 之前的混合账本),则整块搬走桌面份额。
# 该值同时是迁移代次 id(落盘键为 claude_split)。降级陷阱:拆分前的旧构建再跑这份账本时,
# claude 的实时混合值会在高水位合并里胜出,而 claude_desktop 仍带着桌面份额 —— 两页会
# 重复计数;要重跑迁移,须先从 ~/.tokei/ledger.json 删掉 claude_split 键。
_CLAUDE_SPLIT_MIGRATION = 3
```

(3b) 在 `_claude_live_days` 之后插入（依赖 `_claude_refresh_aggregates`，两者都在上文）：

```python
def _claude_subset_live_days(fc, keep, classify, bucket):
    """某命名空间里满足 keep(event) 的事件 → 逐日实测(迁移载荷用,不写回缓存)。

    直接过滤事件而不复用条目里的 days:迁移要的是子集的口径,条目聚合是整个命名空间的。
    """
    subset = {}
    for path, entry in fc.items():
        events = [event for event in entry.get("events", []) if keep(event)]
        if events:
            subset[path] = {"proj": entry.get("proj"), "events": events}
    if not subset:
        return {}
    _claude_refresh_aggregates(subset)
    return _claude_live_days(subset, classify, bucket)
```

(3c) `_migrate_claude_ledger_split` 替换为：

```python
def _migrate_claude_ledger_split(desktop_days, desktop_relay_days):
    """一次性迁移:把 claude 里的桌面客户端份额挪到 claude_desktop。

    载荷按存量代次选:
    - 磁盘标记为 2(gen 2 已减过官方份额)→ 只减桌面客户端的非官方份额(desktop_relay_days);
    - 标记缺失(9-28 之前的混合账本)→ 整块减掉桌面份额(desktop_days)。

    份额用本次扫描的实测值逐日相减;减法走 _ledger_values(..., subtract=True) ——
    它会跳过 _sources,于是被改过的天退化为「聚合 + 残差」,随后的正常对账按现存日志
    重建来源。日志已被清理的天扫不到实测值,份额减不掉,保留在 claude(已知偏差)。
    直接改磁盘并让内存缓存失效,避免 flush 时旧来源把减掉的量又合并回来。
    hours/model_efforts 由键并集原样保留(不按残差重建),所以迁移当天 claude 的
    按小时/按 effort 明细仍含桌面份额;天与按模型的 token 数是对的。
    """
    previous = _load_ledger().get("claude_split")
    if previous == _CLAUDE_SPLIT_MIGRATION:
        return False
    if not (desktop_relay_days if previous == 2 else desktop_days):
        return False
    lock_fd = None
    lock_kind = None
    try:
        os.makedirs(os.path.dirname(_LEDGER_FILE), mode=0o700, exist_ok=True)
        lock_fd = os.open(f"{_LEDGER_FILE}.lock", os.O_CREAT | os.O_RDWR, 0o600)
        lock_kind = _acquire_file_lock(lock_fd)
    except OSError:
        if lock_fd is not None:
            os.close(lock_fd)
        lock_fd = None
    try:
        try:
            with open(_LEDGER_FILE, encoding="utf-8") as fh:
                fresh = json.load(fh)
        except FileNotFoundError:
            fresh = {"v": _LEDGER_VERSION, "tools": {}}      # 真·没有账本:没东西可迁,但要落标记
        except (OSError, ValueError):
            # 文件在、但读不出来(被占用/损坏):不迁移也不落标记,下一轮再试 ——
            # 绝不能在没读到真实账本时写标记,那会把整份历史换成一份空账本。
            return False
        if not isinstance(fresh, dict) or fresh.get("v") != _LEDGER_VERSION:
            return False
        if fresh.get("claude_split") == _CLAUDE_SPLIT_MIGRATION:
            return False
        # 锁内重新判一次代次:等锁期间别的进程可能已经迁完了。
        payload_days = (desktop_relay_days if fresh.get("claude_split") == 2
                        else desktop_days)
        if not payload_days:
            return False
        days = fresh.setdefault("tools", {}).setdefault("claude", {})
        for dk, share in payload_days.items():
            stored = days.get(dk)
            if not isinstance(stored, dict):
                continue
            payload = {field: share.get(field, 0)
                       for field in ("in", "out", "cr", "cw", "cost")}
            payload["models"] = share.get("models") or {}
            days[dk] = _ledger_values(stored, payload, subtract=True)
        fresh["claude_split"] = _CLAUDE_SPLIT_MIGRATION
        _save_ledger(fresh)
        _LEDGER_CACHE["data"] = None      # 让随后的 reconcile 读到迁移后的账本
        _LEDGER_CACHE["dirty"] = False
        return True
    finally:
        if lock_fd is not None:
            try:
                _release_file_lock(lock_fd, lock_kind)
            except OSError:
                pass
            finally:
                os.close(lock_fd)
```

（`_release_file_lock` 的 `except OSError` 是原实现没有的兜底，保持原样写即可 —— 按现有代码只留 `finally: os.close(lock_fd)`。）

(3d) `scan_claude` 收尾段的迁移调用改为：

```python
    if _load_ledger().get("claude_split") != _CLAUDE_SPLIT_MIGRATION:
        # 迁移只在未迁完时算载荷:桌面客户端的非官方份额要逐事件过滤,不该每轮都算。
        desktop_relay_days = _claude_subset_live_days(
            file_caches["claude_desktop"], lambda event: not event.get("official"),
            classify, _claude_empty_ranges())
        _migrate_claude_ledger_split(live["claude_desktop"], desktop_relay_days)
```

- [ ] **Step 4: 跑用例确认通过**

Run: `cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v`
Expected: PASS（37 + 1 = 38 项）。

---

### Task 4: 真机验收、文档与提交

**Files:**
- Modify: 无（只跑验证；如发现偏差回到对应任务修）
- Verify: `docs/superpowers/specs/2026-09-29-claude-client-attribution-design.md` §7.2 的 1–3 条

**Interfaces:**
- Consumes: Task 1–3 的全部产出。
- Produces: 真机口径证据 + 一个提交。

- [ ] **Step 1: 备份真机账本与缓存**

```bash
cd /c/Users/zhuji/.tokei && cp ledger.json ledger.json.pre-client-attribution.bak && cp -r cache cache.pre-client-attribution.bak
```

- [ ] **Step 2: 跑源码 compute()，核对两条卡片口径**

```bash
cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe - <<'PY'
from tokei_windows import collector
u = collector.compute()
for key in ("claude", "claude_desktop"):
    today = u[key]["ranges"]["today"]
    print(key, {k: today[k] for k in ("in", "out", "cr", "cw")})
PY
```

Expected：`claude_desktop` 今日 token 量级 ≈ 桌面客户端（`claude-desktop-3p`）今日用量，明显大于 0；`claude` 今日只剩非桌面客户端（`sdk-cli` 等）的量。若 `claude_desktop` 今日仍为 0，回到 Task 1 检查判据。

- [ ] **Step 3: 核对账本与订阅口径**

```bash
cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe - <<'PY'
import json
from tokei_windows import collector
led = json.load(open(collector._LEDGER_FILE, encoding="utf-8"))
print("claude_split =", led.get("claude_split"))
tools = led["tools"]
for day in sorted(tools.get("claude", {}))[-1:]:
    print(day, "claude =", tools["claude"][day]["in"] + tools["claude"][day]["out"],
          "| claude_desktop =",
          tools.get("claude_desktop", {}).get(day, {}).get("in", 0)
          + tools.get("claude_desktop", {}).get(day, {}).get("out", 0),
          "| claude_official =",
          tools.get(collector._QUOTA_CACHE_KEY, {}).get(day, {}).get("in", 0))
PY
```

Expected：`claude_split = 3`；最近一天的 `claude` + `claude_desktop` 之和与迁移前一致（对照 `ledger.json.pre-client-attribution.bak` 同一天）；`claude_official` ≤ `claude_desktop`。

- [ ] **Step 4: 核对额度历史仍只算官方通道**

```bash
cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe - <<'PY'
from tokei_windows import collector
detail = collector.build_quota_detail()
for cycle in detail["cycles"]:
    if cycle["tool"] == "claude_desktop":
        print(cycle["start"], cycle["end"], "tokens =", cycle["tokens"],
              "used% =", cycle["used_pct"], "current =", cycle["current"])
        break
PY
```

Expected：当前周期 `tokens` 只反映官方通道用量（今天没有官方事件时应接近 0），不再出现 8 亿量级。

- [ ] **Step 5: 全量测试 + 界面截图核对**

```bash
cd E:/tokei-windows/windows && ./.venv/Scripts/python.exe -m unittest discover -s tests -t tests -v
```

Expected：38 项全绿。

界面核对：用 `windows/scripts/smoke_ui.py`（或直接启动 `run_app.py`）确认「Claude Code Desktop」卡显示今天的用量、额度条仍为空、趋势/模型排行/项目足迹里出现 `(Claude Desktop)` 的桌面客户端模型行。

- [ ] **Step 6: 提交**

```bash
cd E:/tokei-windows && git add windows/tokei_windows/collector.py windows/tests/test_windows_client.py docs/superpowers/specs/2026-09-29-claude-client-attribution-design.md docs/superpowers/specs/2026-09-28-claude-channel-split-design.md docs/superpowers/plans/2026-09-29-claude-client-attribution.md && git commit -m "fix(windows): attribute Claude usage by client, keep subscription cycle official-only"
```

（提交信息正文补上：现象与根因、三命名空间口径、claude_split 2→3 迁移、测试 35→38、真机核对结论。）

---

## Self-Review

**Spec coverage**

| 规格条目 | 落在哪个任务 |
|---|---|
| §3 分类规则（客户端归属 + official 只服务额度） | Task 1 Step 4b/4f |
| §4.1 三个命名空间 | Task 1 Step 4b/4e |
| §4.2 扫描流程与解析器版本 3→4 | Task 1 Step 4a/4d/4f/4g |
| §4.3 官方命名空间与读侧映射 | Task 2 全部 |
| §4.4 迁移与代次载荷 | Task 3 全部 |
| §5 输出契约不变 | Task 1 保持 `_claude_scan_result` / `_empty_claude` 不动；Task 4 Step 2 验证 |
| §6 界面不变 | 无改动（Global Constraints 已锁）；Task 4 Step 5 截图核对 |
| §7.1 单元测试 | Task 1/2/3 的用例 |
| §7.2 真机验收 | Task 4 Step 2–4 |
| §8 风险 | 注释（Task 1 常量块、Task 3 迁移 docstring）与规格文档 |

**Placeholder scan**：无 TBD / 「类似上文」；每个代码步骤都给了可粘贴的代码块与精确文件行号。

**Type consistency**：`_QUOTA_CACHE_KEY`、`_CLAUDE_NAMESPACES`、`_claude_desktop_client`、`_claude_subset_live_days`、`_migrate_claude_ledger_split(desktop_days, desktop_relay_days)`、`_QUOTA_LEDGER_KEY` 在 Task 1–3 中命名与签名一致；Task 2 的 `_quota_claude_events(cache=None, cache_key=_QUOTA_CACHE_KEY)` 在 Task 4 的验证脚本里不出现（走 `build_quota_detail`）。
