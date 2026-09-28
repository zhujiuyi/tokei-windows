# Claude 渠道拆分实施计划（API 通道 / 官方订阅）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Claude 用量按渠道拆成 `claude`（OpenCode 中继/API）与 `claude_desktop`（官方通道，承载订阅额度）两个工具，全部页面口径一致，额度历史只统计官方通道。

**Architecture:** 采集层一次解析、两路输出：每条用量记录按官方响应特征（`msg_` + `req_` + `claude-*`）分类，分别写入两个扫描缓存命名空间与两个账本工具键；账本做一次性迁移（用当天桌面实测值从旧混合存档里减去）。桥接层把新工具当作普通 provider 处理（`PROVIDERS` 遍历），仅额度条与额度历史工具键需要显式改动。

**Tech Stack:** Python 3.13（`windows/.venv`，PySide6 6.11.2 + QML + Nuitka onefile）；测试用 stdlib `unittest`。

**Spec:** `docs/superpowers/specs/2026-09-28-claude-channel-split-design.md`

## Global Constraints

- **分类口径（唯一，不得自创第二套判据）**：`message.id` 以 `msg_` 开头 **且** `requestId` 以 `req_` 开头 **且** `model` 以 `claude-` 开头 → 官方通道 `claude_desktop`；否则 → 中继通道 `claude`。不使用 `entrypoint`。
- **工具键与显示名**：`claude` = 「Claude Code」（原卡片，现在只统计中继通道）；`claude_desktop` = 「Claude Code Desktop」（新卡片，颜色 `#f2b06a`）。
- **Codex 本次不动**（`codex_reserve` 保持现状）。
- **不要提升 `_SCAN_CACHE_VERSION`**：新命名空间是纯增量，旧扫描缓存仍可用、其余工具不重扫；只提升 `_CLAUDE_PARSER_VERSION`（Task 1）。
- **同步快照不需要改代码**：`compute()` 的新键由 `_sync_safe_usage_payload()` 原样带出（Task 4 的验收脚本会核对此事）。
- **不要 git commit**：本工作区含用户早前的未提交改动（仪表盘/界面）与今日修复，实施期间所有任务都不提交。每个任务末尾只做 `git status --short` / `git diff --stat` 自查。是否需要提交由用户最后决定。
- **测试命令**（Git Bash，工作目录 `E:/tokei-windows/windows`）：
  `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
  基线：实施前 18 项测试全绿，实施后只增不减。
- **`windows/tokei_windows/collector.py` 是混合行尾文件**（大部分行 CRLF，51–53、215–233 等少数行 LF）。只用 Edit 做定点替换，禁止整体重写。每次改完执行：
  `cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py`
  若插入行数明显超出本次改动量（例如几行改动显示成 +100 以上），说明编辑工具把整份文件行尾统一了 —— 用「工具：行尾还原脚本」修回后再继续。
- **控制台是 GBK**：任何含中文的脚本输出都要写 UTF-8 文件再读，不要 `print` 到控制台。
- 注释风格与现有代码一致：中文、解释「为什么」。新代码沿用现有函数的命名习惯（`_claude_*`、snake_case）。

### 工具：行尾还原脚本（仅在行尾被整体改动后使用）

```
cd "E:/tokei-windows" && py - <<'PY'
# 只把「内容未变」的行恢复成索引版行尾;写回前断言去掉 \r 后内容完全一致
import subprocess, difflib
rel = "windows/tokei_windows/collector.py"
old = subprocess.run(["git", "show", f":{rel}"], capture_output=True, check=True).stdout.split(b"\n")
raw = open(rel, "rb").read()
new = raw.split(b"\n")
strip = lambda ls: [l.rstrip(b"\r") for l in ls]
sm = difflib.SequenceMatcher(None, strip(old), strip(new), autojunk=False)
fixed, restored = list(new), 0
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == "equal":
        for k in range(i2 - i1):
            if fixed[j1 + k] != old[i1 + k]:
                fixed[j1 + k] = old[i1 + k]; restored += 1
out = b"\n".join(fixed)
assert out.replace(b"\r", b"") == raw.replace(b"\r", b""), "content changed"
open(rel, "wb").write(out)
print("restored", restored)
PY
```

## 文件结构

| 文件 | 职责 | 本次改动 |
|---|---|---|
| `windows/tokei_windows/collector.py` | 扫描/账本/额度/各页面数据源 | 分类字段、双命名空间扫描、账本迁移、compute 输出、额度历史换键、趋势/模型/项目/年度回顾、`_empty_claude` |
| `windows/tokei_windows/bridge.py` | 采集结果 → QML 的桥 | `PROVIDERS` 新条目、卡片额度条换键、`cost_fields` |
| `windows/tokei_windows/qml/QuotaCycleCard.qml` | 额度历史周期卡 | 工具名映射与颜色 |
| `windows/scripts/smoke_ui.py` | 离屏 UI 冒烟与截图 | 夹具补 `claude_desktop` |
| `windows/tests/test_windows_client.py` | 单元测试 | 新增 9 项，改 1 项 |

---

### Task 1: 官方通道分类字段

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`_CLAUDE_PARSER_VERSION` ≈786；`_claude_usage` ≈1948-1981）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: 无（起点）
- Produces: `_claude_usage(line, want_dt=...)` 返回值新增键 `"official"`（严格 bool）；`_CLAUDE_PARSER_VERSION = 2`。Task 2 依赖二者。

- [ ] **Step 1: 记录基线数字（迁移守恒对照用）**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
d = c.compute()["claude"]
tok = lambda b: b["in"] + b["out"] + b["cr"] + b["cw"]
snap = {"today": tok(d["ranges"]["today"]), "all": tok(d["ranges"]["all"]),
        "cost_all": round(d["ranges"]["all"]["cost"], 4),
        "q5": d.get("q5"), "q7": d.get("q7")}
path = os.path.join(os.environ["TEMP"], "tokei_split_baseline.json")
json.dump(snap, open(path, "w"), ensure_ascii=False, indent=1)
print(path, snap)
PY
```

Expected: 打印一个 `%TEMP%\tokei_split_baseline.json` 路径与数字（`all` 应为 20 亿量级）。**把 `all` 记下来**，Task 7 要拿它做 `claude + claude_desktop ≈ 基线 all` 的守恒核对。

- [ ] **Step 2: 写失败测试**

在 `windows/tests/test_windows_client.py` 的 `ClaudeDesktopCacheTests` 之前插入：

```python
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
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.ClaudeChannelClassificationTests -v`
Expected: FAIL — `KeyError: 'official'`。

- [ ] **Step 4: 实现**

`collector.py` 第 786 行：

```python
_CLAUDE_PARSER_VERSION = 2
```

`_claude_usage` 的返回块（当前 ≈1973-1981）替换为：

