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
    implicitHeight: 112
    radius: 15
    color: "#25262d"
    border.color: "#41424b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text { text: root.name; color: "#f7f6f8"; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Text { text: "$" + Number(root.cost || 0).toFixed(2); color: "#ebaa95"; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
        Text { text: root.path; color: "#92939d"; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideMiddle }
        RowLayout {
            Layout.fillWidth: true
            Text { text: root.tokensDisplay + " Token"; color: "#c9c9ce"; font.pixelSize: 10; Layout.fillWidth: true }
            Text { text: Number(root.sessions || 0) + " 会话"; color: "#a6a7b0"; font.pixelSize: 10 }
            Text { text: root.tools.join(" · "); color: "#999aa4"; font.pixelSize: 9; Layout.preferredWidth: 190; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
        }
    }
}
