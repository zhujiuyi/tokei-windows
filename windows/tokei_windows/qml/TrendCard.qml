import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    objectName: "trendCard"
    required property var points
    property int selectedIndex: -1
    radius: 16
    color: "#25262d"
    border.color: "#41424b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text { text: "每日成本"; color: "#f7f6f8"; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Text { text: root.points.length + " 天"; color: "#9697a0"; font.pixelSize: 10 }
        }

        Item {
            id: plot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 90

            Canvas {
                id: chart
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var values = []
                    for (var i = 0; i < root.points.length; i++) values.push(Number(root.points[i].total_cost || 0))
                    if (!values.length) return

                    var maxV = Math.max(1, Math.max.apply(null, values))
                    var left = 8
                    var right = width - 8
                    var top = 14
                    var bottom = height - 8
                    ctx.strokeStyle = "#41424b"
                    ctx.lineWidth = 1
                    for (var grid = 0; grid < 4; grid++) {
                        var gy = top + (bottom - top) * grid / 3
                        ctx.beginPath()
                        ctx.moveTo(left, gy)
                        ctx.lineTo(right, gy)
                        ctx.stroke()
                    }

                    ctx.beginPath()
                    ctx.lineWidth = 2.5
                    ctx.strokeStyle = "#eb8566"
                    for (var k = 0; k < values.length; k++) {
                        var x = left + (right - left) * (values.length === 1 ? 0.5 : k / (values.length - 1))
                        var y = bottom - (bottom - top) * values[k] / maxV
                        if (k === 0) ctx.moveTo(x, y)
                        else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                    ctx.lineTo(right, bottom)
                    ctx.lineTo(left, bottom)
                    ctx.closePath()
                    var fill = ctx.createLinearGradient(0, top, 0, bottom)
                    fill.addColorStop(0, "rgba(235,133,102,0.26)")
                    fill.addColorStop(1, "rgba(235,133,102,0.01)")
                    ctx.fillStyle = fill
                    ctx.fill()

                    if (root.selectedIndex >= 0 && root.selectedIndex < values.length) {
                        var selectedX = left + (right - left) * (values.length === 1 ? 0.5 : root.selectedIndex / (values.length - 1))
                        var selectedY = bottom - (bottom - top) * values[root.selectedIndex] / maxV
                        ctx.beginPath()
                        ctx.arc(selectedX, selectedY, 4, 0, Math.PI * 2)
                        ctx.fillStyle = "#fff1ec"
                        ctx.fill()
                        ctx.beginPath()
                        ctx.arc(selectedX, selectedY, 7, 0, Math.PI * 2)
                        ctx.strokeStyle = "rgba(235,133,102,0.72)"
                        ctx.lineWidth = 2
                        ctx.stroke()
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections { target: store; function onSnapshotChanged() { chart.requestPaint() } }
                Connections { target: store; function onPeriodChanged() { chart.requestPaint() } }
                Connections { target: root; function onSelectedIndexChanged() { chart.requestPaint() } }
            }

            MouseArea {
                id: chartMouse
                objectName: "trendChartMouse"
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                    if (root.points.length < 1) return
                    var left = 8
                    var right = chart.width - 8
                    var ratio = Math.max(0, Math.min(1, (mouse.x - left) / Math.max(1, right - left)))
                    root.selectedIndex = Math.round(ratio * (root.points.length - 1))
                }
                onExited: root.selectedIndex = -1
            }

            Rectangle {
                id: tooltip
                visible: chartMouse.containsMouse && root.selectedIndex >= 0 && root.selectedIndex < root.points.length
                enabled: false
                z: 2
                width: 156
                height: 61
                x: Math.max(4, Math.min(plot.width - width - 4, chartMouse.mouseX + 12))
                y: Math.max(3, chartMouse.mouseY - height - 9)
                radius: 9
                color: "#ed17181d"
                border.color: "#8b6157"

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 3
                    Text { text: root.selectedIndex >= 0 ? (root.points[root.selectedIndex].date_label || String(root.points[root.selectedIndex].date || "").slice(5)) : ""; color: "#d6d6dc"; font.pixelSize: 9 }
                    Text { text: root.selectedIndex >= 0 ? "成本  $" + Number(root.points[root.selectedIndex].total_cost || 0).toFixed(2) : ""; color: "#f1b39f"; font.pixelSize: 10; font.weight: Font.Medium }
                    Text { text: root.selectedIndex >= 0 ? "Token  " + (root.points[root.selectedIndex].tokens_display || "0") : ""; color: "#e6e6ea"; font.pixelSize: 10 }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 15
            spacing: 2
            Repeater {
                model: root.dateLabels()
                delegate: Text {
                    required property string modelData
                    text: modelData
                    color: "#9697a0"
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    function dateLabels() {
        var labels = []
        var count = root.points.length
        if (count === 0) return labels
        var labelCount = Math.min(7, count)
        for (var i = 0; i < labelCount; i++) {
            var index = labelCount === 1 ? 0 : Math.round(i * (count - 1) / (labelCount - 1))
            var point = root.points[index] || {}
            labels.push(point.date_label || String(point.date || "").slice(5))
        }
        return labels
    }
}
