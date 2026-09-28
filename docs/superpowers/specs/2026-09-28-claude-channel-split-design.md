# Claude 渠道拆分设计：API 通道 / 官方订阅

- 日期：2026-09-28
- 状态：设计已与用户逐节确认（第一部分数据层 / 第二部分各页面输出 / 第三部分界面与测试）；本文档待用户复核后转实施计划
- 影响模块：`windows/tokei_windows/collector.py`、`windows/tokei_windows/bridge.py`、`windows/tokei_windows/qml/*`、`windows/tests/test_windows_client.py`
- 前置：同日完成的「Windows blockfile 缓存读取订阅额度」修复（工作区尚未提交，本设计叠加在同一批改动之上）

## 1. 背景

### 1.1 现象

「额度历史」页里每个周期的 Token 消耗与实际订阅用量严重不符：当前 Claude 周期显示 **835,493,188 Token**，而周期进度只有 **4%**（09-24 13:59 → 10-01 13:59）。

### 1.2 根因（实测）

`~/.claude/projects` 里的日志其实记录了两个完全不同的计费渠道，而采集器把它们合并成了一条 `claude` 数据流：

| 渠道 | 入口(entrypoint) | 消息特征 | 实测规模 |
|---|---|---|---|
| 官方通道（Claude 订阅 / Claude Desktop） | `claude-desktop` | `message.id` 以 `msg_` 开头、`requestId` 以 `req_` 开头、模型 `claude-*` | 101 条 / 18,811,740 Token（2026-09-27 起） |
| OpenCode 中继通道（API 计费） | `sdk-cli`、`cli` | `message.id` 为 uuid/hex、无 `requestId`、模型 `deepseek-*` | 15,559 + 28 条 / 2,185,960,441 + 1,207,365 Token（2026-08-20 起） |

当前周期窗口（09-24 13:59 起）内实测：中继 733.0M（5,499 条）+ 78.5M（362 条），桌面 17.9M（98 条），合计 829.3M —— 即周期卡几乎全部是中继用量，与「订阅已用 4%」自然对不上。

### 1.3 用户要求（原话口径）

1. 额度历史应按渠道区分消耗：通过 OpenCode API 地址消耗的积分不应计入订阅周期。
2. 拆分应下沉到总览卡片：原「Claude Code」卡片统计的改为 OpenCode API 通道；另加一张「Claude Code Desktop」卡片统计官方通道，**订阅额度数据挂在这张新卡片上**（API 通道没有订阅计划）。
3. 范围（用户选择）：**所有页面都分开**。
4. Codex 的中继/订阅区分本次**不做**（用户决定），只做 Claude。

## 2. 目标与非目标

**目标**
- 把 Claude 用量拆成两个独立工具：`claude`（API 中继通道）与 `claude_desktop`（官方通道，含订阅额度）。
- 全部页面口径一致：总览卡片、托盘/浮窗、趋势与成本、模型排行、项目足迹、年度回顾、额度历史。
- 额度历史的 Claude 周期只统计官方通道消耗；订阅额度读数与遗留锚点平滑迁移。

**非目标**
- 不拆分 Codex（含 `codex_reserve` 保持现状）。
- 不按模型名拆分（会误判经中继调用的 Claude 模型）。
- 不改 Claude Desktop 缓存的读取逻辑（沿用今日修复）。

## 3. 分类规则（唯一口径）

每条 assistant 用量记录标记 `official`：

```
official = message.id.startswith("msg_")
       且 requestId.startswith("req_")
       且 model.startswith("claude-")
```

- 命中 → `claude_desktop`（官方通道）；否则 → `claude`（API 中继通道）。
- 实测校验：桌面 101 条全部命中；中继 15,559 条无一命中（其中 3 条 `msg_` 开头但无 `requestId`，按规则归中继）。
- 不使用 `entrypoint` 作为判据：`cli`（09-05/06，deepseek 模型）同样是中继，entrypoint 只说明入口而非计费渠道。

