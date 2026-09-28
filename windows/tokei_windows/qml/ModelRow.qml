import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property string name
    required property string tokensDisplay
    required property real cost
    implicitHeight: 24
    spacing: 12
    clip: true

    Text { text: root.name; color: "#dce3ed"; font.pixelSize: 11; Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight }
    Text { text: root.tokensDisplay + " tok"; color: "#a5afbe"; font.pixelSize: 10; Layout.preferredWidth: 120; horizontalAlignment: Text.AlignRight }
    Text { text: "$" + Number(root.cost || 0).toFixed(2); color: "#f0a487"; font.pixelSize: 10; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
}