```python
    mid = msg.get("id")
    request_id = o.get("requestId") or o.get("request_id")
    model = msg.get("model")
    res = {"in": inp, "out": out, "cr": cr, "cw": cw, "cw5": w5, "cw1": w1,
           "effort": o.get("effort") or msg.get("effort") or msg.get("reasoning_effort"),
           "model": model, "cwd": o.get("cwd"), "mid": mid,
           "request_id": request_id,
           "event_id": o.get("uuid"), "sidechain": o.get("isSidechain") is True,
           # 官方通道(订阅/官方 API)的响应特征:Claude 自家消息 id + 请求 id + claude-* 模型,
           # 三者缺一即视为经中继/第三方 API 消耗(如 OpenCode),不计入订阅额度。
           "official": bool(isinstance(mid, str) and mid.startswith("msg_")
                            and isinstance(request_id, str) and request_id.startswith("req_")
                            and isinstance(model, str) and model.startswith("claude-"))}
    res["cost"] = _claude_event_cost(res)
    if want_dt:
        res["dt"] = dt
    return res
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（19 项）。

- [ ] **Step 6: 自查（不提交）**

```bash
cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py && git status --short
```
Expected: collector.py 新增行数在个位量级；无意外文件。

---

### Task 2: 双命名空间扫描（`scan_claude` 拆渠道）

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`_empty_claude` ≈1403；在 `_dedupe_claude_events` ≈1693 之后加常量与 3 个辅助函数；重写 `scan_claude` ≈1732-1945）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: Task 1 的 `official` 字段与解析器版本 2。
- Produces:
  - `_CLAUDE_CHANNELS = (("claude", False), ("claude_desktop", True))`
  - `scan_claude(bounds, cache)` 返回 `{"ranges", "cur", "desktop_ranges", "desktop_cur"}`；同时写入 `cache["claude"]` / `cache["claude_desktop"]` 两个命名空间（条目结构不变）。
  - `cache["_claude_parse_sigs"]`：`{文件路径: [签名, 解析器版本]}`，与渠道无关的「已解析」索引（保证两个渠道都没事件的文件不被每轮重读）。
  - `_empty_claude()` 返回四键同名结构（错误兜底）。
  - 两个渠道各自 `ledger_reconcile(<工具键>, …)`；本任务同时开始写 `tools["claude_desktop"]`（迁移在 Task 3，中间态安全：旧 `claude` 存档因来源判定不会被动到，见 Task 3 说明）。

- [ ] **Step 1: 写失败测试**

在 `ClaudeChannelClassificationTests` 之后插入：

```python
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.ClaudeChannelScanTests -v`
Expected: FAIL — `KeyError: 'desktop_ranges'`（第一个）、`KeyError: 'claude_desktop'`。

- [ ] **Step 3: 实现**

3a. `_empty_claude`（≈1403-1406）替换为：

```python
def _empty_claude():
    def ranges():
        return {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0,
                    "models": {}, "model_efforts": {}, "sessions": set()}
                for k in RANGE_KEYS}
    empty_cur = {"in": 0, "out": 0, "cr": 0, "cw": 0, "name": "-"}
    return {"ranges": ranges(), "cur": dict(empty_cur),
            "desktop_ranges": ranges(), "desktop_cur": dict(empty_cur)}
```

3b. 在 `_dedupe_claude_events` 之后、`scan_claude` 之前加入：

```python
# 两个渠道:键 = 扫描缓存命名空间 + 账本工具键;值 = 是否官方通道(见 _claude_usage 的 official)。
# claude 用中继/第三方 API(如 OpenCode);claude_desktop 走官方通道,订阅额度读数挂在它上面。
_CLAUDE_CHANNELS = (("claude", False), ("claude_desktop", True))


def _claude_empty_ranges():
    return {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0,
                "models": {}, "model_efforts": {}, "sessions": set()}
            for k in RANGE_KEYS}


