from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QLockFile, QSize, QStandardPaths, Qt, QUrl
from PySide6.QtGui import QAction, QColor, QCursor, QIcon, QPainter, QPen, QPixmap, QWindow
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


def _centered_window_geometry(
    available: tuple[int, int, int, int],
    requested_width: int = 1220,
    requested_height: int = 820,
) -> tuple[int, int, int, int]:
    left, top, screen_width, screen_height = available
    width = max(1, min(requested_width, screen_width))
    height = max(1, min(requested_height, screen_height))
    x = left + (screen_width - width) // 2
    y = top + (screen_height - height) // 2
    return x, y, width, height


def _place_window_on_current_screen(window, app) -> None:
    screen = app.screenAt(QCursor.pos()) or app.primaryScreen()
    if screen is None:
        return

    available = screen.availableGeometry()
    x, y, width, height = _centered_window_geometry(available.getRect())
    window.setMinimumSize(QSize(min(980, width), min(680, height)))
    window.setGeometry(x, y, width, height)


def _floating_widget_geometry(
    available: tuple[int, int, int, int],
    requested_width: int = 360,
    requested_height: int = 224,
    margin: int = 24,
) -> tuple[int, int, int, int]:
    left, top, screen_width, screen_height = available
    width = min(requested_width, max(1, screen_width - margin * 2))
    height = min(requested_height, max(1, screen_height - margin * 2))
    x = left + max(0, screen_width - width - margin)
    y = top + margin
    return x, y, width, height


def _place_floating_widget_on_current_screen(window, app) -> None:
    if window is None:
        return
    screen = app.screenAt(QCursor.pos()) or app.primaryScreen()
    if screen is None:
        return
    available = screen.availableGeometry()
    x, y, width, height = _floating_widget_geometry(available.getRect())
    window.setMinimumSize(QSize(min(260, width), min(150, height)))
    window.setGeometry(x, y, width, height)


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
    floating_window = window.findChild(QWindow, "floatingWidget")

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
        store.setFloatingVisible(False)
        if not any(screen.availableGeometry().contains(window.geometry()) for screen in app.screens()):
            _place_window_on_current_screen(window, app)
        window.show()
        window.raise_()
        window.requestActivate()

    def update_tooltip() -> None:
        tray.setToolTip(store.traySummary[:127])

    def exit_app() -> None:
        store.setFloatingVisible(False)
        tray.hide()
        app.quit()

    tray.activated.connect(lambda reason: show_window() if reason in (
        QSystemTrayIcon.ActivationReason.Trigger,
        QSystemTrayIcon.ActivationReason.DoubleClick,
    ) else None)
    open_action.triggered.connect(show_window)
    refresh_action.triggered.connect(store.refresh)
    exit_action.triggered.connect(exit_app)
    store.exitRequested.connect(exit_app)
    store.snapshotChanged.connect(update_tooltip)
    store.lastUpdatedChanged.connect(update_tooltip)
    _place_window_on_current_screen(window, app)
    _place_floating_widget_on_current_screen(floating_window, app)
    window.show()
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
