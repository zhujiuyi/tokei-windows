import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var cycle
    required property string tokensDisplay
    implicitHeight: 102
    radius: 18
    color: "#1a1e26"
    border.color: "#2a303b"
    border.width: 1

    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: "#ffffff"; opacity: 0.055 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 17
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.cycle.tool === "claude_desktop" ? "Claude Code Desktop" : root.cycle.tool === "claude" ? "Claude Code" : root.cycle.tool === "codex" ? "Codex" : root.cycle.tool
                color: "#f2f5fa"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Text { text: root.cycle.current ? "当前周期" : "历史周期"; color: root.cycle.current ? "#75d6ae" : "#8994a4"; font.pixelSize: 10 }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "消耗 " + Number(root.cycle.used_pct || 0).toFixed(1) + "%"; color: "#f0a487"; font.pixelSize: 10; Layout.fillWidth: true }
            Text { text: root.tokensDisplay + " Token"; color: "#c7d0de"; font.pixelSize: 10 }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: 3
            color: "#333a46"
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, Number(root.cycle.used_pct || 0))) / 100
                height: parent.height
                radius: 3
                color: root.cycle.tool === "claude" ? "#f09578" : root.cycle.tool === "claude_desktop" ? "#f2b06a" : "#79aef7"
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            }
        }
    }
}