def _claude_refresh_aggregates(fc):
    """重算某渠道每个文件条目的按日聚合(写回缓存条目);返回是否有变化。

    跨文件去重只在本渠道内做 —— 不同渠道的同一逻辑事件不会互相顶掉。
    """
    selected = _dedupe_claude_events([(path, event) for path, entry in fc.items()
                                      for event in entry.get("events", [])])
    aggregates = {path: {"days": {}, "hours": [0] * 24, "day_hours": {}, "dh": set(),
                         "proj": entry.get("proj")}
                  for path, entry in fc.items()}
    for path, event in selected:
        dt = parse_ts(event.get("timestamp", ""))
        if dt is None:
            continue
        dt = dt.astimezone()
        day_key = dt.date().isoformat()
        aggregate = aggregates[path]
        if not aggregate["proj"] and event.get("cwd"):
            aggregate["proj"] = event["cwd"]
        day = aggregate["days"].setdefault(
            day_key, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0,
                      "models": {}, "model_efforts": {}})
        day["in"] += event["in"]; day["out"] += event["out"]
        day["cr"] += event["cr"]; day["cw"] += event["cw"]
        day["cost"] += event["cost"]
        model = event.get("model") or "unknown"
        model_usage = day["models"].setdefault(
            model, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
        model_usage["in"] += event["in"]; model_usage["out"] += event["out"]
        model_usage["cr"] += event["cr"]; model_usage["cw"] += event["cw"]
        model_usage["cost"] += event["cost"]
        effort_usage = day["model_efforts"].setdefault(model, {}).setdefault(
            event.get("effort") or "未记录", {"in": 0, "out": 0, "cr": 0, "cw": 0})
        effort_usage["in"] += event["in"]; effort_usage["out"] += event["out"]
        effort_usage["cr"] += event["cr"]; effort_usage["cw"] += event["cw"]
        amount = _claude_event_total(event)
        aggregate["hours"][dt.hour] += amount
        aggregate["day_hours"].setdefault(day_key, [0] * 24)[dt.hour] += amount
        aggregate["dh"].add(f"{day_key}:{dt.hour}")
    changed = False
    for path, aggregate in aggregates.items():
        entry = fc[path]
        values = {
            "days": aggregate["days"], "hours": aggregate["hours"],
            "day_hours": aggregate["day_hours"], "dh": sorted(aggregate["dh"]),
            "proj": aggregate["proj"],
        }
        for key, value in values.items():
            if entry.get(key) != value:
                entry[key] = value
                changed = True
    return changed


def _claude_live_days(fc, classify, bucket):
    """某渠道现存日志的按日实时聚合(含项目名与会话数),账本的实时来源。"""
    live_days = {}
    day_projects = {}
    for f, entry in fc.items():
        proj_name = os.path.basename((entry.get("proj") or "").rstrip("/"))
        for dk, day in entry.get("days", {}).items():
            agg = live_days.setdefault(
                dk, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0,
                     "models": {}, "model_efforts": {}})
            agg["in"] += day["in"]; agg["out"] += day["out"]
            agg["cr"] += day["cr"]; agg["cw"] += day["cw"]; agg["cost"] += day["cost"]
            if proj_name:
                day_projects.setdefault(dk, set()).add(proj_name)
            for mn, mv in day["models"].items():
                mm = agg["models"].setdefault(mn, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
                mm["in"] += mv["in"]; mm["out"] += mv["out"]
                mm["cr"] += mv["cr"]; mm["cw"] += mv["cw"]; mm["cost"] += mv["cost"]
            for mn, efforts in (day.get("model_efforts") or {}).items():
                target_efforts = agg["model_efforts"].setdefault(mn, {})
                for effort, usage in efforts.items():
                    target = target_efforts.setdefault(
                        effort, {"in": 0, "out": 0, "cr": 0, "cw": 0})
                    for field in ("in", "out", "cr", "cw"):
                        target[field] += usage.get(field, 0)
            # 会话数只能来自现存日志(被清日志无从归属)
            try:
                d = date.fromisoformat(dk)
            except ValueError:
                continue
            for k in classify(d):
                bucket[k]["sessions"].add(f)
    # 项目名随天入账本(list 会被 snapshot 原样存档;_ledger_day_total 只加数值,不受影响),
    # 日志被清理后回顾页仍能回答"那天在干什么"。
    for dk, names in day_projects.items():
        live_days[dk]["projects"] = sorted(names)[:3]
    return live_days


def _claude_channel_into(bucket, tool, fc, live_days, classify):
    """把某渠道经账本对账后的按日值写进 range 桶。"""
    for dk, day in ledger_reconcile(tool, live_days, _ledger_file_sources(
            fc, lambda path, _: os.path.basename(path))).items():
        try:
            d = date.fromisoformat(dk)
        except ValueError:
            continue
        for k in classify(d):
            b = bucket[k]
            b["in"] += day.get("in", 0); b["out"] += day.get("out", 0)
            b["cr"] += day.get("cr", 0); b["cw"] += day.get("cw", 0)
            b["cost"] += day.get("cost", 0.0)
            for mn, mv in (day.get("models") or {}).items():
                mm = b["models"].setdefault(mn, {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
                mm["in"] += mv.get("in", 0); mm["out"] += mv.get("out", 0)
                mm["cr"] += mv.get("cr", 0); mm["cw"] += mv.get("cw", 0)
                mm["cost"] += mv.get("cost", 0.0)
            for mn, efforts in (day.get("model_efforts") or {}).items():
                target_efforts = b["model_efforts"].setdefault(mn, {})
                for effort, usage in efforts.items():
                    target = target_efforts.setdefault(
                        effort, {"in": 0, "out": 0, "cr": 0, "cw": 0})
                    for field in ("in", "out", "cr", "cw"):
                        target[field] += usage.get(field, 0)


def _claude_current_session(fc, cur_file):
    """当前会话 = 最近修改的那个文件的所有天之和(按渠道各算一遍)。"""
    cur = {"in": 0, "out": 0, "cr": 0, "cw": 0,
           "name": os.path.basename(cur_file)[:8] if cur_file else "-"}
    entry = fc.get(cur_file) if cur_file else None
    if entry:
        for day in entry.get("days", {}).values():
            cur["in"] += day["in"]; cur["out"] += day["out"]
            cur["cr"] += day["cr"]; cur["cw"] += day["cw"]
    return cur


def _claude_scan_result(buckets, curs):
    empty = {"in": 0, "out": 0, "cr": 0, "cw": 0, "name": "-"}
    return {"ranges": buckets["claude"], "cur": curs.get("claude") or dict(empty),
            "desktop_ranges": buckets["claude_desktop"],
            "desktop_cur": curs.get("claude_desktop") or dict(empty)}
```

3c. `scan_claude`（≈1732-1945）整体替换为：

```python
def scan_claude(bounds, cache):
    """Claude 一次解析,按响应特征拆成两个渠道。

    - claude        —— 中继/第三方 API 通道(如 OpenCode)
    - claude_desktop —— 官方通道(订阅/官方 API);订阅额度读数挂在它上面
    分类只看每条记录自身特征(_claude_usage 的 official),与入口(entrypoint)无关。
    """
    file_caches = {key: cache.setdefault(key, {}) for key, _official in _CLAUDE_CHANNELS}
    # 与渠道无关的「已解析」索引:{文件: [签名, 解析器版本]}。渠道条目只在有事件时存在,
    # 所以两个渠道都没事件的文件(空会话)必须靠这份索引才不会每轮重读。
    parse_sigs = cache.setdefault("_claude_parse_sigs", {})
    changed = False
    if cache.get("_pricing_changed"):
        changed_models = cache.get("_pricing_changed_models") or []
        for fc in file_caches.values():
            if _reprice_claude_events(fc, changed_models):
                changed = True
    buckets = {key: _claude_empty_ranges() for key, _official in _CLAUDE_CHANNELS}
    cur_file, cur_mtime = None, -1.0
    if not os.path.isdir(CLAUDE_DIR):
        for fc in file_caches.values():
            if fc:
                fc.clear()
                changed = True
        if parse_sigs:
            parse_sigs.clear()
            changed = True
        if changed:
            cache["_dirty"] = True
        return _claude_scan_result(buckets, {})

    today_d = bounds["today"].date()
    yest_d = bounds["yesterday"].date()
    week_d = bounds["week"].date()
    lw_start_d = bounds["last_week"].date()
    lw_end_d = bounds["last_week_end"].date()
    month_d = bounds["month"].date()
    year_d = bounds["year"].date()

    stale = set().union(*(set(fc) for fc in file_caches.values()))

    for f in glob.glob(os.path.join(CLAUDE_DIR, "**", "*.jsonl"), recursive=True):
        stale.discard(f)
        try:
            st = os.stat(f)
        except OSError:
            continue
        mtime, size = st.st_mtime, st.st_size
        if mtime > cur_mtime:
            cur_mtime = mtime
            cur_file = f
        sig = f"{mtime}:{size}"
        entries = [fc.get(f) for fc in file_caches.values()]
        # 过期判定:解析索引的签名/版本对不上(新文件、内容变了、解析器升级),或任一现存
        # 渠道条目过期(别的进程写过旧格式)。渠道侧缺条目不算过期 —— 那是「该渠道无事件」的正常态。
        if (parse_sigs.get(f) != [sig, _CLAUDE_PARSER_VERSION]
                or any(entry is not None
                       and (entry.get("sig") != sig
                            or entry.get("parser_version") != _CLAUDE_PARSER_VERSION)
                       for entry in entries)):
            events = []
            proj = None
            try:
                with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                    for line_number, line in enumerate(fh, 1):
                        if '"usage"' not in line:
                            continue
                        u = _claude_usage(line, want_dt=True)
                        if not u:
                            continue
                        events.append({
                            "in": u["in"], "out": u["out"], "cr": u["cr"], "cw": u["cw"],
                            "cw5": u.get("cw5"), "cw1": u.get("cw1"),
                            "cost": u["cost"], "model": u.get("model") or "unknown",
                            "effort": u.get("effort") or "未记录",
                            "cwd": u.get("cwd"), "mid": u.get("mid"),
                            "request_id": u.get("request_id"), "event_id": u.get("event_id"),
                            "sidechain": bool(u.get("sidechain")), "timestamp": u["dt"].isoformat(),
                            "line": line_number, "official": u.get("official") is True,
                        })
                        if proj is None and u.get("cwd"):
                            proj = u["cwd"]
            except OSError:
                continue
            split = {}
            for official in (False, True):
                own = [event for event in events if event["official"] is official]
                if own:
                    split[official] = [event for _source, event in
                                       _dedupe_claude_events((f, item) for item in own)]
            for key, official in _CLAUDE_CHANNELS:
                own = split.get(official)
                if own:
                    file_caches[key][f] = {"sig": sig, "events": own, "proj": proj,
                                           "parser_version": _CLAUDE_PARSER_VERSION}
                else:
                    file_caches[key].pop(f, None)
            parse_sigs[f] = [sig, _CLAUDE_PARSER_VERSION]
            changed = True

    for path in stale:
        if parse_sigs.pop(path, None) is not None:
            changed = True
        for fc in file_caches.values():
            if fc.pop(path, None) is not None:
                changed = True

    for fc in file_caches.values():
        if _claude_refresh_aggregates(fc):
            changed = True

    if changed:
        cache["_dirty"] = True

    def classify(d):
        ks = ["all"]
        if d == today_d: ks.append("today")
        if d == yest_d: ks.append("yesterday")
        if d >= week_d: ks.append("week")
        if lw_start_d <= d < lw_end_d: ks.append("last_week")
        if d >= month_d: ks.append("month")
        if d >= year_d: ks.append("year")
        return ks

    live = {key: _claude_live_days(file_caches[key], classify, buckets[key])
            for key, _official in _CLAUDE_CHANNELS}
    _migrate_claude_ledger_split(live["claude_desktop"])
    for key, _official in _CLAUDE_CHANNELS:
        _claude_channel_into(buckets[key], key, file_caches[key], live[key], classify)
    curs = {key: _claude_current_session(file_caches[key], cur_file)
            for key, _official in _CLAUDE_CHANNELS}
    return _claude_scan_result(buckets, curs)
```

> 说明：`_migrate_claude_ledger_split` 在 Task 3 落地。为了让本任务可独立通过测试，**本步先加一个空实现**放在 `_claude_scan_result` 之前：
> ```python
> def _migrate_claude_ledger_split(desktop_days):
>     """Task 3 落地：把账本 claude 里官方通道的存量份额挪到 claude_desktop。"""
>     return False
> ```
> Task 3 会把它替换成真实实现（同签名）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（21 项）。

- [ ] **Step 5: 真机冒烟（只读，确认数字对得上）**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
cache = c._load_scan_cache()
r = c.scan_claude(c.range_bounds(), cache)
tok = lambda b: b["in"] + b["out"] + b["cr"] + b["cw"]
out = {"relay_all": tok(r["ranges"]["all"]), "desktop_all": tok(r["desktop_ranges"]["all"]),
       "relay_today": tok(r["ranges"]["today"]), "desktop_today": tok(r["desktop_ranges"]["today"])}
path = os.path.join(os.environ["TEMP"], "tokei_task2.txt")
open(path, "w", encoding="utf-8").write(json.dumps(out, indent=1))
print(path)
PY
```
Expected：`desktop_all` ≈ 1,900 万（官方通道）；`relay_all` ≈ 21 亿；两者之和 ≈ Task 1 基线的 `all`。

- [ ] **Step 6: 行尾与状态自查（不提交）**

```bash
cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py && git status --short
```

---

### Task 3: 账本拆分与一次性迁移

**Files:**
- Modify: `windows/tokei_windows/collector.py`（把 Task 2 的 `_migrate_claude_ledger_split` 空实现替换为真实实现；常量放在 `_CLAUDE_CHANNELS` 旁）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: Task 2 的 `file_caches` / `live["claude_desktop"]`；账本 `_load_ledger()`、`_load_ledger_from_disk()`、`_save_ledger()`、`_ledger_values(..., subtract=True)`、`_acquire_file_lock` / `_release_file_lock`。
- Produces: `_migrate_claude_ledger_split(desktop_days) -> bool`；账本顶层键 `claude_split = 2`（已完成迁移的标记）。

> **中间态安全性（Task 2 之后、本任务之前）**：`tools["claude"]` 的旧存档不会被 Task 2 改动 —— 按文件来源的合并里，只含中继的候选快照 token 更少、判定为“不更优”，旧混合存档被保留；`tools["claude_desktop"]` 此时记的是官方通道实测值，与迁移里要减掉的量同源，所以即使在这个窗口里真机跑过一次，迁移后总数依然自洽。

- [ ] **Step 1: 写失败测试**

在 `ClaudeChannelScanTests` 之后插入：

```python
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.ClaudeLedgerSplitMigrationTests -v`
Expected: FAIL — `claude_split` 缺失、`claude[day]["in"] == 100`、`claude_desktop` 键不存在。

- [ ] **Step 3: 实现**

把 Task 2 的空实现整体替换为（并加常量）：

```python
# 账本一次性迁移:把 claude 里官方通道的存量份额挪到 claude_desktop。
_CLAUDE_SPLIT_MIGRATION = 2


def _migrate_claude_ledger_split(desktop_days):
    """一次性迁移:从旧混合存档的 claude 里减掉官方通道份额。

    桌面份额用本次扫描的实测值逐日相减;减法走 _ledger_values(..., subtract=True) ——
    它会跳过 _sources,于是被改过的天退化为「聚合 + 残差」,随后的正常对账按现存日志
    重建来源。日志已被清理的天扫不到实测值,份额减不掉,保留在中继渠道(已知偏差)。
    直接改磁盘并让内存缓存失效,避免 flush 时旧来源把减掉的量又合并回来。
    """
    if not desktop_days:
        return False
    if _load_ledger().get("claude_split") == _CLAUDE_SPLIT_MIGRATION:
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
        fresh = _load_ledger_from_disk()
        if fresh.get("claude_split") == _CLAUDE_SPLIT_MIGRATION:
            return False
        days = fresh.setdefault("tools", {}).setdefault("claude", {})
        for dk, desktop_day in desktop_days.items():
            stored = days.get(dk)
            if not isinstance(stored, dict):
                continue
            payload = {field: desktop_day.get(field, 0)
                       for field in ("in", "out", "cr", "cw", "cost")}
            payload["models"] = desktop_day.get("models") or {}
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
            finally:
                os.close(lock_fd)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（23 项）。

- [ ] **Step 5: 真机迁移与守恒核对**

先备份真账本（迁移会改它，这份备份是唯一回退手段）：

```bash
cp "$USERPROFILE/.tokei/ledger.json" "$USERPROFILE/.tokei/ledger.json.pre-claude-split.bak" && \
cp "$USERPROFILE/.tokei/quota_cycles.json" "$USERPROFILE/.tokei/quota_cycles.json.pre-claude-split.bak" && \
ls -la "$USERPROFILE/.tokei/" | grep pre-claude-split
```

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
c.compute()                     # 触发迁移 + 落盘
ledger = json.load(open(os.path.join(os.environ["USERPROFILE"], ".tokei", "ledger.json"),
                        encoding="utf-8"))
base = json.load(open(os.path.join(os.environ["TEMP"], "tokei_split_baseline.json"),
                      encoding="utf-8"))

def total(tool):
    return sum(int(day.get(field, 0) or 0)
               for day in (ledger["tools"].get(tool) or {}).values()
               for field in ("in", "out", "cr", "cw"))

out = {"claude_split": ledger.get("claude_split"), "relay": total("claude"),
       "desktop": total("claude_desktop"), "baseline_all": base["all"]}
path = os.path.join(os.environ["TEMP"], "tokei_task3.txt")
open(path, "w", encoding="utf-8").write(json.dumps(out, indent=1))
print(path)
PY
```
Expected（读 `%TEMP%\tokei_task3.txt`）：`claude_split == 2`；`relay + desktop ≈ baseline_all`（容差 ≤ 1%；被清理日志的天无法归属会造成少量偏差）。若不满足，**停下来**核对是不是迁移把中继份额也减掉了。

- [ ] **Step 6: 行尾与状态自查（不提交）**

```bash
cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py && git status --short
```

---

### Task 4: `compute()` 输出契约与额度历史换键

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`compute()` ≈12809、12889-12890、12928-12938；`_QUOTA_TOOLS` ≈14926；`_quota_day_tokens` ≈14975；`_quota_claude_events` ≈15032；`_quota_tool_reading` ≈15128；`_quota_cycle_specs` ≈15273；`_merge_quota_anchors` ≈15217；`build_quota_detail` ≈15341-15350）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: Task 2 的 `desktop_ranges` / `desktop_cur`；Task 1-3 的账本工具键 `claude_desktop`。
- Produces: `compute()["claude_desktop"]`（含 `q5/q5_reset/q7/q7_reset/qf/qf_reset/q_updated/q5_stale/q7_stale/qf_stale`、`ranges`、`session_name/session_total`）；`compute()["claude"]` 不再带额度字段；`_QUOTA_TOOLS = (("claude_desktop", "cd"), ("codex", "x"), ("grok", "g"))`；`_rename_legacy_quota_anchors(anchors) -> bool`；`_QUOTA_TOOL_ALIASES = {"claude": "claude_desktop"}`；`_quota_claude_events(cache=None, cache_key="claude_desktop")`。

- [ ] **Step 1: 写失败测试**

在 `ClaudeLedgerSplitMigrationTests` 之后插入：

```python
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.ClaudeQuotaChannelTests -v`
Expected: FAIL — `AttributeError: module ... has no attribute '_rename_legacy_quota_anchors'`，`_quota_claude_events()` 收到意外的 `cache_key`。

- [ ] **Step 3: 实现**

3a. `compute()`：`cranges` 之后加一行（≈12809）：

```python
    cranges = {k: claude_range(cc["ranges"][k]) for k in RANGE_KEYS}
    cdranges = {k: claude_range(cc["desktop_ranges"][k]) for k in RANGE_KEYS}
```

`cur` 块（≈12889-12890）之后加：

```python
    cur = cc["cur"]
    cur_total = cur["in"] + cur["out"] + cur["cr"] + cur["cw"]
    desktop_cur = cc["desktop_cur"]
    desktop_cur_total = (desktop_cur["in"] + desktop_cur["out"]
                         + desktop_cur["cr"] + desktop_cur["cw"])
```

`result` 的 claude 块（≈12929-12938）替换为：

```python
        "claude": {
            "ranges": cranges,
            "session_name": cur["name"], "session_total": cur_total,
        },
        # 官方通道(订阅/官方 API):订阅读数只挂在这里,中继通道没有订阅计划。
        "claude_desktop": {
            "ranges": cdranges,
            "session_name": desktop_cur["name"], "session_total": desktop_cur_total,
            "q5": plan.get("q5"), "q5_reset": plan.get("q5_reset"),
            "q7": plan.get("q7"), "q7_reset": plan.get("q7_reset"),
            "qf": plan.get("qf"), "qf_reset": plan.get("qf_reset"),
            "q_updated": plan.get("q_updated"),
            "q5_stale": plan.get("q5_stale"), "q7_stale": plan.get("q7_stale"),
            "qf_stale": plan.get("qf_stale"),
        },
```

3b. 额度工具键与别名（≈14926）：

```python
# 订阅额度属于官方通道:工具键是 claude_desktop,不是混合口径的 claude。
_QUOTA_TOOLS = (("claude_desktop", "cd"), ("codex", "x"), ("grok", "g"))
# 旧版本 peer 的额度读数与锚点还挂在 claude 键上,读到要认。
_QUOTA_TOOL_ALIASES = {"claude": "claude_desktop"}
```

3c. `_quota_day_tokens`（≈14979）：`if tool == "claude":` → `if tool in ("claude", "claude_desktop"):`

3d. `_quota_claude_events`（≈15032）：签名与取缓存改为

```python
def _quota_claude_events(cache=None, cache_key="claude_desktop"):
    """去重后的 Claude 事件 → [(epoch, 本地日, tokens)]。去重逻辑与 scan_claude 一致。"""
    file_cache = (cache if cache is not None else _load_scan_cache()).get(cache_key) or {}
```
（函数体其余不变）

3e. `_quota_tool_reading`（≈15128-15148）：**删掉原来的第一行 `data = (source or {}).get(tool) or {}`**，把整个函数替换为下面这版（三分支各自取数据，官方通道带旧 peer 回退）：

```python
def _quota_tool_reading(source, tool):
    """从一份 payload/同步快照里取 (used_pct, reset_epoch, 读数时间);取不到返回 None。"""
    source = source or {}
    if tool == "claude_desktop":
        # 新版本把订阅读数放在 claude_desktop;旧版本 peer 还在 claude 键上。
        data = source.get("claude_desktop") or source.get("claude") or {}
        if data.get("q7_stale"):
            return None
        used, reset, updated = data.get("q7"), data.get("q7_reset"), data.get("q_updated")
    elif tool == "codex":
        data = source.get(tool) or {}
        if data.get("pw_stale"):
            return None
        used, reset, updated = data.get("pw"), data.get("rw"), data.get("q_updated")
    else:
        data = source.get(tool) or {}
        # Grok 也可能是月套餐,月窗口长度不定又没有数据可验证,先只认周。
        if data.get("stale") or data.get("window") != "week":
            return None
        used, reset, updated = data.get("pct"), data.get("reset"), data.get("q_updated")
```

3f. 锚点迁移助手（放在 `_merge_quota_anchors` 之前）：

```python
def _rename_legacy_quota_anchors(anchors):
    """旧锚点是按 claude 记的,搬到 claude_desktop;幂等,返回是否有改动。"""
    changed = False
    for legacy, current in _QUOTA_TOOL_ALIASES.items():
        rows = anchors.get(legacy)
        if isinstance(rows, list) and rows and not anchors.get(current):
            anchors[current] = rows
        if legacy in anchors:
            anchors.pop(legacy)
            changed = True
    return changed
```

`_merge_quota_anchors`：把入参的工具名过一遍别名表 ——

```python
    known = {tool for tool, _key in _QUOTA_TOOLS}
    for tool, rows in (incoming or {}).items():
        tool = _QUOTA_TOOL_ALIASES.get(tool, tool)
        if tool not in known or not isinstance(rows, list):
            continue
```

3g. `_quota_cycle_specs`（≈15282）开头：

```python
    anchors = _load_quota_anchors()
    dirty = _rename_legacy_quota_anchors(anchors)
```
（删掉原来的 `dirty = False`，其余不变）

3h. `build_quota_detail` 的事件来源（≈15348）：

```python
            events[tool] = (_quota_claude_events(cache, "claude_desktop")
                            if tool == "claude_desktop"
                            else _quota_codex_events(codex_spans, cache) if tool == "codex"
                            else None)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（26 项）。

- [ ] **Step 5: 真机核对额度周期**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
from datetime import datetime
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
d = c.compute()
fmt = lambda e: datetime.fromtimestamp(e).strftime("%m-%d %H:%M") if e else None
lines = [f"claude_desktop q5={d['claude_desktop'].get('q5')} q7={d['claude_desktop'].get('q7')}"
         f" q7_reset={fmt(d['claude_desktop'].get('q7_reset'))}",
         f"claude 带额度字段={sorted(k for k in d['claude'] if k.startswith('q'))}",
         # 同步快照沿用同一份 compute() 输出,新键自动进快照(设计 §4.5,无需改代码)
         f"sync 载荷 claude 键={sorted(k for k in c._sync_safe_usage_payload(d) if k.startswith('claude'))}"]
for cy in c.build_quota_detail()["cycles"]:
    lines.append(f"cycle {cy['tool']} {fmt(cy['start'])}..{fmt(cy['end'])} "
                 f"used={cy['used_pct']}% tokens={cy['tokens']:,} current={cy['current']}")
path = os.path.join(os.environ["TEMP"], "tokei_task4.txt")
open(path, "w", encoding="utf-8").write("\n".join(lines))
print(path)
PY
```
Expected：`claude` 的额度字段为空列表；sync 载荷里 `claude` 与 `claude_desktop` 两个键都在；周期列表里 Claude 那条的 `tokens` 从 8 亿量级掉到 **千万量级（≈17-20M）**，`used` 与 4% 量级相符。
- `claude_desktop` 的 q5/q7/qf 在本机预计为 `None`：额度数据源（Claude Desktop 的 Chromium 缓存）随该应用被卸载而消失，用户 2026-09-28 裁决「暂时不管额度」（本机 CLI 走 OpenCode 中继，没有官方凭据）。键保留、值为 None 是预期结果，不是缺陷；将来接通数据源时结构不变。

- [ ] **Step 6: 行尾与状态自查（不提交）**

```bash
cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py && git status --short
```

---

### Task 5: 界面卡片、额度条与额度历史标题

**Files:**
- Modify: `windows/tokei_windows/bridge.py`（`PROVIDERS` ≈21-22；`_build_cards` 额度分支 ≈670；`cost_fields` ≈309-313）
- Modify: `windows/tokei_windows/qml/QuotaCycleCard.qml`（≈24、≈46）
- 注意：`bridge.py` 的 `_make_summary` 里那段额度文字仍只显示 Codex（本次不改，避免撑破 127 字符上限）；飘窗/托盘按 `PROVIDERS`/`cards` 遍历，新卡片自动出现。
- Modify: `windows/scripts/smoke_ui.py`（夹具 ≈40-72）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: Task 4 的 `compute()` 契约。
- Produces: 总览/托盘/浮窗出现第二张 Claude 卡片；额度条只挂在 `claude_desktop`；额度历史卡片显示「Claude Code Desktop」。

- [ ] **Step 1: 写失败测试（并改掉两条旧测试）**

改旧测试 ①：`test_claude_quota_values_are_used_percentages` 的快照键从 `"claude"` 改为 `"claude_desktop"`（卡片查找键同步改）：

```python
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
```

改旧测试 ②：`test_cards_mark_expired_quota_values` 同样换键（额度只挂桌面卡片），名字一并改成 `test_desktop_card_marks_expired_quota_values`：

```python
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
```

新增：

```python
    def test_only_the_desktop_card_carries_subscription_bars(self) -> None:
        state = SimpleNamespace(
            _snapshot={
                "claude": {"ranges": {"today": {"in": 1000, "out": 500, "cost": 0.12}}},
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.DashboardPresentationTests -v`
Expected: FAIL — `KeyError: 'claude_desktop'`（卡片不存在的 provider 直接不渲染）。

- [ ] **Step 3: 实现**

3a. `bridge.py` `PROVIDERS` 第一行之后插入：

```python
PROVIDERS = [
    ("claude", "Claude Code", "#eb8566"),
    # 官方通道(订阅/官方 API):中继通道没有订阅计划,额度条只挂这张卡片。
    ("claude_desktop", "Claude Code Desktop", "#f2b06a"),
```

3b. `_build_cards` 的额度分支：`if key == "claude":` → `if key == "claude_desktop":`（分支体内字段名不变）。

3c. `_RefreshJob.run` 的 `cost_fields`（≈309）加入 `"claude_desktop"`：

```python
            cost_fields = (
                "claude", "claude_desktop", "codex", "codex_reserve", "gemini", "grok", "zcode",
```

3d. `qml/QuotaCycleCard.qml` 第 24 行标题映射：

```qml
                text: root.cycle.tool === "claude_desktop" ? "Claude Code Desktop" : root.cycle.tool === "claude" ? "Claude Code" : root.cycle.tool === "codex" ? "Codex" : root.cycle.tool
```

第 46 行进度条颜色：

```qml
                color: root.cycle.tool === "claude" ? "#f09578" : root.cycle.tool === "claude_desktop" ? "#f2b06a" : "#79aef7"
```

3e. `scripts/smoke_ui.py` 夹具：`claude` 快照去掉 `q5/q7/qf`，新增 `claude_desktop`：

```python
        "claude": {
            "ranges": {"today": {"in": 32500, "out": 5700, "cached": 21800, "cost": 0.41}},
        },
        "claude_desktop": {
            "ranges": {"today": {"in": 4200, "out": 900, "cost": 0.13}},
            "q5": 38,
            "q7": 64,
            "qf": 12,
        },
```
并把 `store._quota_history["cycles"]` 的第一条 `"tool": "claude"` 改为 `"tool": "claude_desktop"`，另加一条中继周期的历史条目：

```python
            {"tool": "claude_desktop", "current": True, "used_pct": 62.0, "tokens": 75200, "tokens_display": "75,200"},
            {"tool": "codex", "current": False, "used_pct": 41.5, "tokens": 39400, "tokens_display": "39,400"},
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（27 项）。

- [ ] **Step 5: 离屏截图核对**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe scripts/smoke_ui.py
```
Expected: 无 `QML root object was not created` / `No frame for page` 输出；用图片查看器打开 `windows/dist/preview-overview.png`（应看到「Claude Code」与「Claude Code Desktop」两张卡片，后者带 3 条额度条）和 `preview-quotas.png`（标题为 Claude Code Desktop）。

- [ ] **Step 6: 自查（不提交）**

```bash
cd "E:/tokei-windows" && git status --short && git diff --stat windows/tokei_windows/bridge.py windows/tokei_windows/qml/QuotaCycleCard.qml windows/scripts/smoke_ui.py
```

---

### Task 6: 趋势/模型排行/项目足迹/年度回顾

**Files:**
- Modify: `windows/tokei_windows/collector.py`（`build_daily_costs` 的 `_empty` ≈13791-13812、claude 循环 ≈13814-13830、`_LEDGER_COST_COLUMNS` ≈14169-14172、`daily` 输出 ≈14219-14257；`_PROJECT_SOURCES` ≈15409-15419；`build_wrapped` 的 Claude 循环 ≈14393-14416）
- Test: `windows/tests/test_windows_client.py`

**Interfaces:**
- Consumes: Task 2 的两个缓存命名空间。
- Produces: `dashboard.daily[].claude_desktop` 与 `cd_in/cd_out/cd_cr/cd_cw`、`total` 含新通道、模型排行出现 `… (Claude Desktop)` 行、项目足迹出现 `claude_desktop` 贡献、年度回顾总额含新通道。

- [ ] **Step 1: 写失败测试**

在 `ClaudeQuotaChannelTests` 之后插入：

```python
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
        self.assertAlmostEqual(row["total"], 2.5, places=2)
        names = {model["name"] for model in result["models"]}
        # nice_model("claude-opus-5-5") == "Opus 5.5";中继模型名保持原样
        self.assertIn("Opus 5.5 (Claude Desktop)", names)
        self.assertIn("Deepseek V4.1 Flash", names)

    def test_project_footprint_includes_the_desktop_channel(self) -> None:
        rows = list(collector._project_contributions(self._cache()))
        desktop_rows = [row for row in rows if row["tool"] == "claude_desktop"]
        self.assertEqual(len(desktop_rows), 1)
        self.assertEqual(desktop_rows[0]["tokens"], 98)
        self.assertEqual(desktop_rows[0]["label"], "Claude Code Desktop")

    def test_yearly_review_totals_include_the_desktop_channel(self) -> None:
        wrapped = collector.build_wrapped("all", refresh=False, _cache=self._cache())
        self.assertEqual(wrapped["total_tokens"], 111)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client.ClaudeChannelPagesTests -v`
Expected: FAIL — `KeyError: 'claude_desktop'`（daily 行）/ 项目行缺失 / 总额只有 13。

- [ ] **Step 3: 实现**

3a. `build_daily_costs` 的 `_empty` 增加成本列与 token 列：

```python
    _empty = lambda: {"claude": 0.0, "claude_desktop": 0.0, "codex": 0.0, "codex_reserve": 0.0,
```
并在 `"c_in": 0, "c_out": 0, "c_cr": 0, "c_cw": 0,` 之后加一行：

```python
                       "cd_in": 0, "cd_out": 0, "cd_cr": 0, "cd_cw": 0,
```

3b. 现有 Claude 循环之后，新增官方通道循环：

```python
    for fp, entry in cache.get("claude_desktop", {}).items():
        for dk, day in entry.get("days", {}).items():
            if cutoff and dk < cutoff:
                continue
            d = days.setdefault(dk, _empty())
            d["claude_desktop"] += day.get("cost", 0)
            d["cd_in"] += day.get("in", 0); d["cd_out"] += day.get("out", 0)
            d["cd_cr"] += day.get("cr", 0); d["cd_cw"] += day.get("cw", 0)
            _add_day_tokens(d, dk, "claude_desktop",
                            day.get("in", 0) + day.get("out", 0) + day.get("cr", 0) + day.get("cw", 0))
            d["sessions"] += 1
            for mn, mv in day.get("models", {}).items():
                # 中继通道的模型名保持原样,官方通道加后缀,避免同一模型两行混在一起。
                nm = f"{nice_model(mn)} (Claude Desktop)"
                m = models.setdefault(nm, {"cost": 0.0, "in": 0, "out": 0, "cr": 0, "cw": 0,
                                          "tool": "claude_desktop"})
                m["cost"] += mv.get("cost", 0)
                m["in"] += mv.get("in", 0); m["out"] += mv.get("out", 0)
                m["cr"] += mv.get("cr", 0); m["cw"] += mv.get("cw", 0)
```

3c. `_LEDGER_COST_COLUMNS` 加入 `"claude_desktop"`：

```python
    _LEDGER_COST_COLUMNS = frozenset((
        "claude", "claude_desktop", "codex", "codex_reserve", "gemini", "grok", "hermes",
        "openclaw", "zcode",
        "mimocode", "devin", "pi", "workbuddy", "workbuddy_ai", "codebuddy", "deepseek_harness",
        "opencode", "qwencode", "musecode", "cmdcode"))
```

3d. `daily` 输出：`"claude": round(v["claude"], 2),` 之后加 `"claude_desktop": round(v["claude_desktop"], 2),`；`total` 表达式加 `+ v["claude_desktop"]`；`"c_in": v["c_in"], "c_out": v["c_out"], "c_cr": v["c_cr"], "c_cw": v["c_cw"],` 之后加：

```python
              "cd_in": v["cd_in"], "cd_out": v["cd_out"],
              "cd_cr": v["cd_cr"], "cd_cw": v["cd_cw"],
```

3e. `_PROJECT_SOURCES` 第一行之后加：

```python
    ("claude",       "Claude",          True,  "entry", "token_total"),
    ("claude_desktop", "Claude Code Desktop", True, "entry", "token_total"),
```

3f. `build_wrapped` 的 Claude 循环：把现有循环体改为按渠道循环（把原来的 `fc = cache.get("claude", {})` 与随后的 `for f, entry in fc.items():` 循环替换为）：

```python
    # --- Claude (有 hours / proj / models);两个渠道各跑一遍,中继名保持原样 ---
    for cache_key, suffix in (("claude", ""), ("claude_desktop", " (Claude Desktop)")):
        fc = cache.get(cache_key, {})
        for f, entry in fc.items():
            if not isinstance(entry, dict):
                continue
            for day_key, day_hours in entry.get("day_hours", {}).items():
                if not cutoff or day_key >= cutoff:
                    add_hours(day_key, day_hours)
            proj_path = entry.get("proj") or ""
            proj = os.path.basename(proj_path.rstrip("/")) or "?"
            for dk, day in entry.get("days", {}).items():
                if cutoff and dk < cutoff:
                    continue
                tok = token_total(day)
                day_tokens[dk] = day_tokens.get(dk, 0) + tok
                day_cost[dk] = day_cost.get(dk, 0.0) + day.get("cost", 0)
                pt = proj_tok.setdefault(proj, [0, 0.0])
                pt[0] += tok; pt[1] += day.get("cost", 0)
                day_projs.setdefault(dk, set()).add(proj)
                weekday[date.fromisoformat(dk).weekday()] += tok
                for mn, mv in day.get("models", {}).items():
                    nm = f"{nice_model(mn)}{suffix}"
                    model_tok[nm] = model_tok.get(nm, 0) + token_total(mv)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v`
Expected: PASS（30 项）。

- [ ] **Step 5: 真机核对仪表盘**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
cache = c._load_scan_cache()
dash = c.build_daily_costs("all", refresh=False, _cache=cache)
last = dash["daily"][-1]
wrapped = c.build_wrapped("all", refresh=False, _cache=cache)
projects = c.build_projects(refresh=False)
lines = [f"daily[{last['date']}] relay={last['claude']} desktop={last['claude_desktop']} total={last['total']}",
         f"models(claude*): " + "; ".join(f"{m['name']}={m['tokens']:,}"
                                          for m in dash["models"] if "laude" in m["name"])[:400],
         f"wrapped.total_tokens={wrapped['total_tokens']:,}",
         f"projects with claude_desktop: " + "; ".join(
             p["name"] for p in projects if any("Claude Code Desktop" in str(t) for t in p.get("tools", [])))[:300]]
path = os.path.join(os.environ["TEMP"], "tokei_task6.txt")
open(path, "w", encoding="utf-8").write("\n".join(lines))
print(path)
PY
```
Expected：最近一天的 `desktop` 非零且小于 `relay`；模型列表里既有中继模型也有 `… (Claude Desktop)`；项目足迹至少有一个项目带 `Claude Code Desktop`。

- [ ] **Step 6: 行尾与状态自查（不提交）**

```bash
cd "E:/tokei-windows" && git diff --stat windows/tokei_windows/collector.py && git status --short
```

---

### Task 7: 真机验收与打包

**Files:**
- Verify: 全仓库（不改代码；除本节列出的临时脚本，恢复现场）
- Reference: `docs/superpowers/specs/2026-09-28-claude-channel-split-design.md` §7.2

**Interfaces:**
- Consumes: Task 1-6 的全部产物；Task 1 的基线文件 `%TEMP%\tokei_split_baseline.json`。
- Produces: 验收结论（数字 + 截图 + exe），供用户决定是否提交。

- [ ] **Step 1: 全量测试 + 源码端到端**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe -m unittest tests.test_windows_client -v
```

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe - <<'PY'
import json, os, sys
from datetime import datetime
sys.path.insert(0, r"E:\tokei-windows\windows")
from tokei_windows import collector as c
d = c.compute()
tok = lambda b: b["in"] + b["out"] + b["cr"] + b["cw"]
ledger_path = os.path.join(os.environ["USERPROFILE"], ".tokei", "ledger.json")
cur = json.load(open(ledger_path, encoding="utf-8"))
bak = json.load(open(ledger_path + ".pre-claude-split.bak", encoding="utf-8"))

def day_total(tools, day):
    return tok((tools.get("claude") or {}).get(day) or {}) + tok((tools.get("claude_desktop") or {}).get(day) or {})

lines = [f"claude_split={cur.get('claude_split')}",
         f"relay_all={tok(d['claude']['ranges']['all']):,} desktop_all={tok(d['claude_desktop']['ranges']['all']):,}"]
worst = 0.0
for day, mixed in sorted((bak.get("tools") or {}).get("claude", {}).items()):
    before = tok(mixed)
    after = day_total(cur.get("tools") or {}, day)
    delta = (after - before) / before if before else 0.0
    worst = max(worst, abs(delta))
    lines.append(f"  {day}: before={before:,} after={after:,} delta={delta:+.3%}")
lines.append(f"worst per-day delta={worst:.3%}")
detail = c.build_quota_detail()
current = next((cy for cy in detail["cycles"] if cy["tool"] == "claude_desktop" and cy["current"]), None)
lines += [
    f"desktop q5={d['claude_desktop'].get('q5')} q7={d['claude_desktop'].get('q7')}",
    f"claude 额度字段={sorted(k for k in d['claude'] if k.startswith('q'))}",
    (f"cycle current: used={current['used_pct']}% tokens={current['tokens']:,}"
     if current else "no current cycle"),
]
path = os.path.join(os.environ["TEMP"], "tokei_task7.txt")
open(path, "w", encoding="utf-8").write("\n".join(lines))
print(path)
PY
```
Expected：
- 测试 34 项全绿（修复轮再加 1 项则 35）；
- **逐日守恒**：迁移前备份 `*.pre-claude-split.bak` 里每个 `claude` 天 ≈ 现在该天 `claude + claude_desktop` 之和；`worst per-day delta` ≤1%（差来自日志已清理、迁移时扫不到的天；Task 3 实测总差 +0.223%）。**不要**再拿 Task 1 的 `%TEMP%\tokei_split_baseline.json` 做总量对比 —— 那是迁移前的时点值，之后有真实增量流量（约 +1.5%），拿它比会把正常增长误判成错误；
- `desktop_all` ≈ 2,600 万；`claude` 额度字段为空；
- `claude_desktop` 的 q5/q7 为 `None`（数据源已消失，用户裁决暂不接通凭据通道；见 Task 4 Step 5 的说明）；
- 当前周期 `tokens` 在千万量级（≈17-27M），与该周期内官方通道的实测窗口值一致。

- [ ] **Step 2: 界面截图验收**

```bash
cd "E:/tokei-windows/windows" && .venv/Scripts/python.exe scripts/smoke_ui.py
```
逐张打开 `windows/dist/preview-overview.png`、`preview-dashboard.png`、`preview-projects.png`、`preview-quotas.png`：确认两张 Claude 卡片、模型排行里两者都有行、项目足迹有 Claude Code Desktop、额度历史标题正确、界面无错位。

- [ ] **Step 3: 打包**

```bash
cd "E:/tokei-windows/windows" && powershell.exe -NoProfile -File build.ps1
```
Expected: 退出码 0；末尾打印 SHA-256 与 `Built: …dist\Tokei-Windows.exe`（若用户实例在运行，则另存为 `Tokei-Windows-update-<时间戳>.exe`，属正常）。

- [ ] **Step 4: 隔离启动新 exe**

```bash
ISO_W="$(cygpath -w "$TEMP")\\tokei_exe_check"; mkdir -p "$TEMP/tokei_exe_check/Local" "$TEMP/tokei_exe_check/Temp"
cat > "$TEMP/tokei_exe_check/run.ps1" <<EOF
\$env:LOCALAPPDATA = '$ISO_W\\Local'
\$env:TEMP = '$ISO_W\\Temp'
\$env:TMP = '$ISO_W\\Temp'
\$env:QT_QPA_PLATFORM = 'offscreen'
\$p = Start-Process -FilePath 'E:\\tokei-windows\\windows\\dist\\Tokei-Windows.exe' -PassThru
\$p.Id
EOF
powershell.exe -NoProfile -File "$(cygpath -w "$TEMP/tokei_exe_check/run.ps1")" | tr -d '\r'
```
等 30 秒后检查隔离目录里是否出现新的扫描缓存与额度状态文件：

```bash
ls -la "$TEMP/tokei_exe_check/Local/Tokei-Windows/" && \
grep -l "claude_desktop" "$TEMP/tokei_exe_check/Local/Tokei-Windows/"*.json 2>/dev/null; \
grep -o "blockfile_snapshot" "$TEMP/tokei_exe_check/Local/Tokei-Windows/claude_quota_cache.json" 2>/dev/null
```
然后按 PID 结束隔离实例（**不要**动用户自己那个进程）：

```bash
PID_ISO=<上一步打印的 PID>; taskkill //PID "$PID_ISO" //T //F
```

- [ ] **Step 5: 清理临时脚本并汇报**

删除 `%TEMP%\tokei_exe_check`、`%TEMP%\tokei_split_baseline.json`、`%TEMP%\tokei_task*.txt`；跑一次 `git status --short` 确认工作区只有预期的 5 个改动文件（`collector.py`、`bridge.py`、`QuotaCycleCard.qml`、`tests/test_windows_client.py`、`scripts/smoke_ui.py`）加上用户早前的未提交改动与未跟踪文件。

汇报内容：测试数量、守恒核对数字、额度历史数字、截图结论、exe 路径与 SHA-256、**是否建议提交**（提交由用户决定）。
