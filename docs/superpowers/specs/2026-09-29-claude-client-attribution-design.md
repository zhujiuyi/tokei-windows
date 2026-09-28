# Claude 卡片归属改为客户端维度（桌面客户端口径）

- 日期：2026-09-29
- 状态：设计已与用户逐条确认（卡片按客户端统计；额度历史仍只统计官方通道），本文档待用户复核后转实施计划
- 影响模块：`windows/tokei_windows/collector.py`、`windows/tests/test_windows_client.py`
- 不改：`windows/tokei_windows/bridge.py`、`windows/tokei_windows/qml/*`（键名与标题都不变）
- 修订：`2026-09-28-claude-channel-split-design.md` 的 §3（分类判据）与 §4.4（额度事件源）

## 1. 背景

### 1.1 现象

用户现在用 Claude 桌面客户端（本会话客户端），**未登录账号、无订阅**，模型走第三方 API。Tokei 的「Claude Code Desktop」卡片今天没有任何数据（显示「暂无本地数据」），用户判断是「检测不到订阅状态就不统计」。

### 1.2 实测（本机，本地时间 2026-09-29）

按日志逐条统计：

| entrypoint | 模型 | `message.id` / `requestId` | 9-28 判据下归属 | 今日 token |
|---|---|---|---|---|
| `claude-desktop-3p` | deepseek-v4.1-flash | uuid / 无 | 中继通道 | 60,354,436（287 条） |
| `sdk-cli` | deepseek-flash | uuid / 无 | 中继通道 | 6,595,001（59 条） |

扫描缓存（去重后）：`claude` 通道今日 15,306,733 token；`claude_desktop` 通道今日 0，命名空间内只有 2 个文件、全部落在 09-28。

### 1.3 根因

`official` 判据（`msg_` + `req_` + `claude-`）区分的是**计费渠道**，不是**客户端**。桌面客户端在未登录时经第三方 API 出网，日志特征与 CLI 中继完全一样，于是被归到中继命名空间 → 数据全部显示在「Claude Code」卡，「Claude Code Desktop」卡为空。

**不是订阅状态导致的**：代码里没有「无订阅就不统计」的分支，`q5/q7/qf` 取不到只让额度条为空（`bridge.py:672`），token/成本照常统计，9-28 设计 §9.4 也是这么定的。

### 1.4 用户要求（本次裁决）

1. 卡片口径按**客户端**：桌面客户端的用量（含经第三方 API 的部分）都进「Claude Code Desktop」卡。
2. 额度历史页的 Claude 订阅周期**仍只统计官方通道**（保持 9-28 的修复，不让第三方用量重新污染周期 Token）。
3. 没有订阅时照常统计，只有订阅额度条不显示（现状已满足，保持）。

## 2. 目标与非目标

**目标**
- 卡片、趋势与成本、模型排行、项目足迹、年度回顾、浮窗摘要按**客户端**划分 Claude 用量。
- 订阅额度读数与额度历史周期 Token 仍按**官方通道**口径，与卡片口径解耦。
- 界面结构、卡片标题、`PROVIDERS` 键名保持不动。

**非目标**
- 不拆分 Codex。
- 不改 Claude Desktop 缓存（blockfile）的读取逻辑。
- 不新增卡片、不改卡片布局与文案。
- 不追溯无法归属的历史天（沿用 9-28 的已知偏差口径）。

## 3. 分类规则（唯一口径）

```
desktop = entrypoint 以 "claude-desktop" 开头       # 是 → cache["claude_desktop"]，否 → cache["claude"]
official = message.id 以 "msg_" 开头
        且 requestId 以 "req_" 开头
        且 model 以 "claude-" 开头                  # 只服务额度周期（§4.3），不参与卡片归属
```

- 前缀匹配而非枚举，将来 `claude-desktop-*` 新变体自动落桌面命名空间。
- 实测校验：`claude-desktop`、`claude-desktop-3p` 命中；`cli`、`sdk-cli` 不命中。
- 边界（写进代码注释）：这是**客户端**口径，不等于订阅。用官方 API key 或经中继调用 `claude-*` 的用量都跟着客户端走；额度周期只认 `official`，两者互不影响。

## 4. 数据层设计

### 4.1 缓存命名空间（键名不变，含义改变）

