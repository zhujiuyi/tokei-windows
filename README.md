# Tokei Windows

Tokei Windows 是基于原项目 [cclank/tokei](https://github.com/cclank/tokei) 进行的 Windows 适配，不是上游官方 Windows 版本。项目复用上游用量采集脚本与价格数据，并以 PySide6/QML 重建 Windows 桌面客户端。适配所依据的上游提交见 [UPSTREAM.md](UPSTREAM.md)。

## Windows 客户端

程序启动后显示独立主窗口，包含总览、工具用量、项目、额度和设置页面。总览卡片显示所选统计周期内各工具的 Token 总量；用量分析图提供日期刻度和悬停明细，模型、项目及额度历史中的 Token 数以完整整数显示。

默认每 60 秒自动刷新，可在设置中改为 120 或 300 秒。设置可以选择关闭主窗口时退出，或隐藏到系统托盘；托盘模式下可显示半透明桌面浮窗，汇总当天 Token 用量排名前三的工具，支持拖动和调整大小。单击托盘图标恢复主窗口，右键菜单提供刷新与退出。托盘悬停摘要显示今日 Token、估算成本、优先额度与更新时间，并限制在 Windows 通知区域支持的长度内。

客户端支持本地用量扫描、可选额度来源、Windows 凭据管理器密钥存储、当前用户登录启动以及防休眠选项。各来源的实际 Windows 支持和验证状态列在 [Windows 支持清单](docs/windows-support.md)。Git 多设备同步和自更新当前不可用；未验证的数据来源会标注为待验证或不可用，不应视为实时支持。

## 构建单文件 EXE

环境要求：Windows 10/11 x64、Python 3.11 或更新版本、Visual Studio C++ Build Tools。

    cd E:\tokei-windows\windows
    py -3.13 -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install --upgrade pip
    python -m pip install -r requirements-build.txt
    .\build.ps1

产物路径：windows\dist\Tokei-Windows.exe。若旧版程序仍在运行导致该文件被占用，构建脚本会生成带时间戳的 `Tokei-Windows-update*.exe` 副本。构建使用 PySide6 部署工具的 Nuitka onefile 模式；目标机器无需预装 Python。首次启动时单文件程序会解包运行组件，因此启动时间可能较长。

应用设置、缓存与上游兼容用量数据保存在 %LOCALAPPDATA%\Tokei-Windows。本地用量日志不会上传。可选服务密钥通过 Windows 凭据存储集成保存。

## 开发与验证

    cd E:\tokei-windows\windows
    python -m unittest discover -s tests -v
    Get-ChildItem tokei_windows\qml\*.qml | ForEach-Object { .\.venv\Scripts\pyside6-qmllint.exe $_.FullName }
    python scripts\smoke_ui.py

GitHub Actions 在 Windows runner 上运行客户端测试、QML 检查并构建单文件程序。

## 来源与许可

原项目：https://github.com/cclank/tokei。本仓库保留上游版权声明，并注明该 Windows 适配基于原项目开发。许可与第三方依赖说明见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