**边界与局限（写进代码注释）**
- 卡片口径是「官方通道」，不等于「订阅」：用官方 API key（非订阅）跑 `claude-*` 模型也会命中 → 归入桌面卡片。
- 反向风险：经中继调用 `claude-*` 模型且同时带 `msg_`/`req_` 时会被判为官方通道。目前未观测到该用法；如日后出现，改为「中继请求的 base_url 白名单」或再加判据。

## 4. 数据层设计

### 4.1 两个缓存命名空间

扫描缓存（`~/.tokei/cache/*.json`）新增顶层命名空间，与现有 `cache["claude"]` 平行：

- `cache["claude"]`：**只含中继事件**的按文件条目（`sig` / `events` / `proj` / `days` / `hours` / `day_hours` / `dh` / `parser_version`），结构不变。
- `cache["claude_desktop"]`：**只含官方事件**的按文件条目，结构完全相同。

只有含对应渠道事件的文件才在该命名空间建条目，因此新增缓存体积 ≈ 官方通道占比（当前 101 条事件，可忽略）。

### 4.2 扫描流程（`scan_claude`，一次解析、两路输出）

1. 遍历 `CLAUDE_DIR`（`~/.claude/projects/**/*.jsonl`），**每个文件仍只解析一次**；只要两个命名空间里任一命名空间的该文件条目 `sig` 或 `parser_version` 不匹配，就重新解析。
2. `_claude_usage()` 增加 `official` 字段（由 §3 规则算出）。
3. 解析后按 `official` 拆成两串事件；各自做同文件的 `_dedupe_claude_events`，分别写入两个命名空间的条目。某渠道事件为空则不在该命名空间建条目（已有条目要删除）。
4. 跨文件去重、按文件聚合（`days`/`hours`/`day_hours`/`dh`/`proj`）在**各自命名空间内**进行，口径与今天完全一致。
5. `stale` 清理取两个命名空间键的并集：文件消失时两边同时删。
6. 分别落账本：
   - `ledger_reconcile("claude", api_live_days, api_sources)`
   - `ledger_reconcile("claude_desktop", desktop_live_days, desktop_sources)`
7. 返回值新增 `desktop_ranges`、`desktop_cur`（`ranges`、`cur` 保持现有含义 = 中继通道）。`classify`/`B` 的构造复制一份给桌面渠道。
8. `_CLAUDE_PARSER_VERSION` 由 1 提到 2（强制旧缓存条目按新规则重解析）。

`_claude_usage()` 里 `official` 的计算位置：`mid`、`request_id`、`model` 都已解析出来后加一行布尔表达式，不做额外读取。

### 4.3 账本与一次性迁移

账本文件 `~/.tokei/ledger.json` 现有 `tools["claude"]` 的 26 天（08-20 ~ 09-28）是**两个渠道混合**的存档，必须迁移，否则桌面渠道的 token 会永远留在 `claude` 里。

迁移分四件事：

1. **迁移标记**：账本顶层新增 `claude_split: 2`（`_load_ledger_from_disk` 只校验 `v`，多余顶层键安全）。标记已存在则整个迁移跳过。
2. **迁移规则**（在 `scan_claude` 内、两次 `ledger_reconcile` 之前执行）：对 `tools["claude"]` 的每一天，用**本次扫描出的桌面渠道当日实测值**做减法：
   `stored[day] = _ledger_values(stored[day], desktop_live_day[day], subtract=True)`。
   减法载荷只含计数口径字段（`in`/`out`/`cr`/`cw`/`cost`/`models`），不含 `projects`（项目名是归属信息，不能做集合差）。
   `_ledger_values(..., subtract=True)` 本身会跳过 `_sources`，于是被改动过的天退化为「聚合 + 残差」，随后由正常的 `ledger_reconcile` 按现存日志重新建立 `_sources` —— 这正是「去掉混合来源、按渠道重建」所需语义。
