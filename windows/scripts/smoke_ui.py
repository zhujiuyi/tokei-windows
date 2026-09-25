from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QCoreApplication, QEvent, QUrl
from PySide6.QtGui import QFont, QFontDatabase
from PySide6.QtQuick import QQuickWindow
from PySide6.QtQml import QQmlApplicationEngine
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
            {"d": "2026-09-23", "total_cost": 0.31},
            {"d": "2026-09-24", "total_cost": 0.45},
            {"d": "2026-09-25", "total_cost": 0.58},
        ],
        "models": [
            {"name": "claude-sonnet-4-6", "in": 42000, "out": 8500, "cr": 21000, "cw": 1000, "cost": 0.82},
            {"name": "gpt-5-codex", "in": 18000, "out": 2900, "cr": 3500, "cw": 0, "cost": 0.38},
        ],
    }
    store._projects = [
        {"name": "tokei-windows", "path": "E:/work/tokei-windows", "tokens": 58200, "cost": 1.2, "sessions": 8, "tools": ["Claude", "Codex"]}
    ]
    store._quota_history = {
        "cycles": [
            {"tool": "claude", "current": True, "used_pct": 62.0, "tokens": 75200},
            {"tool": "codex", "current": False, "used_pct": 41.5, "tokens": 39400},
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
    store._timer.stop()
    window.close()
    engine.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    store.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    app.processEvents()
    print(f"Rendered 5 pages to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
