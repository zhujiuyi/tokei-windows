from __future__ import annotations

import json
import logging
import os
import sys
import threading
import time
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QRunnable, QThreadPool, QTimer, Signal, Slot, Property
from PySide6.QtGui import QGuiApplication

from . import collector
from .paths import log_path, settings_path


PROVIDERS = [
    ("claude", "Claude Code", "#eb8566"),
    ("codex", "Codex CLI", "#6babfa"),
    ("gemini", "Gemini / Antigravity", "#9e85eb"),
    ("cursor", "Cursor", "#b8c4e6"),
    ("zed", "Zed", "#ed6150"),
    ("sub2api", "Sub2API", "#2fc7d9"),
    ("zai", "z.ai / GLM", "#61abfa"),
    ("grok", "Grok Build", "#a6adbF"),
    ("grok_bot", "Grok Bot", "#f266a3"),
    ("qoder", "Qoder Desktop", "#e6c056"),
    ("qoderwork", "QoderWork", "#c0a64d"),
    ("qodercli", "Qoder CLI", "#f5d675"),
    ("hermes", "Hermes", "#66d199"),
    ("zcode", "ZCode", "#85cc57"),
    ("mimocode", "MiMoCode", "#f28042"),
    ("openclaw", "OpenClaw", "#d973ad"),
    ("pi", "Pi Coding Agent", "#bd94f2"),
    ("prime_agent", "Prime Agent", "#f59448"),
    ("workbuddy", "WorkBuddy", "#40c7b8"),
    ("workbuddy_ai", "WorkBuddy Intl.", "#5ca8f0"),
    ("codebuddy", "CodeBuddy Code", "#7594f5"),
    ("deepseek_harness", "DeepSeek Harness", "#2e94f0"),
    ("opencode", "OpenCode", "#8cbfe6"),
    ("qwencode", "Qwen Code", "#7a8cf2"),
    ("qwenwork", "QwenWork", "#3db8ae"),
    ("kimicode", "Kimi Code", "#33c7a8"),
    ("musecode", "Muse Code", "#1a6be8"),
    ("cmdcode", "Command Code", "#38ad52"),
    ("devin", "Devin", "#6c78fa"),
]

LABELS = {
    "in": "输入", "out": "输出", "cached": "缓存读", "cr": "缓存读",
    "cw": "缓存写", "reason": "推理", "sessions": "会话", "calls": "调用",
    "tasks": "任务", "cost": "估算成本", "cost_cny": "人民币成本",
    "tokens": "Token", "messages": "消息", "sub_agents": "子 Agent",
    "credits": "Credit", "turns": "轮次", "duration": "时长",
}