3. **执行次数**：只做一次；标记写入后不再执行。
4. **无法归属的部分**：日志已被清理、迁移时扫不到的天的桌面份额减不掉，保留在中继渠道（`claude`）里；这是本设计接受的已知偏差，写进代码注释。

### 4.4 额度历史（`claude` → `claude_desktop`）

- `_QUOTA_TOOLS`：`(("claude", "c"), ("codex", "x"), ("grok", "g"))` → `(("claude_desktop", "cd"), ("codex", "x"), ("grok", "g"))`。
- `_quota_day_tokens()`：`tool == "claude"` 分支改为 `tool in ("claude", "claude_desktop")`（口径相同：`in+out+cr+cw`）。
- `_quota_tool_reading()`：桌面渠道读 `source["claude_desktop"]` 的 `q7/q7_reset/q_updated/q7_stale`；**当该键不存在时回退读 `source["claude"]`**（兼容旧版本 peer 写出的同步快照）。
- `_quota_claude_events()` 增加缓存键参数，桌面周期取 `cache["claude_desktop"]` —— 这是本需求的核心：订阅周期内只累计官方通道 token。
- 锚点文件 `~/.tokei/quota_cycles.json` 迁移：`anchors["claude_desktop"]` 不存在时，把 `anchors["claude"]` 整段搬过去（同一一次性迁移里做，避免周期历史从零开始）。
- 多设备：peer 的**账本日表**不再有 `claude_desktop` 时（旧版本 peer）该设备对桌面周期贡献 0 token；**额度读数**仍可用（§上面的回退），周期边界不受影响。混跑期间允许这一降级。

### 4.5 同步快照

- `compute()` 输出的新键 `claude_desktop` 自动进快照（`_sync_safe_usage_payload` 不剔除它），与现在 `claude` 的待遇一致 —— 订阅读数是账号级的，peer 可据此显示。
- `write_sync_snapshot()` 的 `_ledger` 备份自动带上新工具键，无需改动。

### 4.6 首次重扫成本

- `parser_version` 提升会让所有 Claude 日志重解析一次（约 26 天、1.7 万条事件，实测全量扫描 Claude 部分秒级）。
- **不提升** `_SCAN_CACHE_VERSION`：新命名空间是纯增量，旧缓存文件仍可用，其余工具不重扫。

## 5. `compute()` 输出契约

```python
"claude": {                      # OpenCode API 中继通道
    "ranges": …,
    "session_name": …, "session_total": …,     # 中继通道自己的当前会话
},
"claude_desktop": {              # 官方通道（含订阅数据）
    "ranges": …,
    "session_name": …, "session_total": …,
    "q5": …, "q5_reset": …, "q7": …, "q7_reset": …,
    "qf": …, "qf_reset": …, "q_updated": …,
    "q5_stale": …, "q7_stale": …, "qf_stale": …,
},
```

- `q5/q7/qf` 等字段**从 `claude` 移到 `claude_desktop`**（数据源仍是 `scan_claude_plan()`）。
- `_empty_claude()`（错误兜底）补 `desktop_ranges` 与 `desktop_cur`，保证 `compute()` 出错时不 KeyError。
- `main()`（macOS 菜单栏文本路径，Windows 不使用）读 `d["claude"]["ranges"]["today"]`，拆分后自动读中继通道，无需改动。

## 6. 界面

### 6.1 总览卡片

- `PROVIDERS` 在 `("claude", "Claude Code", "#eb8566")` 之后新增 `("claude_desktop", "Claude Code Desktop", "#f2b06a")`。
  - 标题：原卡片保留「Claude Code」＝中继通道（按用户口径）；新卡片「Claude Code Desktop」。
  - 颜色：默认琥珀 `#f2b06a`（与 Claude 橙同族、可区分）；如需调整只改这一处。
