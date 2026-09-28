import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string name
    required property string path
    required property string tokensDisplay
    required property var cost
    required property var sessions
    required property var tools
    implicitHeight: 120
    radius: 18
    color: "#1a1e26"
    border.color: "#2a303b"
    border.width: 1

    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: "#ffffff"; opacity: 0.055 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 17
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            Text { text: root.name; color: "#f2f5fa"; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Text { text: "$" + Number(root.cost || 0).toFixed(2); color: "#f0a487"; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
        Text { text: root.path; color: "#8994a4"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
        RowLayout {
            Layout.fillWidth: true
            Text { text: root.tokensDisplay + " Token"; color: "#dce3ed"; font.pixelSize: 11; Layout.fillWidth: true }
            Text { text: Number(root.sessions || 0) + " 会话"; color: "#a5afbe"; font.pixelSize: 10 }
            Text { text: root.tools.join(" · "); color: "#8994a4"; font.pixelSize: 10; Layout.preferredWidth: 190; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
        }
    }
}
