from __future__ import annotations

import os
from pathlib import Path


APP_NAME = "Tokei-Windows"


def app_data_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    path = Path(root) / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def settings_path() -> Path:
    return app_data_dir() / "settings.json"


def log_path() -> Path:
    return app_data_dir() / "logs" / "tokei.log"
