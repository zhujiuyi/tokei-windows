from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QLockFile, QStandardPaths, Qt, QUrl
from PySide6.QtGui import QAction, QColor, QIcon, QPainter, QPen, QPixmap
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from .bridge import Store
from .paths import app_data_dir, log_path


def _app_icon() -> QIcon:
    pixmap = QPixmap(64, 64)
    pixmap.fill(QColor("#202126"))
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setPen(QPen(QColor("#eb8566"), 5))
    painter.drawEllipse(10, 10, 44, 44)
    hand_pen = QPen(QColor("#f8f8fa"), 4)
    hand_pen.setCapStyle(Qt.PenCapStyle.RoundCap)
    painter.setPen(hand_pen)
    painter.drawLine(32, 18, 32, 33)
    painter.drawLine(32, 33, 43, 39)
    painter.end()
    return QIcon(pixmap)


def _qml_url() -> QUrl:
    path = Path(__file__).resolve().parent / "qml" / "main.qml"
    if not path.is_file():
        compiled = getattr(sys, "__compiled__", None)
        containing_dir = getattr(compiled, "containing_dir", None)
        if containing_dir:
            path = Path(containing_dir) / "tokei_windows" / "qml" / "main.qml"
    return QUrl.fromLocalFile(str(path))


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Tokei-Windows")
    app.setOrganizationName("Tokei-Windows")
    app.setWindowIcon(_app_icon())
    app.setQuitOnLastWindowClosed(False)

    lock_path = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.TempLocation)
    instance_lock = QLockFile(str(Path(lock_path) / "Tokei-Windows.lock"))
    if not instance_lock.tryLock(0):
        return 0

    store = Store()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("store", store)
    engine.rootContext().setContextProperty("appIcon", _app_icon())
    engine.load(_qml_url())
    if not engine.rootObjects():
        logging.error("Could not load QML UI from %s", _qml_url().toLocalFile())
        return 2
    window = engine.rootObjects()[0]

    tray = QSystemTrayIcon(_app_icon(), app)
    tray.setToolTip(store.traySummary)
    tray_menu = QMenu()
    open_action = QAction("打开 Tokei-Windows", tray_menu)
    refresh_action = QAction("立即刷新", tray_menu)
    exit_action = QAction("退出", tray_menu)
    tray_menu.addAction(open_action)
    tray_menu.addAction(refresh_action)
    tray_menu.addSeparator()
    tray_menu.addAction(exit_action)
    tray.setContextMenu(tray_menu)

    def show_window() -> None:
        window.show()
        window.raise_()
        window.requestActivate()

    def update_tooltip() -> None:
        tray.setToolTip(store.traySummary[:127])

    def exit_app() -> None:
        tray.hide()
        app.quit()

    tray.activated.connect(lambda reason: show_window() if reason in (
        QSystemTrayIcon.ActivationReason.Trigger,
        QSystemTrayIcon.ActivationReason.DoubleClick,
    ) else None)
    open_action.triggered.connect(show_window)
    refresh_action.triggered.connect(store.refresh)
    exit_action.triggered.connect(exit_app)
    store.snapshotChanged.connect(update_tooltip)
    store.lastUpdatedChanged.connect(update_tooltip)
    tray.show()
    store.refresh()

    return app.exec()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        log_path().parent.mkdir(parents=True, exist_ok=True)
        logging.basicConfig(filename=str(log_path()), level=logging.ERROR, encoding="utf-8")
        logging.exception("Fatal application error")
        raise
