import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var cycle
    implicitHeight: 94
    radius: 15
    color: "#25262d"
    border.color: "#41424b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.cycle.tool === "claude" ? "Claude Code" : root.cycle.tool === "codex" ? "Codex" : root.cycle.tool
                color: "#f7f6f8"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Text { text: root.cycle.current ? "当前周期" : "历史周期"; color: root.cycle.current ? "#70d6a1" : "#999aa4"; font.pixelSize: 9 }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "消耗 " + Number(root.cycle.used_pct || 0).toFixed(1) + "%"; color: "#d9b0a7"; font.pixelSize: 10; Layout.fillWidth: true }
            Text { text: Number(root.cycle.tokens || 0).toLocaleString() + " Token"; color: "#c6c6cc"; font.pixelSize: 10 }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: 3
            color: "#42434a"
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, Number(root.cycle.used_pct || 0))) / 100
                height: parent.height
                radius: 3
                color: root.cycle.tool === "claude" ? "#eb8566" : "#6babfa"
            }
        }
    }
}
