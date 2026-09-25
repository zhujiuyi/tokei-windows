from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QCoreApplication, QEvent, QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QFont, QFontDatabase
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication
from shiboken6 import getCppPointer, wrapInstance

from tokei_windows.bridge import Store


def main() -> int:
    app = QApplication([])
    system_cjk_font = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts" / "simsun.ttc"
    if system_cjk_font.is_file():
        font_id = QFontDatabase.addApplicationFont(str(system_cjk_font))
        families = QFontDatabase.applicationFontFamilies(font_id)
        if families:
            app.setFont(QFont(families[0], 10))
    store = Store()
    store._settings = {
        "card_period": "today",
        "refresh_seconds": 60,
        "start_at_login": False,
        "keep_awake": False,
        "sub2api_quota_enabled": False,
        "zai_quota_enabled": False,
        "zai_region": "global",
        "close_behavior": "tray",
        "show_floating_widget": True,
    }
    store._snapshot = {
        "claude": {
            "ranges": {"today": {"in": 32500, "out": 5700, "cached": 21800, "cost": 0.41}},
            "q5": 38,
            "q7": 64,
            "qf": 12,
        },
        "codex": {
            "ranges": {"today": {"in": 12400, "out": 3100, "cost": 0.17}},
            "p5": 31,
            "pw": 58,
        },
    }
    store._dashboard = {
        "daily": [
            {"date": "2026-09-23", "total_cost": 0.31, "tokens": 18000, "tokens_display": "18,000", "date_label": "09-23"},
            {"date": "2026-09-24", "total_cost": 0.45, "tokens": 24500, "tokens_display": "24,500", "date_label": "09-24"},
            {"date": "2026-09-25", "total_cost": 0.58, "tokens": 32600, "tokens_display": "32,600", "date_label": "09-25"},
        ],
        "models": [
            {"name": "claude-sonnet-4-6", "tokens": 72500, "tokens_display": "72,500", "cost": 0.82},
            {"name": "gpt-5-codex", "tokens": 24400, "tokens_display": "24,400", "cost": 0.38},
        ],
    }
    store._projects = [
        {"name": "tokei-windows", "path": "E:/work/tokei-windows", "tokens": 58200, "tokens_display": "58,200", "tokensDisplay": "58,200", "cost": 1.2, "sessions": 8, "tools": ["Claude", "Codex"]}
    ]
    store._quota_history = {
        "cycles": [
            {"tool": "claude", "current": True, "used_pct": 62.0, "tokens": 75200, "tokens_display": "75,200"},
            {"tool": "codex", "current": False, "used_pct": 41.5, "tokens": 39400, "tokens_display": "39,400"},
        ]
    }
    store._last_updated = "2026-09-25 20:00:00"

    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda warnings: [print(warning.toString()) for warning in warnings])
    engine.rootContext().setContextProperty("store", store)
    qml = Path(__file__).resolve().parents[1] / "tokei_windows" / "qml" / "main.qml"
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        print("QML root object was not created")
        return 2
    window = engine.rootObjects()[0]
    quick_window = wrapInstance(getCppPointer(window)[0], QQuickWindow)
    window.show()
    app.processEvents()

    output = Path(__file__).resolve().parents[1] / "dist"
    output.mkdir(parents=True, exist_ok=True)
    for page in ("overview", "dashboard", "projects", "quotas", "settings"):
        store.setPage(page)
        app.processEvents()
        image = quick_window.grabWindow()
        if image.isNull():
            print(f"No frame for page: {page}")
            return 3
        image.save(str(output / f"preview-{page}.png"))

    combo_cases = (
        ("overview", "cardPeriodCombo"),
        ("dashboard", "dashboardPeriodCombo"),
        ("settings", "closeBehaviorCombo"),
        ("settings", "refreshCombo"),
        ("settings", "zaiRegionCombo"),
    )
    original_size = quick_window.size()
    quick_window.resize(1220, 1400)
    app.processEvents()
    for page, object_name in combo_cases:
        store.setPage(page)
        app.processEvents()
        combo = window.findChild(QQuickItem, object_name)
        if combo is None:
            print(f"Dropdown was not created: {object_name}")
            return 9
        click_point = combo.mapToScene(QPointF(combo.width() / 2, combo.height() / 2))
        QTest.mouseClick(quick_window, Qt.MouseButton.LeftButton, pos=QPoint(round(click_point.x()), round(click_point.y())))
        app.processEvents()
        if not combo.property("down"):
            print(f"Dropdown did not open: {object_name}")
            return 10
        image = quick_window.grabWindow()
        if image.isNull():
            print(f"Dropdown frame was not rendered: {object_name}")
            return 11
        image.save(str(output / f"preview-{object_name}.png"))
        QTest.keyClick(quick_window, Qt.Key.Key_Escape)
        app.processEvents()
    quick_window.resize(original_size)
    app.processEvents()

    store.setPage("dashboard")
    app.processEvents()
    trend = window.findChild(QQuickItem, "trendCard")
    chart_mouse = window.findChild(QQuickItem, "trendChartMouse")
    if trend is None or chart_mouse is None:
        print("Trend chart hover target was not created")
        return 5
    hover_point = chart_mouse.mapToScene(QPointF(chart_mouse.width() / 2, chart_mouse.height() / 2))
    QTest.mouseMove(quick_window, QPoint(round(hover_point.x()), round(hover_point.y())))
    app.processEvents()
    if trend.property("selectedIndex") < 0:
        print("Trend chart did not select a point on hover")
        return 6
    quick_window.grabWindow().save(str(output / "preview-dashboard-hover.png"))
    floating = window.findChild(QQuickWindow, "floatingWidget")
    window.close()
    app.processEvents()
    if floating is None or window.isVisible() or not floating.isVisible() or floating.grabWindow().isNull():
        print("Closing to the tray did not show the floating widget")
        return 4
    floating.grabWindow().save(str(output / "preview-floating.png"))
    store.setFloatingVisible(False)
    window.show()
    app.processEvents()
    if not window.isVisible() or floating.isVisible():
        print("Restoring the main window did not hide the floating widget")
        return 7
    exit_requested = []
    store.exitRequested.connect(lambda: exit_requested.append(True))
    store._settings["close_behavior"] = "exit"
    store.handleWindowClose()
    if not exit_requested:
        print("The exit close behavior was not emitted")
        return 8
    store._timer.stop()
    window.close()
    engine.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    store.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    app.processEvents()
    print(f"Rendered 5 pages, 5 dropdowns, and the floating widget to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