- `_build_cards()` 的额度条分支由 `key == "claude"` 改为 `key == "claude_desktop"`；中继卡片无额度条（落到通用分支后自然为空），状态文案保持「有数据」。
- 桥接层其余部分（`_top_tools`、`_make_summary`、浮窗、`_provider_token_total`）都按 `PROVIDERS` 遍历，新增条目即自动生效，无需改动。

### 6.2 趋势 / 成本 / 模型排行（`build_daily_costs`）

- `_empty()` 增加成本列 `"claude_desktop"` 与 token 列 `cd_in/cd_out/cd_cr/cd_cw`。
- 新增一段与现有 Claude 循环平行的循环，遍历 `cache["claude_desktop"]`，产出成本、`cd_*` 列、`_add_day_tokens(d, dk, "claude_desktop", …)`、以及模型条目：
  - 中继通道模型名保持不变（`nice_model(mn)`，今天的显示不变）；
  - 官方通道模型名加后缀：`f"{nice_model(mn)} (Claude Desktop)"`。
- `daily` 输出增加 `"claude_desktop"` 列并计入 `"total"`。
- `_LEDGER_COST_COLUMNS` 增加 `"claude_desktop"`（账本高水位合并逐工具生效）。
- `bridge.py` 的 `cost_fields` 增加 `"claude_desktop"`。

### 6.3 项目足迹

- `_PROJECT_SOURCES` 增加 `("claude_desktop", "Claude Code Desktop", True, "entry", "token_total")`；`cache["claude_desktop"]` 的条目结构与 `cache["claude"]` 相同，直接复用现有贡献流，模型显示为 `模型名 (Claude Code Desktop)`。

### 6.4 年度回顾（`build_wrapped`）

- 现有 Claude 循环改为对 `cache["claude"]` 与 `cache["claude_desktop"]` 各跑一遍（同一套 `day_tokens`/`day_cost`/`proj_tok`/`model_tok`/`weekday`/`hours` 聚合）。
- 账本高水位合并无需改动：循环 `_load_ledger().get("tools")` 时新工具键自动参与。

### 6.5 额度历史卡片

- `qml/QuotaCycleCard.qml` 标题映射增加 `"claude_desktop" → "Claude Code Desktop"`（`"claude"` 分支保留，兼容旧数据）。
- 周期卡片下方 `tokens` 即 §4.4 的官方通道口径。

### 6.6 托盘 / 浮窗

- 悬停摘要与浮窗按 `PROVIDERS`/`cards` 遍历，两张卡片自动出现；摘要里的额度文字仍只显示 Codex（本次不改，避免超出 127 字符上限）。

## 7. 测试与验收

### 7.1 单元测试（`windows/tests/test_windows_client.py`）

1. **分类**：临时 `CLAUDE_DIR` 放两条 assistant 记录（官方：`msg_`+`req_`+`claude-opus-5-5`；中继：uuid + 无 requestId + `deepseek-v4.1-flash`），断言 `scan_claude` 的中继 `ranges` 只含中继 token、`desktop_ranges` 只含官方 token。
2. **缓存双写**：同一文件含两渠道事件时，两个命名空间都出现该文件条目且 `events` 互斥。
3. **账本迁移**：预置 `tools["claude"]` 混合日（含 `_sources`）+ 一条 `claude_split` 缺失，跑一次扫描后断言该日 `claude` 值 = 混合 − 桌面实测，`claude_split == 2`，且再跑一次不重复扣减。
4. **额度历史**：构造桌面缓存与账本日表，断言 `build_quota_detail()` 的 Claude 周期 `tokens` 只含官方通道，且锚点从 `claude` 迁到 `claude_desktop` 后周期仍连续。
5. **卡片渲染**：`_build_cards` 中两张卡片都存在，额度条只在中继之外（即只在 `claude_desktop`）出现，`used/remaining` 语义为已用/剩余。
6. 现有 18 项测试全部保持通过。

### 7.2 真机验收

