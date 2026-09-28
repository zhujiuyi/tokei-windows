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
    required property var model_details
    property bool hovered: false
    property bool pressed: false
    signal clicked()
    radius: 18
    color: hovered ? "#202630" : "#1a1e26"
    border.color: hovered ? root.tint : "#2a303b"
    border.width: hovered ? 1.4 : 1
    scale: pressed ? 0.99 : hovered ? 1.008 : 1
    clip: true

    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on border.width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: root.pressed ? 90 : 160; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        opacity: root.hovered ? 0.075 : 0.025
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: "#ffffff"
        opacity: 0.06
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 11

        RowLayout {
            Layout.fillWidth: true
            spacing: 9
            Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: root.tint }
            Text {
                text: root.title
                color: "#f2f5fa"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text { text: root.totalTokensDisplay + " Token"; color: root.tint; font.pixelSize: 10; font.weight: Font.DemiBold }
            Text { text: root.status; color: "#929baa"; font.pixelSize: 9 }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 18
            rowSpacing: 8

            Repeater {
                model: root.metrics
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Text { text: modelData.label; color: "#929baa"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.value; color: "#dce3ed"; font.pixelSize: 10; font.weight: Font.Medium }
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
                    Text { text: modelData.label; color: "#a5afbe"; font.pixelSize: 10; Layout.fillWidth: true }
                    Text {
                        text: modelData.stale ? "已过期" : "余 " + Number(modelData.remaining).toFixed(0) + "%"
                        color: modelData.stale ? "#e6aa77" : root.tint
                        font.pixelSize: 10
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 3
                    color: "#333a46"
                    Rectangle {
                        width: parent.width * Number(modelData.used) / 100
                        height: parent.height
                        radius: 3
                        color: root.tint
                        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onPressedChanged: root.pressed = pressed
        onClicked: root.clicked()
    }
}
