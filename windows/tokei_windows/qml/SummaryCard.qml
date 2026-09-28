import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string label
    required property string value
    required property color tint
    implicitHeight: 112
    radius: 18
    color: "#1a1e26"
    border.color: "#2a303b"
    border.width: 1
    clip: true

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: "#ffffff"
        opacity: 0.055
    }

    Rectangle {
        x: 0
        y: 20
        width: 3
        height: parent.height - 40
        radius: 2
        color: root.tint
        opacity: 0.9
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 19
        anchors.rightMargin: 16
        anchors.topMargin: 17
        anchors.bottomMargin: 15
        spacing: 10

        Text {
            text: root.label
            color: "#929baa"
            font.pixelSize: 11
            font.weight: Font.Medium
        }
        Text {
            text: root.value
            color: "#f2f5fa"
            font.pixelSize: 25
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}
