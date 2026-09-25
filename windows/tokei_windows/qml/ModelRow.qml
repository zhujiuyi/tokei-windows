import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property string name
    required property string tokensDisplay
    required property real cost
    spacing: 12

    Text { text: root.name; color: "#dedee3"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
    Text { text: root.tokensDisplay + " tok"; color: "#a6a7b0"; font.pixelSize: 9; Layout.preferredWidth: 120; horizontalAlignment: Text.AlignRight }
    Text { text: "$" + Number(root.cost || 0).toFixed(2); color: "#d9b0a7"; font.pixelSize: 9; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
}
