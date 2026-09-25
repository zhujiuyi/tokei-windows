import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string label
    required property string value
    required property color tint
    implicitHeight: 104
    radius: 16
    color: "#25262d"
    border.color: "#41424b"

    Rectangle {
        x: 0
        y: 16
        width: 3
        height: parent.height - 32
        radius: 2
        color: root.tint
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text { text: root.label; color: "#b7b7c0"; font.pixelSize: 11 }
        Text {
            text: root.value
            color: "#faf9fb"
            font.pixelSize: 23
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