1. 源码直跑 `collector.compute()`：记录 `claude` 与 `claude_desktop` 的 today/week/all 数字，与日志实测分组（§1.2 的脚本口径）逐项对上。
2. **总量守恒**：迁移前后 `claude` + `claude_desktop` 的 all 期 token/成本 ≈ 迁移前 `claude` 的值（允许日志清理造成的账本兜底差异）。
3. `build_quota_detail()` 当前周期 token ≈ 官方通道窗口实测（当前约 17.9M，而非 835M），进度 4% 与之量级相符。
4. 界面：`scripts/smoke_ui.py`/截图核对两张卡片、趋势、模型排行、项目足迹、额度历史、浮窗。
5. 打包（`build.ps1`）后用隔离环境启动 exe（独立 `LOCALAPPDATA`/`TEMP` + `QT_QPA_PLATFORM=offscreen`），确认落盘数据与源码一致。

## 8. 风险与限制

| 项 | 说明 |
|---|---|
| 中继上的 Claude 模型 | 经中继调用 `claude-*` 且带 `msg_`/`req_` 时会被算进官方卡片（当前未观测到） |
| 官方 API key | 用官方 API key 而非订阅时同样进官方卡片；卡片口径是「官方通道」 |
| 历史天归属 | 日志已清理且确有桌面用量的天无法拆分，保留在中继渠道 |
| 缓存体积 | 新增命名空间只存官方事件，增量可忽略 |
| 混版本同步 | 旧版本 peer 的账本对桌面周期贡献 0 token（额度读数仍有） |
| 首次重扫 | 仅 Claude 日志重解析一次；扫描缓存版本号不提升，其他工具不重扫 |

## 9. 实施期修订（2026-09-28，实施过程中发现并裁定）

1. **解析索引 `cache["_claude_parse_sigs"]`（替代「渠道条目兼记录已解析」）**：命名空间只含有该渠道事件的文件（§4.1/§4.2 语义不变），另用一份与渠道无关的 `{文件: [签名, 解析器版本]}` 索引保证「两个渠道都没事件」的空会话文件不被每轮重读；过期判定同时看索引与现存条目（防旧版本进程写过的条目）。
2. **`ledger_flush` 的陈旧内存账本守卫**：迁移的「重置内存缓存」只保护迁移进程自己。任何在迁移前载入账本的进程，其下一次 flush 会按旧来源把减掉的官方份额合并回来（`_ledger_merge_sources` 视 `kept` 无 `_sources` 为残差 + 旧来源优先）。故 `ledger_flush` 在「磁盘有 `claude_split`、内存没有」时跳过 `claude` 工具（以磁盘的迁移后值为准），该标记随本轮 `_LEDGER_CACHE["data"] = fresh` 自清。
3. **迁移只认「严格读得到」的账本**：`_load_ledger_from_disk()` 在读失败时会给出一份伪造的空账本，据此写标记会抹掉整份历史。迁移改为锁内自己 `open()`：`FileNotFoundError` → 真·新账本（没东西可减，仍要落标记，否则下次扫描会拿已拆分的中继值去减官方份额）；不可读/坏 JSON → 不迁移也不落标记，下一轮再试。
4. **订阅额度数据源在本机消失（用户裁决：暂时不管）**：`claude_desktop` 卡片的 token/成本照常统计，`q5/q7/qf` 保留为 `None`（数据源＝已卸载的 Claude Desktop 缓存；CLI 走 OpenCode 中继、无官方凭据）。将来接通数据源（凭据通道或重装桌面端）无需改结构。

## 10. 实施分期（供后续实施计划拆解）

1. **数据层**：`official` 分类 + 双命名空间扫描 + 双账本 + 一次性迁移（§3、§4.1–4.3、§4.6）。
2. **输出与额度历史**：`compute()` 契约、`_QUOTA_TOOLS` 换键、锚点迁移、事件源切换（§4.4、§4.5、§5）。
3. **界面**：卡片与各页面（§6）。
4. **测试与验收**：单元测试 + 真机 + 打包（§7）。