def _number(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _integer(value: Any) -> int:
    try:
        return int(Decimal(str(value or 0)).to_integral_value(rounding=ROUND_HALF_UP))
    except (InvalidOperation, TypeError, ValueError):
        return 0


def _format_integer(value: Any) -> str:
    return f"{_integer(value):,}"


def _normalize_refresh_seconds(value: Any) -> int:
    try:
        return min(300, max(60, int(value)))
    except (TypeError, ValueError):
        return 60


def _qml_safe(value: Any) -> Any:
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and abs(value) > 9_007_199_254_740_991:
        return str(value)
    if isinstance(value, dict):
        return {key: _qml_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_qml_safe(item) for item in value]
    return value


def _top_tools(snapshot: dict[str, Any], limit: int = 3) -> list[dict[str, Any]]:
    tools = []
    for key, title, color in PROVIDERS:
        provider = snapshot.get(key)
        ranges = provider.get("ranges") if isinstance(provider, dict) else None
        today = (ranges or {}).get("today") or {}
        tokens = sum(_integer(today.get(field)) for field in ("in", "out", "cached", "cr", "cw", "reason"))
        if tokens <= 0:
            continue
        tools.append({
            "key": key,
            "title": title,
            "tint": color,
            "tokens": tokens,
            "tokens_display": _format_integer(tokens),
        })
    return sorted(tools, key=lambda item: (-item["tokens"], item["title"]))[:limit]


def _format_number(value: Any) -> str:
    number = _number(value)
    if abs(number) >= 1_000_000:
        return f"{number / 1_000_000:.1f}M"
    if abs(number) >= 10_000:
        return f"{number / 1_000:.1f}K"
    if number.is_integer():
        return f"{int(number):,}"
    return f"{number:,.2f}"


def _load_settings() -> dict[str, Any]:
    try:
        value = json.loads(settings_path().read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _save_settings(settings: dict[str, Any]) -> None:
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def _keyring_backend():
    if os.name != "nt":
        return None
    try:
        import keyring
        return keyring
    except Exception:
        logging.exception("Windows Credential Manager backend is unavailable")
        return None


def _install_credential_bridge() -> None:
    keyring = _keyring_backend()
    if keyring is None:
        return
    original = collector._tokei_config

    def with_credentials() -> dict[str, Any]:
        config = dict(original())
        config.update(_runtime_config)
        for key in ("sub2api_api_key", "zai_api_key"):
            try:
                secret = keyring.get_password("Tokei-Windows", key)
            except Exception:
                logging.exception("Could not read credential %s", key)
                continue
            if secret:
                config[key] = secret
        return config

    collector._tokei_config = with_credentials


_install_credential_bridge()
_runtime_config: dict[str, Any] = {}


class _JobSignals(QObject):
    completed = Signal(str, object, str)


class _RefreshJob(QRunnable):
    def __init__(self, request_id: str, period: str, include_projects: bool, include_quota_history: bool):
        super().__init__()
        self.request_id = request_id
        self.period = period
        self.include_projects = include_projects
        self.include_quota_history = include_quota_history
        self.signals = _JobSignals()

    @Slot()
    def run(self) -> None:
        started = time.monotonic()
        try:
            usage = collector.compute()
            dashboard = collector.build_dashboard(self.period)
            cost_fields = (
                "claude", "codex", "codex_reserve", "gemini", "grok", "zcode",
                "mimocode", "devin", "pi", "workbuddy", "workbuddy_ai",
                "codebuddy", "deepseek_harness", "opencode", "qwencode",
                "kimicode", "musecode", "cmdcode", "prime_agent", "hermes", "openclaw",
            )
            for day in dashboard.get("daily", []):
                day["total_cost"] = sum(_number(day.get(field)) for field in cost_fields)
                day["tokens_display"] = _format_integer(day.get("tokens", 0))
                day["date_label"] = str(day.get("date", ""))[5:]
            for model in dashboard.get("models", []):
                model["tokens_display"] = _format_integer(model.get("tokens", 0))
            result: dict[str, Any] = {"usage": usage, "dashboard": dashboard}
            if self.include_projects:
                result["projects"] = collector.build_projects(refresh=False)
                for project in result["projects"]:
                    project["tokens_display"] = _format_integer(project.get("tokens", 0))
                    project["tokensDisplay"] = project["tokens_display"]
            if self.include_quota_history:
                result["quota_history"] = collector.build_quota_detail()
                for cycle in result["quota_history"].get("cycles", []):
                    cycle["tokens_display"] = _format_integer(cycle.get("tokens", 0))
            result["elapsed"] = round(time.monotonic() - started, 2)
            self.signals.completed.emit(self.request_id, result, "")
        except Exception as exc:
            logging.exception("Refresh failed")
            self.signals.completed.emit(self.request_id, None, str(exc))


class Store(QObject):
    snapshotChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()
    lastUpdatedChanged = Signal()
    activePageChanged = Signal()
    periodChanged = Signal()
    settingsChanged = Signal()
    floatingVisibleChanged = Signal()
    exitRequested = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._snapshot: dict[str, Any] = {}
        self._dashboard: dict[str, Any] = {}
        self._projects: list[dict[str, Any]] = []
        self._quota_history: dict[str, Any] = {}
        self._busy = False
        self._error = ""
        self._last_updated = "尚未刷新"
        self._active_page = "overview"
        self._period = "30d"
        self._settings = _load_settings()
        config = collector._tokei_config()
        for provider in ("sub2api", "zai"):
            config_key = f"{provider}_quota_enabled"
            self._settings.setdefault(config_key, bool(config.get(config_key, False)))
        self._settings.setdefault("sub2api_base_url", config.get("sub2api_base_url", ""))
        self._settings.setdefault("keep_awake", False)
        self._settings.setdefault("close_behavior", "tray")
        self._settings.setdefault("show_floating_widget", True)
        self._settings["refresh_seconds"] = _normalize_refresh_seconds(
            self._settings.get("refresh_seconds", 60))
        self._floating_visible = False
        self._request_id = ""
        self._pool = QThreadPool.globalInstance()
        self._pending_projects = False
        self._pending_quota_history = False
        log_path().parent.mkdir(parents=True, exist_ok=True)
        logging.basicConfig(
            filename=str(log_path()), level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s", encoding="utf-8")
        if self._settings.get("keep_awake") and not self._set_keep_awake(True):
            self._settings["keep_awake"] = False
            _save_settings(self._settings)
            logging.warning("Could not restore the keep-awake setting")
        self._timer = QTimer(self)
        self._timer.timeout.connect(self.refresh)
        self._timer.start(self._settings["refresh_seconds"] * 1000)

    @Property("QVariantMap", notify=snapshotChanged)
    def snapshot(self) -> dict[str, Any]:
        return _qml_safe(self._snapshot)

    @Property("QVariantMap", notify=snapshotChanged)
    def dashboard(self) -> dict[str, Any]:
        return _qml_safe(self._dashboard)

    @Property("QVariantList", notify=snapshotChanged)
    def cards(self) -> list[dict[str, Any]]:
        return _qml_safe(self._build_cards())

    @Property("QVariantList", notify=snapshotChanged)
    def floatingTools(self) -> list[dict[str, Any]]:
        return _qml_safe(_top_tools(self._snapshot))

    @Property("QVariantList", notify=snapshotChanged)
    def projects(self) -> list[dict[str, Any]]:
        return _qml_safe(self._projects)

    @Property("QVariantMap", notify=snapshotChanged)
    def quotaHistory(self) -> dict[str, Any]:
        return _qml_safe(self._quota_history)

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property(str, notify=lastUpdatedChanged)
    def lastUpdated(self) -> str:
        return self._last_updated

    @Property(str, notify=activePageChanged)
    def activePage(self) -> str:
        return self._active_page

    @Property(str, notify=periodChanged)
    def period(self) -> str:
        return self._period

    @Property(str, notify=settingsChanged)
    def cardPeriod(self) -> str:
        return self._settings.get("card_period", "today")

    @Property("QVariantMap", notify=settingsChanged)
    def settings(self) -> dict[str, Any]:
        return self._settings

    @Property(bool, notify=floatingVisibleChanged)
    def floatingVisible(self) -> bool:
        return self._floating_visible

    @Property(str, notify=snapshotChanged)
    def traySummary(self) -> str:
        summary = self._make_summary()
        return summary[:127]

    @Slot()
    def refresh(self) -> None:
        if self._busy:
            return
        self._busy = True
        self._error = ""
        self.busyChanged.emit()
        self.errorChanged.emit()
        request_id = str(time.time_ns())
        self._request_id = request_id
        job = _RefreshJob(
            request_id, self._period,
            self._active_page == "projects",
            self._active_page == "quotas")
        job.signals.completed.connect(self._refresh_completed)
        self._pool.start(job)

    @Slot(str)
    def setPage(self, page: str) -> None:
        if page not in {"overview", "dashboard", "projects", "quotas", "settings"}:
            return
        self._active_page = page
        self.activePageChanged.emit()
        if page == "projects" and not self._projects:
            self.refresh()
        elif page == "quotas" and not self._quota_history:
            self.refresh()

    @Slot(str)
    def setPeriod(self, period: str) -> None:
        if period not in {"7d", "30d", "90d", "365d", "all"} or period == self._period:
            return
        self._period = period
        self.periodChanged.emit()
        self.refresh()

    @Slot(str)
    def setCardPeriod(self, period: str) -> None:
        if period not in {"today", "yesterday", "week", "lastweek", "month", "year"}:
            return
        self._settings["card_period"] = period
        _save_settings(self._settings)
        self.settingsChanged.emit()
        self.snapshotChanged.emit()

    @Slot(str, str, str)
    def setProviderSetting(self, provider: str, name: str, value: str) -> None:
        allowed = {
            ("sub2api", "sub2api_base_url"),
            ("zai", "zai_region"),
            ("zai", "zai_usage_scope"),
        }
        if (provider, name) not in allowed:
            return
        value = value.strip()
        if name == "sub2api_base_url" and value:
            from urllib.parse import urlparse
            parsed = urlparse(value)
            if parsed.scheme != "https" or not parsed.netloc:
                self._error = "Sub2API 地址必须使用 HTTPS"
                self.errorChanged.emit()
                return
        if name == "zai_region" and value not in {"global", "bigmodel-cn"}:
            return
        if name == "zai_usage_scope" and value not in {"personal", "team"}:
            return
        path = Path(collector._USER_DIR) / "config.json"
        try:
            config = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
            if not isinstance(config, dict):
                config = {}
        except json.JSONDecodeError:
            config = {}
        config[name] = value
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
        _runtime_config[name] = value
        self._settings[name] = value
        _save_settings(self._settings)
        self.settingsChanged.emit()
        self.refresh()

    @Slot(bool)
    def setStartAtLogin(self, enabled: bool) -> None:
        self._settings["start_at_login"] = enabled
        self._settings["_autostart_applied"] = self._set_autostart(enabled)
        _save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot(bool)
    def setKeepAwake(self, enabled: bool) -> None:
        if not self._set_keep_awake(enabled):
            self._error = "Windows 未能更新防休眠状态"
            self.errorChanged.emit()
            return
        self._settings["keep_awake"] = enabled
        _save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot(str)
    def setCloseBehavior(self, behavior: str) -> None:
        if behavior not in {"exit", "tray"}:
            return
        self._settings["close_behavior"] = behavior
        _save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot(bool)
    def setFloatingWidgetEnabled(self, enabled: bool) -> None:
        self._settings["show_floating_widget"] = enabled
        _save_settings(self._settings)
        self.settingsChanged.emit()
        if not enabled:
            self.setFloatingVisible(False)

    @Slot(bool)
    def setFloatingVisible(self, visible: bool) -> None:
        if self._floating_visible == visible:
            return
        self._floating_visible = visible
        self.floatingVisibleChanged.emit()

    @Slot()
    def handleWindowClose(self) -> None:
        if self._settings.get("close_behavior", "tray") == "exit":
            self.exitRequested.emit()
            return
        self.setFloatingVisible(bool(self._settings.get("show_floating_widget", True)))

    @Slot(int)
    def setRefreshSeconds(self, seconds: int) -> None:
        seconds = _normalize_refresh_seconds(seconds)
        self._settings["refresh_seconds"] = seconds
        self._timer.start(seconds * 1000)
        _save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot(str, str)
    def saveCredential(self, provider: str, secret: str) -> None:
        names = {"sub2api": "sub2api_api_key", "zai": "zai_api_key"}
        key = names.get(provider)
        if not key:
            return
        keyring = _keyring_backend()
        if keyring is None:
            self._error = "Windows 凭据管理器不可用，密钥未保存"
            self.errorChanged.emit()
            return
        try:
            if secret.strip():
                keyring.set_password("Tokei-Windows", key, secret.strip())
            else:
                keyring.delete_password("Tokei-Windows", key)
            self._error = "密钥已保存到 Windows 凭据管理器" if secret.strip() else "已删除保存的密钥"
            self.errorChanged.emit()
        except Exception as exc:
            logging.exception("Could not save credential")
            self._error = f"保存失败：{exc}"
            self.errorChanged.emit()

    @Slot(str, bool)
    def setProviderEnabled(self, provider: str, enabled: bool) -> None:
        aliases = {"sub2api": "sub2api_quota_enabled", "zai": "zai_quota_enabled"}
        config_key = aliases.get(provider)
        if not config_key:
            return
        path = Path(collector._USER_DIR) / "config.json"
        try:
            config = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
            if not isinstance(config, dict):
                config = {}
        except json.JSONDecodeError:
            config = {}
        config[config_key] = enabled
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
        _runtime_config[config_key] = enabled
        self._settings[f"{provider}_quota_enabled"] = enabled
        _save_settings(self._settings)
        self.settingsChanged.emit()
        self.refresh()

    def _refresh_completed(self, request_id: str, result: Any, error: str) -> None:
        if request_id != self._request_id:
            return
        self._busy = False
        self.busyChanged.emit()
        if error:
            self._error = f"刷新失败：{error}"
            self.errorChanged.emit()
            return
        self._snapshot = result.get("usage", {})
        self._dashboard = result.get("dashboard", {})
        if "projects" in result:
            self._projects = result["projects"]
        if "quota_history" in result:
            self._quota_history = result["quota_history"]
        self._last_updated = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
        self.snapshotChanged.emit()
        self.lastUpdatedChanged.emit()

    def _build_cards(self) -> list[dict[str, Any]]:
        cards = []
        for key, title, color in PROVIDERS:
            data = self._snapshot.get(key)
            if not isinstance(data, dict):
                continue
            selected_range = self._settings.get("card_period", "today")
            today = ((data.get("ranges") or {}).get(selected_range) or {})
            total_tokens = sum(_integer(today.get(field)) for field in ("in", "out", "cached", "cr", "cw", "reason"))
            quota = data.get("quota") if isinstance(data.get("quota"), dict) else data
            metrics = []
            for name in ("in", "out", "cached", "cr", "cw", "reason", "sessions", "calls", "tasks", "cost", "cost_cny", "credits"):
                value = today.get(name)
                if value is None or _number(value) == 0:
                    continue
                label = LABELS.get(name, name)
                display = f"${_number(value):,.2f}" if name == "cost" else f"¥{_number(value):,.2f}" if name == "cost_cny" else _format_number(value)
                if name == "credits":
                    display = f"{_number(value):,.1f}"
                metrics.append({"label": label, "value": display})
            quotas = []
            if key == "claude":
                for field, label in (("q5", "5 小时"), ("q7", "周额度"), ("qf", "Opus")):
                    value = data.get(field)
                    if value is not None:
                        quotas.append({"label": label, "used": max(0, min(100, 100 - _number(value))), "remaining": _number(value), "stale": bool(data.get(f"{field}_stale"))})
            elif key == "codex":
                for field, label in (("p5", "5 小时"), ("pw", "周额度")):
                    value = data.get(field)
                    if value is not None:
                        quotas.append({"label": label, "used": max(0, min(100, _number(value))), "remaining": max(0, 100 - _number(value)), "stale": bool(data.get(f"{field}_stale"))})
            elif key == "grok" and data.get("pct") is not None:
                quotas.append({"label": "周额度", "used": max(0, min(100, _number(data.get("pct")))), "remaining": max(0, 100 - _number(data.get("pct"))), "stale": bool(data.get("stale"))})
            else:
                for window in (quota.get("windows") or []):
                    used = _number(window.get("used_pct"))
                    quotas.append({"label": window.get("title") or window.get("id") or "额度", "used": max(0, min(100, used)), "remaining": max(0, 100 - used), "stale": bool(quota.get("stale"))})
            if not metrics and isinstance(quota, dict):
                for detail in quota.get("details", [])[:4]:
                    if detail.get("value"):
                        metrics.append({"label": detail.get("label", "信息"), "value": str(detail["value"])[:28]})
            status = "有数据" if metrics or quotas else "暂无本地数据"
            if isinstance(quota, dict) and quota.get("available") is False and ("windows" in quota or "details" in quota):
                status = "额度不可用"
            cards.append({"key": key, "title": title, "tint": color,
                          "total_tokens": total_tokens,
                          "total_tokens_display": _format_integer(total_tokens),
                          "totalTokensDisplay": _format_integer(total_tokens),
                          "status": status, "metrics": metrics[:6], "quotas": quotas[:3]})
        return cards

    def _make_summary(self) -> str:
        total_tokens = 0.0
        total_cost = 0.0
        for key, _, _ in PROVIDERS:
            provider = self._snapshot.get(key, {})
            today = ((provider.get("ranges") or {}).get("today") or {}) if isinstance(provider, dict) else {}
            total_tokens += sum(_number(today.get(field)) for field in ("in", "out", "cached", "cr", "cw", "reason"))
            total_cost += _number(today.get("cost"))
        codex = self._snapshot.get("codex") or {}
        p5, pw = codex.get("p5"), codex.get("pw")
        quota_text = ""
        if p5 is not None or pw is not None:
            values = []
            if p5 is not None:
                values.append(f"5h余{max(0, 100-_number(p5)):.0f}%")
            if pw is not None:
                values.append(f"周余{max(0, 100-_number(pw)):.0f}%")
            quota_text = " · " + " ".join(values)
        summary = f"今日 {_format_number(total_tokens)} Token · ${total_cost:,.2f}{quota_text} · {self._last_updated}"
        if not self._snapshot:
            return "Tokei-Windows 正在加载用量数据"
        return summary

    @staticmethod
    def _set_autostart(enabled: bool) -> bool:
        if os.name != "nt":
            return False
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE)
            with key:
                if enabled:
                    executable = str(Path(sys.argv[0]).resolve())
                    winreg.SetValueEx(key, "Tokei-Windows", 0, winreg.REG_SZ, f'"{executable}"')
                else:
                    try:
                        winreg.DeleteValue(key, "Tokei-Windows")
                    except FileNotFoundError:
                        pass
            return True
        except OSError:
            logging.exception("Could not update Windows startup registration")
            return False

    @staticmethod
    def _set_keep_awake(enabled: bool) -> bool:
        if os.name != "nt":
            return False
        try:
            import ctypes
            state = 0x80000000 | (0x00000001 if enabled else 0)
            return bool(ctypes.windll.kernel32.SetThreadExecutionState(state))
        except Exception:
            logging.exception("Could not update Windows execution state")
            return False