| 键 | 旧含义（9-28） | 新含义 |
|---|---|---|
| `cache["claude"]` | 中继通道事件 | **非桌面客户端**事件（任意渠道） |
| `cache["claude_desktop"]` | 官方通道事件 | **桌面客户端**事件（官方 + 第三方） |
| `cache["claude_official"]` | —（新增） | **官方通道**事件（任意客户端），只服务订阅额度，不进任何卡片/趋势/项目/回顾 |

- 第三个命名空间是「订阅口径的派生视图」，因此官方事件会在两个命名空间各存一份（实测 ~300 条，体积可忽略）。这样做是为了让 live 聚合 / 账本对账 / 桶写入全部复用现有按命名空间的通用路径：若改成「读取时跨两个命名空间过滤」，同一文件在两个命名空间都有官方事件时会在按路径聚合的临时结构里互相覆盖。
- 条目结构（`sig`/`events`/`proj`/`days`/`hours`/`day_hours`/`dh`/`parser_version`）与 `_claude_parse_sigs` 索引语义不变。

### 4.2 扫描流程（`scan_claude`）

1. `_claude_usage()` 返回的事件多带 `entrypoint`（原始事实；`desktop` 由前缀判据现算）。
2. 拆分流由「按 `official` 二分」改为三组：非桌面 → `claude`；桌面 → `claude_desktop`；官方 → `claude_official`（与前两组是交集关系）。每组各自在文件内 `_dedupe_claude_events`，其余（过期判定、stale 清理、聚合刷新）不变。
3. 通用循环（`_claude_live_days` / `ledger_reconcile` / `_claude_channel_into`）遍历三个命名空间；`curs` 只算两个卡片命名空间。
4. `_CLAUDE_PARSER_VERSION` 3 → 4：强制重解析，让旧缓存条目按新判据归属。

### 4.3 额度周期专用账本键 `claude_official`

额度周期需要「官方通道逐日 token」，它与桌面卡总量（桌面客户端全部用量）不再是同一个数，因此单独记账：

- 新增账本工具键 `claude_official`：字段结构与其它工具键相同（逐日 `in/out/cr/cw/cost/models` + `_sources`），由 `ledger_reconcile` 正常对账，来源就是 `cache["claude_official"]`（§4.1）。
- 读侧：
  - `_quota_claude_events(cache, _QUOTA_CACHE_KEY)` 从官方命名空间取事件（默认参数换成新键，函数体不变）。
  - `_QUOTA_LEDGER_KEY = {"claude_desktop": "claude_official"}`；`_quota_daily_from_tools()` 按该映射取账本日表。
  - `_QUOTA_TOOLS`、`_QUOTA_TOOL_ALIASES`、`~/.tokei/quota_cycles.json` 锚点键、peer 读数键（`compute()` 输出的 `claude_desktop.q5/q7/qf`）**全部不变**。
- `claude_official` 不进任何卡片、趋势、模型排行、项目足迹、年度回顾、浮窗；`PROVIDERS` 不含它。

### 4.4 一次性迁移（`claude_split: 3`）

账本 `tools["claude"]` 里含 9-28 之后的桌面客户端第三方份额（9-28 的 gen 2 只搬走了官方份额），必须再搬一次，否则高水位合并会把旧值永久留在「Claude Code」卡。

- 复用 gen 2 的机制（`_migrate_claude_ledger_split`）：载荷换成「桌面客户端 ∩ 非 official」的逐日实测，从 `tools["claude"]` 逐日相减（`_ledger_values(..., subtract=True)`）。
- **存量代次决定载荷**：磁盘标记为 2 → 只减「桌面非官方」（官方份额 gen 2 已减过）；标记不存在 → 减**整个桌面份额**（桌面全部），因为那种账本要么是 9-28 之前的混合账本，要么当时 payload 为空（此时桌面官方份额必然为 0，两种载荷等价）。
- 桌面命名空间无需相加：其实时值（已含该份额）高于存档，`ledger_reconcile` 会自动上移；`claude_official` 是全新键，直接从实时值建立，不需要减法。
- 标记值 2 → 3（`_CLAUDE_SPLIT_MIGRATION`）。已落 `claude_split: 2` 的机器会再跑一次 gen 3；已是 3 则跳过。
- 已知偏差（与 gen 2 同口径，写进注释）：日志已被清理、扫不到实测值的天，份额减不掉，保留在 `claude`；被改过的天 `hours`/`model_efforts` 走键并集而非残差重建。

## 5. `compute()` 输出契约

