import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: false
    width: 1220
    height: 820
    minimumWidth: 980
    minimumHeight: 680
    title: "Tokei-Windows · AI 用量面板"
    color: "#202126"

    property color ink: "#f8f8fa"
    property color muted: "#d1d1d6"
    property color soft: "#94959f"
    property color panel: "#25262d"
    property color coral: "#eb8566"
    property string currentPage: store.activePage

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#33363f" }
            GradientStop { position: 1.0; color: "#1f2025" }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 218
            Layout.fillHeight: true
            color: "#17181d"
            border.color: "#34353c"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        width: 42; height: 42; radius: 14
                        color: "#352d30"
                        border.color: "#a75d4d"; border.width: 1
                        Text { anchors.centerIn: parent; text: "◷"; color: coral; font.pixelSize: 25; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { text: "Tokei"; color: ink; font.pixelSize: 21; font.weight: Font.DemiBold }
                        Text { text: "WINDOWS EDITION"; color: soft; font.pixelSize: 9; font.letterSpacing: 1.4 }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#34353c"; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                Repeater {
                    model: [
                        { id: "overview", title: "总览", icon: "◫" },
                        { id: "dashboard", title: "用量分析", icon: "⌁" },
                        { id: "projects", title: "项目足迹", icon: "⌂" },
                        { id: "quotas", title: "额度历史", icon: "◷" },
                        { id: "settings", title: "设置", icon: "⚙" }
                    ]
                    delegate: Item {
                        Layout.fillWidth: true
                        height: 44
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: store.activePage === modelData.id ? "#3b3030" : "transparent"
                            border.color: store.activePage === modelData.id ? "#68463f" : "transparent"
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Text { text: modelData.icon; color: store.activePage === modelData.id ? coral : soft; font.pixelSize: 17; Layout.preferredWidth: 18 }
                            Text { text: modelData.title; color: store.activePage === modelData.id ? ink : muted; font.pixelSize: 13; font.weight: store.activePage === modelData.id ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: store.setPage(modelData.id) }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    height: 84
                    radius: 14
                    color: "#222329"
                    border.color: "#393a42"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 5
                        Text { text: store.busy ? "正在扫描本机日志" : "本地数据"; color: ink; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: "数据仅在本机处理"; color: soft; font.pixelSize: 10 }
                        Text { text: "更新于 " + store.lastUpdated; color: soft; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                color: "#202126"
                border.color: "#34353c"
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 26
                    anchors.rightMargin: 24
                    Text {
                        text: store.activePage === "overview" ? "用量总览" : store.activePage === "dashboard" ? "用量分析" : store.activePage === "projects" ? "项目足迹" : store.activePage === "quotas" ? "额度历史" : "设置"
                        color: ink; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true
                    }
                    Text { text: store.busy ? "扫描中…" : "● 本机"; color: store.busy ? "#e7bc68" : "#6ed39c"; font.pixelSize: 11; Layout.rightMargin: 8 }
                    Button {
                        text: store.busy ? "刷新中" : "刷新"
                        enabled: !store.busy
                        onClicked: store.refresh()
                        contentItem: Text { text: store.busy ? "刷新中" : "刷新"; color: "#fff4ef"; font.pixelSize: 12; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 10; color: parent.enabled ? "#a85f50" : "#5b4a48"; border.color: "#cb806d" }
                        Layout.preferredWidth: 88; Layout.preferredHeight: 38
                    }
                }
            }

            ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Item {
                    width: bodyScroll.availableWidth
                    implicitHeight: contentColumn.implicitHeight + 56
                    ColumnLayout {
                        id: contentColumn
                        width: parent.width
                        anchors.top: parent.top
                        anchors.topMargin: 24
                        anchors.leftMargin: 26
                        anchors.rightMargin: 26
                        spacing: 20

                        Rectangle {
                            visible: store.error.length > 0
                            Layout.fillWidth: true; implicitHeight: visible ? 42 : 0; radius: 10
                            color: "#472c30"; border.color: "#a9555c"
                            Text { anchors.fill: parent; anchors.margins: 12; text: store.error; color: "#ffd3d3"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }

                        ColumnLayout {
                            visible: store.activePage === "overview"
                            Layout.fillWidth: true
                            spacing: 18
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Repeater {
                                    model: [
                                        { label: "今日估算成本", value: rootCost(), tint: "#eb8566" },
                                        { label: "今日 Token", value: rootTokens(), tint: "#6babfa" },
                                        { label: "活跃工具", value: activeTools(), tint: "#9e85eb" },
                                        { label: "模型数量", value: modelCount(), tint: "#66d199" }
                                    ]
                                    delegate: SummaryCard { Layout.fillWidth: true }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "工具用量"; color: ink; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                DarkComboBox {
                                    id: cardPeriodCombo
                                    objectName: "cardPeriodCombo"
                                    Layout.preferredWidth: 130
                                    model: ["今天", "昨天", "本周", "上周", "本月", "今年"]
                                    currentIndex: store.cardPeriod === "today" ? 0 : store.cardPeriod === "yesterday" ? 1 : store.cardPeriod === "week" ? 2 : store.cardPeriod === "lastweek" ? 3 : store.cardPeriod === "month" ? 4 : 5
                                    onActivated: store.setCardPeriod(["today", "yesterday", "week", "lastweek", "month", "year"][currentIndex])
                                }
                                Text { text: "每 " + (store.settings.refresh_seconds || 60) + " 秒更新"; color: soft; font.pixelSize: 10 }
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 850 ? 3 : 2
                                columnSpacing: 14; rowSpacing: 14
                                Repeater {
                                    model: store.cards
                                    delegate: ToolCard {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 186
                                    }
                                }
                            }
                            Rectangle {
                                visible: store.cards.length === 0
                                Layout.fillWidth: true; height: 150; radius: 16
                                color: "#222329"; border.color: "#393a42"
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: store.busy ? "正在读取用量" : "暂无可显示的数据"; color: ink; font.pixelSize: 15; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: "安装并使用受支持的 AI 编程工具后，数据会显示在这里。"; color: soft; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "dashboard"
                            Layout.fillWidth: true; spacing: 16
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "成本与 Token 趋势"; color: ink; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                DarkComboBox {
                                    id: dashboardPeriodCombo
                                    objectName: "dashboardPeriodCombo"
                                    Layout.preferredWidth: 122
                                    model: ["7 天", "30 天", "90 天", "365 天", "全部"]
                                    currentIndex: store.period === "7d" ? 0 : store.period === "30d" ? 1 : store.period === "90d" ? 2 : store.period === "365d" ? 3 : 4
                                    onActivated: store.setPeriod(["7d", "30d", "90d", "365d", "all"][currentIndex])
                                }
                            }
                            TrendCard { Layout.fillWidth: true; Layout.preferredHeight: 310; points: store.dashboard.daily || [] }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 260; radius: 16
                                color: "#202126"; border.color: "#3c3d45"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 18; spacing: 12
                                    Text { text: "模型用量排行"; color: ink; font.pixelSize: 14; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: (store.dashboard.models || []).slice(0, 12).map(function(item) { return { name: item.name || "未知模型", tokensDisplay: item.tokens_display || "0", cost: Number(item.cost || 0) } })
                                        delegate: ModelRow { Layout.fillWidth: true }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "projects"
                            Layout.fillWidth: true; spacing: 14
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "项目贡献"; color: ink; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                Text { text: store.projects.length + " 个项目"; color: soft; font.pixelSize: 11 }
                            }
                            Repeater {
                                model: store.projects
                                delegate: ProjectCard { Layout.fillWidth: true }
                            }
                            Text { visible: store.projects.length === 0 && !store.busy; text: "没有发现带项目维度的会话记录"; color: soft; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 40 }
                        }

                        ColumnLayout {
                            visible: store.activePage === "quotas"
                            Layout.fillWidth: true; spacing: 14
                            Text { text: "额度周期历史"; color: ink; font.pixelSize: 16; font.weight: Font.DemiBold }
                            Repeater {
                                model: (store.quotaHistory.cycles || []).map(function(cycle) { return { cycle: cycle, tokensDisplay: cycle.tokens_display || "0" } })
                                delegate: QuotaCycleCard { Layout.fillWidth: true }
                            }
                            Rectangle {
                                visible: (store.quotaHistory.cycles || []).length === 0
                                Layout.fillWidth: true; height: 150; radius: 16
                                color: "#222329"; border.color: "#393a42"
                                Text { anchors.centerIn: parent; text: store.busy ? "读取额度历史…" : "暂时没有可绘制的额度周期"; color: soft; font.pixelSize: 12 }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "settings"
                            Layout.fillWidth: true; spacing: 16
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 420; radius: 16
                                color: "#222329"; border.color: "#393a42"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 18; spacing: 13
                                    Text { text: "应用行为"; color: ink; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "登录 Windows 后自动启动"; color: ink; font.pixelSize: 12 }
                                            Text { text: "使用当前用户的启动项，不需要管理员权限"; color: soft; font.pixelSize: 10 }
                                        }
                                        Switch { checked: store.settings.start_at_login === true; onToggled: store.setStartAtLogin(checked) }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#383941" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "Tokei 运行时保持电脑唤醒"; color: ink; font.pixelSize: 12 }
                                            Text { text: "关闭应用后恢复 Windows 电源策略"; color: soft; font.pixelSize: 10 }
                                        }
                                        Switch { checked: store.settings.keep_awake === true; onToggled: store.setKeepAwake(checked) }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#383941" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "点击关闭按钮时"; color: ink; font.pixelSize: 12 }
                                            Text { text: "选择退出应用或隐藏到系统托盘"; color: soft; font.pixelSize: 10 }
                                        }
                                        DarkComboBox {
                                            id: closeBehaviorCombo
                                            objectName: "closeBehaviorCombo"
                                            Layout.preferredWidth: 126
                                            model: ["隐藏到托盘", "退出应用"]
                                            currentIndex: store.settings.close_behavior === "exit" ? 1 : 0
                                            onActivated: store.setCloseBehavior(currentIndex === 1 ? "exit" : "tray")
                                        }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#383941" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "隐藏到托盘时显示桌面浮窗"; color: ink; font.pixelSize: 12 }
                                            Text { text: "展示今日用量排名前三的工具，可拖动和调整大小"; color: soft; font.pixelSize: 10; wrapMode: Text.WordWrap }
                                        }
                                        Switch { checked: store.settings.show_floating_widget !== false; onToggled: store.setFloatingWidgetEnabled(checked) }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#383941" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "自动刷新间隔"; color: ink; font.pixelSize: 12 }
                                            Text { text: "本地日志扫描和已开启的额度查询"; color: soft; font.pixelSize: 10 }
                                        }
                                        DarkComboBox {
                                            id: refreshCombo
                                            objectName: "refreshCombo"
                                            Layout.preferredWidth: 126
                                            model: ["60 秒", "120 秒", "300 秒"]
                                            currentIndex: refreshIndex()
                                            onActivated: store.setRefreshSeconds([60, 120, 300][currentIndex])
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 390; radius: 16
                                color: "#222329"; border.color: "#393a42"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 18; spacing: 12
                                    Text { text: "可选额度来源"; color: ink; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { text: "API 密钥保存在 Windows 凭据管理器；额度查询默认关闭。"; color: soft; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Sub2API"; color: ink; font.pixelSize: 12; Layout.fillWidth: true }
                                        Switch { checked: store.settings.sub2api_quota_enabled === true; onToggled: store.setProviderEnabled("sub2api", checked) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        TextField { id: sub2apiUrl; text: store.settings.sub2api_base_url || ""; placeholderText: "https://你的 Sub2API 域名"; placeholderTextColor: "#747580"; Layout.fillWidth: true; color: ink; background: Rectangle { radius: 8; color: "#191a1f"; border.color: "#44454d" } }
                                        Button {
                                            id: saveSub2ApiUrl
                                            text: "保存地址"
                                            onClicked: store.setProviderSetting("sub2api", "sub2api_base_url", sub2apiUrl.text)
                                            contentItem: Text { text: saveSub2ApiUrl.text; color: "#f1f0f3"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 8; color: saveSub2ApiUrl.down ? "#3b3030" : "#2c2d34"; border.color: "#555660" }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        TextField { id: sub2apiKey; placeholderText: "Sub2API API Key（留空删除）"; placeholderTextColor: "#747580"; echoMode: TextInput.Password; Layout.fillWidth: true; color: ink; background: Rectangle { radius: 8; color: "#191a1f"; border.color: "#44454d" } }
                                        Button {
                                            id: saveSub2ApiKey
                                            text: "保存"
                                            onClicked: { store.saveCredential("sub2api", sub2apiKey.text); sub2apiKey.clear() }
                                            contentItem: Text { text: saveSub2ApiKey.text; color: "#f1f0f3"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 8; color: saveSub2ApiKey.down ? "#3b3030" : "#2c2d34"; border.color: "#555660" }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "z.ai / GLM"; color: ink; font.pixelSize: 12; Layout.fillWidth: true }
                                        Switch { checked: store.settings.zai_quota_enabled === true; onToggled: store.setProviderEnabled("zai", checked) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        DarkComboBox {
                                            id: zaiRegionCombo
                                            objectName: "zaiRegionCombo"
                                            Layout.preferredWidth: 150
                                            model: ["Global", "BigModel CN"]
                                            currentIndex: store.settings.zai_region === "bigmodel-cn" ? 1 : 0
                                            onActivated: store.setProviderSetting("zai", "zai_region", currentIndex === 1 ? "bigmodel-cn" : "global")
                                        }
                                        TextField { id: zaiKey; placeholderText: "z.ai API Key（留空删除）"; placeholderTextColor: "#747580"; echoMode: TextInput.Password; Layout.fillWidth: true; color: ink; background: Rectangle { radius: 8; color: "#191a1f"; border.color: "#44454d" } }
                                        Button {
                                            id: saveZaiKey
                                            text: "保存"
                                            onClicked: { store.saveCredential("zai", zaiKey.text); zaiKey.clear() }
                                            contentItem: Text { text: saveZaiKey.text; color: "#f1f0f3"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 8; color: saveZaiKey.down ? "#3b3030" : "#2c2d34"; border.color: "#555660" }
                                        }
                                    }
                                }
                            }
                            Text { text: "配置与缓存：%LOCALAPPDATA%\\Tokei-Windows；本机用量日志不会上传。"; color: soft; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }

    function rootCost() {
        var total = 0; var keys = Object.keys(store.snapshot || {})
        for (var i = 0; i < keys.length; i++) { var r = (((store.snapshot[keys[i]] || {}).ranges || {}).today || {}); total += Number(r.cost || 0) }
        return "$" + Number(total).toFixed(2)
    }
    function rootTokens() {
        var total = 0; var keys = Object.keys(store.snapshot || {})
        for (var i = 0; i < keys.length; i++) { var r = (((store.snapshot[keys[i]] || {}).ranges || {}).today || {}); total += Number(r.in || 0) + Number(r.out || 0) + Number(r.cached || 0) + Number(r.cr || 0) + Number(r.cw || 0) + Number(r.reason || 0) }
        return pretty(total)
    }
    function activeTools() { var n = 0; var list = store.cards || []; for (var i = 0; i < list.length; i++) if (list[i].metrics.length || list[i].quotas.length) n++; return String(n) }
    function modelCount() { var list = (store.dashboard || {}).models || []; return String(list.length) }
    function pretty(n) { if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"; if (n >= 10000) return (n / 1000).toFixed(1) + "K"; return Math.round(n).toLocaleString() }
    function refreshIndex() { var s = store.settings.refresh_seconds || 60; return s >= 300 ? 2 : s >= 120 ? 1 : 0 }
    onClosing: function(close) { close.accepted = false; store.handleWindowClose(); win.hide() }

    Window {
        id: floatingWindow
        objectName: "floatingWidget"
        visible: store.floatingVisible
        width: 360
        height: 224
        minimumWidth: 260
        minimumHeight: 150
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        color: "transparent"
        opacity: 0.86
        title: "Tokei 今日用量"

        Rectangle {
            id: floatingPanel
            anchors.fill: parent
            anchors.margins: 1
            radius: 16
            color: "#202126"
            border.color: "#665458"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Math.max(11, Math.min(18, floatingWindow.width / 22))
                spacing: Math.max(6, Math.min(11, floatingWindow.height / 20))

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: "今日工具用量"; color: "#f8f8fa"; font.pixelSize: Math.max(12, Math.min(16, floatingWindow.width / 23)); font.weight: Font.DemiBold }
                        Text { text: store.lastUpdated; color: "#9697a0"; font.pixelSize: Math.max(8, Math.min(10, floatingWindow.width / 36)) }
                    }
                    Rectangle {
                        Layout.preferredWidth: 25; Layout.preferredHeight: 25; radius: 7
                        color: floatingCloseMouse.containsMouse ? "#493435" : "transparent"
                        Text { anchors.centerIn: parent; text: "×"; color: "#d1d1d6"; font.pixelSize: 18 }
                        MouseArea { id: floatingCloseMouse; anchors.fill: parent; hoverEnabled: true; onClicked: store.setFloatingVisible(false) }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#383941" }

                Repeater {
                    model: store.floatingTools.map(function(tool) {
                        return { toolTitle: tool.title, toolTint: tool.tint, tokensDisplay: tool.tokens_display }
                    })
                    delegate: RowLayout {
                        required property string toolTitle
                        required property color toolTint
                        required property string tokensDisplay
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        Rectangle { Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4; color: toolTint }
                        Text { text: toolTitle; color: "#dcdce1"; font.pixelSize: Math.max(10, Math.min(13, floatingWindow.width / 28)); Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: tokensDisplay + " Token"; color: "#f2c1b4"; font.pixelSize: Math.max(8, Math.min(13, floatingWindow.width / 34)); font.weight: Font.Medium; horizontalAlignment: Text.AlignRight }
                    }
                }

                Text {
                    visible: store.floatingTools.length === 0
                    text: "今天还没有可显示的 Token 用量"
                    color: "#a6a7b0"
                    font.pixelSize: Math.max(10, Math.min(12, floatingWindow.width / 30))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                width: parent.width - 42
                height: 34
                anchors.left: parent.left
                anchors.top: parent.top
                cursorShape: Qt.SizeAllCursor
                onPressed: floatingWindow.startSystemMove()
            }

            MouseArea {
                width: 22; height: 22
                anchors.right: parent.right; anchors.bottom: parent.bottom
                cursorShape: Qt.SizeFDiagCursor
                onPressed: floatingWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
                Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 9; height: 9; color: "transparent"; border.color: "#9b7f79"; rotation: 45 }
            }
        }

        onClosing: function(close) { close.accepted = false; store.setFloatingVisible(false) }
    }
}
