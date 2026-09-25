import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string title
    required property string totalTokensDisplay
    required property color tint
    required property string status
    required property var metrics
    required property var quotas
    radius: 16
    color: "#25262d"
    border.color: "#41424b"

    Rectangle { anchors.fill: parent; radius: 16; color: root.tint; opacity: 0.045 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 7
            Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: root.tint }
            Text {
                text: root.title
                color: "#f7f6f8"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text { text: root.totalTokensDisplay + " Token"; color: root.tint; font.pixelSize: 9; font.weight: Font.Medium }
            Text { text: root.status; color: "#9d9ea8"; font.pixelSize: 9 }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 7

            Repeater {
                model: root.metrics
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Text { text: modelData.label; color: "#a6a7b0"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.value; color: "#e6e6ea"; font.pixelSize: 10; font.weight: Font.Medium }
                }
            }
        }

        Repeater {
            model: root.quotas
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: modelData.label; color: "#b7b7c0"; font.pixelSize: 9; Layout.fillWidth: true }
                    Text {
                        text: modelData.stale ? "已过期" : "余 " + Number(modelData.remaining).toFixed(0) + "%"
                        color: modelData.stale ? "#e6aa77" : root.tint
                        font.pixelSize: 9
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 3
                    color: "#42434a"
                    Rectangle {
                        width: parent.width * Number(modelData.used) / 100
                        height: parent.height
                        radius: 3
                        color: root.tint
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
