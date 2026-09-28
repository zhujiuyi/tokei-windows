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
    color: "#101319"
    palette.window: "#101319"
    palette.windowText: "#f2f5fa"
    palette.base: "#141922"
    palette.alternateBase: "#1a1e26"
    palette.text: "#c7d0de"
    palette.button: "#20252e"
    palette.buttonText: "#c7d0de"
    palette.highlight: "#6f9cdd"
    palette.highlightedText: "#ffffff"
    palette.placeholderText: "#778396"

    property color ink: "#f2f5fa"
    property color muted: "#c7d0de"
    property color soft: "#8994a4"
    property color panel: "#1a1e26"
    property color coral: "#f09578"
    property string currentPage: store.activePage
    property string selectedToolTitle: ""
    property string selectedToolTotal: "0"
    property var selectedToolDetails: []

    function showToolDetails(title, total, details) {
        selectedToolTitle = title
        selectedToolTotal = total
        selectedToolDetails = details || []
        toolDetailsDialog.open()
    }

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#171c25" }
            GradientStop { position: 0.46; color: "#12161e" }
            GradientStop { position: 1.0; color: "#101319" }
        }
    }

    Dialog {
        id: toolDetailsDialog
        modal: true
        focus: true
        width: Math.min(win.width - 48, 1060)
        anchors.centerIn: parent
        padding: 22
        spacing: 8
        title: win.selectedToolTitle + " · 模型用量"
        closePolicy: Popup.CloseOnEscape
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { target: toolDetailsDialog; property: "opacity"; from: 0; to: 1; duration: 155; easing.type: Easing.OutCubic }
                NumberAnimation { target: toolDetailsDialog; property: "scale"; from: 0.975; to: 1; duration: 190; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { target: toolDetailsDialog; property: "opacity"; to: 0; duration: 105; easing.type: Easing.InCubic }
                NumberAnimation { target: toolDetailsDialog; property: "scale"; to: 0.985; duration: 105; easing.type: Easing.InCubic }
            }
        }

        background: Rectangle {
            radius: 20
            color: "#1a1e26"
            border.color: "#353d49"
            border.width: 1
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: "#ffffff"; opacity: 0.07 }
        }

        header: RowLayout {
            implicitHeight: 76
            spacing: 12
            Item { Layout.preferredWidth: 10 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { text: win.selectedToolTitle + " · 模型用量"; color: ink; font.pixelSize: 19; font.weight: Font.DemiBold }
                Text { text: "按模型与思考程度汇总当前周期的 Token"; color: soft; font.pixelSize: 11 }
            }
            Rectangle {
                Layout.preferredWidth: 1; Layout.preferredHeight: 30
                color: "#343c49"
            }
            ColumnLayout {
                spacing: 2
                Text { text: "周期消耗"; color: soft; font.pixelSize: 10; Layout.alignment: Qt.AlignRight }
                Text { text: win.selectedToolTotal + " Token"; color: coral; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignRight }
            }
            Button {
                id: closeToolDetails
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                Layout.rightMargin: 18
                onClicked: toolDetailsDialog.close()
                contentItem: Text { text: "×"; color: closeToolDetails.down ? "#ffffff" : "#b8c2d0"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle {
                    radius: 11
                    color: closeToolDetails.down ? "#343b47" : closeToolDetails.hovered ? "#2a303b" : "transparent"
                    border.color: closeToolDetails.hovered ? "#465162" : "transparent"
                    Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "统计周期"
                    color: soft; font.pixelSize: 10
                    Layout.fillWidth: true
                }
                Text {
                    text: cardPeriodCombo.currentText
                    color: muted; font.pixelSize: 10; font.weight: Font.Medium
                }
            }

            RowLayout {
                visible: win.selectedToolDetails.length > 0
                Layout.fillWidth: true
                spacing: 10
                Text { text: "模型"; Layout.fillWidth: true; Layout.preferredWidth: 145; color: soft; font.pixelSize: 10 }
                Text { text: "思考程度"; Layout.fillWidth: true; Layout.preferredWidth: 78; color: soft; font.pixelSize: 10 }
                Text { text: "Token"; Layout.fillWidth: true; Layout.preferredWidth: 94; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
                Text { text: "输入"; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
                Text { text: "缓存读"; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
                Text { text: "缓存写"; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
                Text { text: "输出"; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
                Text { text: "推理"; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: soft; font.pixelSize: 10 }
            }

            Rectangle { visible: win.selectedToolDetails.length > 0; Layout.fillWidth: true; height: 1; color: "#303743" }

            Text {
                visible: win.selectedToolDetails.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                text: "当前周期没有可用的模型级 Token 明细。"
                color: soft
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                visible: win.selectedToolDetails.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 7 * 42)
                clip: true
                model: win.selectedToolDetails
                interactive: contentHeight > height
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 42
                    radius: 8
                    color: index % 2 === 0 ? "#20252e" : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 10
                        Text { text: modelData.name; Layout.fillWidth: true; Layout.preferredWidth: 145; color: muted; font.pixelSize: 10; elide: Text.ElideRight }
                        Text { text: modelData.effort; Layout.fillWidth: true; Layout.preferredWidth: 78; color: muted; font.pixelSize: 10; elide: Text.ElideRight }
                        Text { text: modelData.tokens_display; Layout.fillWidth: true; Layout.preferredWidth: 94; horizontalAlignment: Text.AlignRight; color: ink; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Text { text: modelData.in_display; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: muted; font.pixelSize: 10 }
                        Text { text: modelData.cached_read_display; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: muted; font.pixelSize: 10 }
                        Text { text: modelData.cache_write_display; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: muted; font.pixelSize: 10 }
                        Text { text: modelData.out_display; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: muted; font.pixelSize: 10 }
                        Text { text: modelData.reason_display; Layout.fillWidth: true; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight; color: muted; font.pixelSize: 10 }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.selectedToolDetails.length > 0
                text: "未记录表示本地数据源未提供思考程度；推理 Token 按工具记录口径显示。"
                color: soft; font.pixelSize: 9
                wrapMode: Text.Wrap
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 232
            Layout.fillHeight: true
            color: "#12161d"
            border.color: "#29303b"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 22
                anchors.bottomMargin: 18
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        width: 42; height: 42; radius: 14
                        color: "#282c35"
                        border.color: "#4a5261"; border.width: 1
                        Text { anchors.centerIn: parent; text: "◷"; color: coral; font.pixelSize: 25; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { text: "Tokei"; color: ink; font.pixelSize: 21; font.weight: Font.DemiBold }
                        Text { text: "WINDOWS EDITION"; color: soft; font.pixelSize: 9; font.letterSpacing: 1.4 }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#29303b"; Layout.topMargin: 6; Layout.bottomMargin: 4 }

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
                        height: 46
                        property bool hovered: navMouse.containsMouse
                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: store.activePage === modelData.id ? "#252e3b" : parent.hovered ? "#1b2029" : "transparent"
                            border.color: store.activePage === modelData.id ? "#3c506c" : "transparent"
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Text { text: modelData.icon; color: store.activePage === modelData.id ? "#a9c8ff" : soft; font.pixelSize: 17; Layout.preferredWidth: 18 }
                            Text { text: modelData.title; color: store.activePage === modelData.id ? ink : muted; font.pixelSize: 13; font.weight: store.activePage === modelData.id ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
                        }
                        MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; onClicked: store.setPage(modelData.id) }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    height: 90
                    radius: 16
                    color: "#1a1e26"
                    border.color: "#2c333f"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 13; spacing: 5
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
                Layout.preferredHeight: 76
                color: "#141820"
                border.color: "#29303b"
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 30
                    anchors.rightMargin: 28
                    Text {
                        text: store.activePage === "overview" ? "用量总览" : store.activePage === "dashboard" ? "用量分析" : store.activePage === "projects" ? "项目足迹" : store.activePage === "quotas" ? "额度历史" : "设置"
                        color: ink; font.pixelSize: 23; font.weight: Font.DemiBold; font.letterSpacing: -0.25; Layout.fillWidth: true
                    }
                    Text { text: store.busy ? "● 扫描中" : "● 本机"; color: store.busy ? "#e9bf78" : "#75d6ae"; font.pixelSize: 11; Layout.rightMargin: 10 }
                    Button {
                        text: store.busy ? "刷新中" : "刷新"
                        enabled: !store.busy
                        hoverEnabled: true
                        onClicked: store.refresh()
                        contentItem: Text { text: store.busy ? "刷新中" : "刷新数据"; color: "#f6f8fb"; font.pixelSize: 12; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle {
                            radius: 11
                            color: !parent.enabled ? "#3d424c" : parent.down ? "#42679b" : parent.hovered ? "#527bb3" : "#466da4"
                            border.color: parent.hovered ? "#87b3f3" : "#5c81b5"
                            Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        }
                        Layout.preferredWidth: 98; Layout.preferredHeight: 40
                    }
                }
            }

            ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.vertical.width: 8

                Item {
                    width: bodyScroll.availableWidth
                    implicitHeight: contentColumn.implicitHeight + 56
                    ColumnLayout {
                        id: contentColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        anchors.top: parent.top
                        anchors.topMargin: 24
                        spacing: 22

                        Rectangle {
                            visible: store.error.length > 0
                            Layout.fillWidth: true; implicitHeight: visible ? 42 : 0; radius: 10
                            color: "#34252a"; border.color: "#845563"
                            Text { anchors.fill: parent; anchors.margins: 12; text: store.error; color: "#ffd3d3"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }

                        ColumnLayout {
                            visible: store.activePage === "overview"
                            Layout.fillWidth: true
                            spacing: 20
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16
                                Repeater {
                                    model: [
                                        { label: "估算成本", value: rootCost(), tint: "#f09578" },
                                        { label: "Token", value: rootTokens(), tint: "#79aef7" },
                                        { label: "活跃工具", value: activeTools(), tint: "#af9af4" },
                                        { label: "模型数量", value: modelCount(), tint: "#75d6ae" }
                                    ]
                                    delegate: SummaryCard { Layout.fillWidth: true }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "工具用量"; color: ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                DarkComboBox {
                                    id: cardPeriodCombo
                                    objectName: "cardPeriodCombo"
                                    Layout.preferredWidth: 138
                                    model: ["今天", "昨天", "本周", "上周", "本月", "今年"]
                                    currentIndex: store.cardPeriod === "today" ? 0 : store.cardPeriod === "yesterday" ? 1 : store.cardPeriod === "week" ? 2 : store.cardPeriod === "lastweek" ? 3 : store.cardPeriod === "month" ? 4 : 5
                                    onActivated: store.setCardPeriod(["today", "yesterday", "week", "lastweek", "month", "year"][currentIndex])
                                }
                                Text { text: "每 " + (store.settings.refresh_seconds || 60) + " 秒更新"; color: soft; font.pixelSize: 10 }
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 850 ? 3 : 2
                                columnSpacing: 16; rowSpacing: 16
                                Repeater {
                                    model: store.cards
                                    delegate: ToolCard {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 196
                                        onClicked: win.showToolDetails(title, totalTokensDisplay, model_details)
                                    }
                                }
                            }
                            Rectangle {
                                visible: store.cards.length === 0
                                Layout.fillWidth: true; height: 160; radius: 18
                                color: "#1a1e26"; border.color: "#2c333f"
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: store.busy ? "正在读取用量" : "暂无可显示的数据"; color: ink; font.pixelSize: 15; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: "安装并使用受支持的 AI 编程工具后，数据会显示在这里。"; color: soft; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "dashboard"
                            Layout.fillWidth: true; spacing: 18
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "成本与 Token 趋势"; color: ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
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
                                id: modelRankingCard
                                property var rankingRows: (store.dashboard.models || []).slice(0, 12).map(function(item) { return { name: item.name || "未知模型", tokensDisplay: item.tokens_display || "0", cost: Number(item.cost || 0) } })
                                Layout.fillWidth: true
                                implicitHeight: rankingRows.length > 0 ? 78 + rankingRows.length * 24 : 126
                                radius: 18
                                color: "#171b23"; border.color: "#2b323e"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 20; spacing: 12
                                    Text { text: "模型用量排行"; color: ink; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: modelRankingCard.rankingRows.length > 0 ? modelRankingCard.rankingRows.length * 24 : 0
                                        visible: modelRankingCard.rankingRows.length > 0
                                        clip: true
                                        interactive: false
                                        model: modelRankingCard.rankingRows
                                        delegate: ModelRow {
                                            width: ListView.view.width
                                            height: 24
                                        }
                                    }
                                    Text {
                                        visible: modelRankingCard.rankingRows.length === 0
                                        text: store.busy ? "正在整理模型用量…" : "当前周期暂无模型数据"
                                        color: soft; font.pixelSize: 11
                                        Layout.preferredHeight: 40
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "projects"
                            Layout.fillWidth: true; spacing: 16
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "项目贡献"; color: ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
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
                            Layout.fillWidth: true; spacing: 16
                            Text { text: "额度周期历史"; color: ink; font.pixelSize: 17; font.weight: Font.DemiBold }
                            Repeater {
                                model: (store.quotaHistory.cycles || []).map(function(cycle) { return { cycle: cycle, tokensDisplay: cycle.tokens_display || "0" } })
                                delegate: QuotaCycleCard { Layout.fillWidth: true }
                            }
                            Rectangle {
                                visible: (store.quotaHistory.cycles || []).length === 0
                                Layout.fillWidth: true; height: 160; radius: 18
                                color: "#1a1e26"; border.color: "#2c333f"
                                Text { anchors.centerIn: parent; text: store.busy ? "读取额度历史…" : "暂时没有可绘制的额度周期"; color: soft; font.pixelSize: 12 }
                            }
                        }

                        ColumnLayout {
                            visible: store.activePage === "settings"
                            Layout.fillWidth: true; spacing: 18
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 450; radius: 18
                                color: "#171b23"; border.color: "#2b323e"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 20; spacing: 14
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
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b323e" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "Tokei 运行时保持电脑唤醒"; color: ink; font.pixelSize: 12 }
                                            Text { text: "关闭应用后恢复 Windows 电源策略"; color: soft; font.pixelSize: 10 }
                                        }
                                        Switch { checked: store.settings.keep_awake === true; onToggled: store.setKeepAwake(checked) }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b323e" }
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
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b323e" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text { text: "隐藏到托盘时显示桌面浮窗"; color: ink; font.pixelSize: 12 }
                                            Text { text: "展示今日用量排名前三的工具，可拖动和调整大小"; color: soft; font.pixelSize: 10; wrapMode: Text.WordWrap }
                                        }
                                        Switch { checked: store.settings.show_floating_widget !== false; onToggled: store.setFloatingWidgetEnabled(checked) }
                                    }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b323e" }
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
                                Layout.fillWidth: true; implicitHeight: 390; radius: 18
                                color: "#171b23"; border.color: "#2b323e"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 20; spacing: 14
                                    Text { text: "可选额度来源"; color: ink; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { text: "API 密钥保存在 Windows 凭据管理器；额度查询默认关闭。"; color: soft; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Sub2API"; color: ink; font.pixelSize: 12; Layout.fillWidth: true }
                                        Switch { checked: store.settings.sub2api_quota_enabled === true; onToggled: store.setProviderEnabled("sub2api", checked) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        TextField { id: sub2apiUrl; text: store.settings.sub2api_base_url || ""; placeholderText: "https://你的 Sub2API 域名"; placeholderTextColor: "#778396"; Layout.fillWidth: true; Layout.preferredHeight: 40; color: ink; background: Rectangle { radius: 10; color: "#141922"; border.color: sub2apiUrl.activeFocus ? "#6f96c9" : "#333c4a"; Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } } } }
                                        Button {
                                            id: saveSub2ApiUrl
                                            text: "保存地址"
                                            hoverEnabled: true
                                            onClicked: store.setProviderSetting("sub2api", "sub2api_base_url", sub2apiUrl.text)
                                            contentItem: Text { text: saveSub2ApiUrl.text; color: "#f1f4f9"; font.pixelSize: 11; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 10; color: saveSub2ApiUrl.down ? "#344863" : saveSub2ApiUrl.hovered ? "#2b3a4e" : "#222a36"; border.color: saveSub2ApiUrl.hovered ? "#536d8d" : "#3a4657"; Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } } }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        TextField { id: sub2apiKey; placeholderText: "Sub2API API Key（留空删除）"; placeholderTextColor: "#778396"; echoMode: TextInput.Password; Layout.fillWidth: true; Layout.preferredHeight: 40; color: ink; background: Rectangle { radius: 10; color: "#141922"; border.color: sub2apiKey.activeFocus ? "#6f96c9" : "#333c4a"; Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } } } }
                                        Button {
                                            id: saveSub2ApiKey
                                            text: "保存"
                                            hoverEnabled: true
                                            onClicked: { store.saveCredential("sub2api", sub2apiKey.text); sub2apiKey.clear() }
                                            contentItem: Text { text: saveSub2ApiKey.text; color: "#f1f4f9"; font.pixelSize: 11; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 10; color: saveSub2ApiKey.down ? "#344863" : saveSub2ApiKey.hovered ? "#2b3a4e" : "#222a36"; border.color: saveSub2ApiKey.hovered ? "#536d8d" : "#3a4657"; Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } } }
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
                                        TextField { id: zaiKey; placeholderText: "z.ai API Key（留空删除）"; placeholderTextColor: "#778396"; echoMode: TextInput.Password; Layout.fillWidth: true; Layout.preferredHeight: 40; color: ink; background: Rectangle { radius: 10; color: "#141922"; border.color: zaiKey.activeFocus ? "#6f96c9" : "#333c4a"; Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } } } }
                                        Button {
                                            id: saveZaiKey
                                            text: "保存"
                                            hoverEnabled: true
                                            onClicked: { store.saveCredential("zai", zaiKey.text); zaiKey.clear() }
                                            contentItem: Text { text: saveZaiKey.text; color: "#f1f4f9"; font.pixelSize: 11; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Rectangle { radius: 10; color: saveZaiKey.down ? "#344863" : saveZaiKey.hovered ? "#2b3a4e" : "#222a36"; border.color: saveZaiKey.hovered ? "#536d8d" : "#3a4657"; Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } } }
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

    // 总览顶部四项与「工具用量」下拉同口径:都按 store.cardPeriod 取 ranges 里对应的周期桶。
    function periodKey() { return store.cardPeriod || "today" }
    function periodRange(key) { return (((store.snapshot || {})[key] || {}).ranges || {})[periodKey()] || {} }
    function rootCost() {
        var total = 0; var keys = Object.keys(store.snapshot || {})
        for (var i = 0; i < keys.length; i++) total += Number(periodRange(keys[i]).cost || 0)
        return "$" + Number(total).toFixed(2)
    }
    function rootTokens() {
        var total = 0; var keys = Object.keys(store.snapshot || {})
        for (var i = 0; i < keys.length; i++) { var r = periodRange(keys[i]); total += Number(r.in || 0) + Number(r.out || 0) + Number(r.cached || 0) + Number(r.cr || 0) + Number(r.cw || 0) + Number(r.reason || 0) }
        return pretty(total)
    }
    function activeTools() { var n = 0; var list = store.cards || []; for (var i = 0; i < list.length; i++) if (list[i].metrics.length || list[i].quotas.length) n++; return String(n) }
    // 模型数量同样按该周期统计:跨工具按模型名去重(与卡片弹窗的模型行同源)。
    function modelCount() {
        var seen = {}; var n = 0; var keys = Object.keys(store.snapshot || {})
        for (var i = 0; i < keys.length; i++) {
            var list = periodRange(keys[i]).models || []
            for (var j = 0; j < list.length; j++) {
                var name = String(list[j].name || "").toLowerCase()
                if (name && !seen[name]) { seen[name] = true; n++ }
            }
        }
        return String(n)
    }
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
        opacity: 0.97
        title: "Tokei 今日用量"

        Rectangle {
            id: floatingPanel
            anchors.fill: parent
            anchors.margins: 1
            radius: 16
            color: "#171b23"
            border.color: "#394553"
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
                        Text { text: "今日工具用量"; color: "#f2f5fa"; font.pixelSize: Math.max(12, Math.min(16, floatingWindow.width / 23)); font.weight: Font.DemiBold }
                        Text { text: store.lastUpdated; color: "#8994a4"; font.pixelSize: Math.max(8, Math.min(10, floatingWindow.width / 36)) }
                    }
                    Rectangle {
                        Layout.preferredWidth: 25; Layout.preferredHeight: 25; radius: 7
                        color: floatingCloseMouse.containsMouse ? "#293443" : "transparent"
                        Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: "×"; color: "#c7d0de"; font.pixelSize: 18 }
                        MouseArea { id: floatingCloseMouse; anchors.fill: parent; hoverEnabled: true; onClicked: store.setFloatingVisible(false) }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b323e" }

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
                        Text { text: toolTitle; color: "#dce3ed"; font.pixelSize: Math.max(10, Math.min(13, floatingWindow.width / 28)); Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: tokensDisplay + " Token"; color: "#f0a487"; font.pixelSize: Math.max(8, Math.min(13, floatingWindow.width / 34)); font.weight: Font.Medium; horizontalAlignment: Text.AlignRight }
                    }
                }

                Text {
                    visible: store.floatingTools.length === 0
                    text: "今天还没有可显示的 Token 用量"
                    color: "#a5afbe"
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
                Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 9; height: 9; color: "transparent"; border.color: "#7186a2"; rotation: 45 }
            }
        }

        onClosing: function(close) { close.accepted = false; store.setFloatingVisible(false) }
    }
}