不变：`claude` / `claude_desktop` 的字段名、`ranges` / `desktop_ranges` / `cur` / `desktop_cur` / `q5..qf` 结构与语义保持 9-28 契约；只有 `claude` 与 `claude_desktop` 的**内容口径**变为客户端维度。`_empty_claude()` 不变。

## 6. 界面

- `PROVIDERS`、卡片标题、颜色、排序：不变。「Claude Code」= 非桌面客户端；「Claude Code Desktop」= 桌面客户端。
- 卡片额度条仍只挂在 `claude_desktop`（取不到读数就不显示，现状）。
- 模型行后缀 `(Claude Desktop)` 继续由桌面命名空间产出。
- `bridge.py` 的 `cost_fields` / `_top_tools` / `_make_summary` / 浮窗：不变。

## 7. 测试与验收

### 7.1 单元测试（`windows/tests/test_windows_client.py`）

**改（新口径）**

1. 分类：`claude-desktop` 与 `claude-desktop-3p` 记录 → `claude_desktop` 命名空间；`sdk-cli` 记录 → `claude` 命名空间，两笔 token 不混。
2. 缓存双写：同一文件含两类客户端事件时，两个命名空间各得自己的事件且互斥。
3. 账本迁移：预置 `tools["claude"]` 含桌面第三方份额的混合日（带 `_sources`）+ `claude_split: 2`，跑一次扫描后断言该日 `claude` 值 = 混合 − 桌面非官方实测，`claude_split == 3`，再跑一次不重复扣减。
4. 额度历史：桌面命名空间同时含官方与第三方事件时，周期 token 只含官方部分。
5. 卡片：`claude_desktop` 卡的数据来自桌面命名空间（含第三方），额度条仍在它上面，`claude` 卡不含桌面事件。

**加**

6. 迁移守恒：迁移前后两个卡片命名空间的 token 总量不变（`claude` 减少 = `claude_desktop` 增加），桌面份额全部落在 `claude_desktop`。
7. 官方命名空间：`cache["claude_official"]` 只含 `official` 事件；它同时是桌面卡数据的子集，且不参与任何卡片聚合。
8. 额度账本键：`_quota_daily_from_tools` 从 `claude_official` 取数，而不是 `claude_desktop`。

现有 35 项保持全绿。

### 7.2 真机验收

1. 源码直跑 `collector.compute()`：`claude_desktop.ranges.today` ≈ 桌面客户端今日去重后 token；`claude.ranges.today` ≈ 非桌面客户端今日去重后 token。
2. `build_quota_detail()` 当前周期 token 只含官方份额（今天应为 0，因为今天没有官方通道事件）。
3. 账本：`claude_split == 3`；有日志的天 `claude` 值下降、`claude_desktop` 值上升，两者之和不变。
4. 界面：`scripts/smoke_ui.py` / 截图核对两张卡片、趋势、模型排行、项目足迹、额度历史、浮窗。
5. 打包（`build.ps1`）后隔离环境启动 exe，确认落盘数据与源码一致。

## 8. 风险与限制

| 项 | 说明 |
|---|---|
| entrypoint 判据 | 将来若有别的客户端也写 `claude-desktop*`，会被误归桌面卡；目前该前缀只由 Claude 桌面客户端产生 |
| 历史天归属 | 日志已清理且确有桌面客户端第三方用量的天，份额搬不到桌面卡，留在 `claude`（同 gen 2 偏差） |
| 同一天两口径 | 桌面卡数字（客户端全部）与订阅周期数字（官方）不同源，量级不一致时属预期，不是 bug |
| 混版本同步 | 旧版本 peer 的快照没有 `claude_official` 键 → 该 peer 对订阅周期贡献 0 token（额度读数仍可用），与 gen 2 对旧 peer 的降级口径一致 |
| 首次重扫 | `_CLAUDE_PARSER_VERSION` 提升会让 Claude 日志重解析一次；`_SCAN_CACHE_VERSION` 不动，其它工具不重扫 |
| 降级陷阱 | 用旧构建（< 本次改动）再跑这份账本时，`claude` 的实时混合值会在高水位合并里胜出，桌面卡会少算；重跑迁移须先删 `~/.tokei/ledger.json` 的 `claude_split` 键 |

## 9. 实施分期

1. 数据层：事件带 `entrypoint`、按客户端拆分、解析器版本提升（§3、§4.1–4.2）。
2. 额度专用账本键与读侧映射（§4.3）。
3. 一次性迁移 `claude_split: 3`（§4.4）。
4. 测试与验收（§7），并在 9-28 设计文档顶部标注判据变更。
