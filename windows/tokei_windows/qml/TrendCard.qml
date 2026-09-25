import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var points
    radius: 16
    color: "#25262d"
    border.color: "#41424b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "每日成本"; color: "#f7f6f8"; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Text { text: root.points.length + " 天"; color: "#9697a0"; font.pixelSize: 10 }
        }

        Canvas {
            id: chart
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                var bottom = height - 28
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

                ctx.fillStyle = "#9697a0"
                ctx.font = "10px sans-serif"
                var stride = Math.max(1, Math.floor(root.points.length / 6))
                for (var n = 0; n < root.points.length; n += stride) {
                    var px = left + (right - left) * (values.length === 1 ? 0.5 : n / (values.length - 1))
                    ctx.fillText(String(root.points[n].d || "").slice(5), px - 18, height - 6)
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections { target: store; function onSnapshotChanged() { chart.requestPaint() } }
            Connections { target: store; function onPeriodChanged() { chart.requestPaint() } }
        }
    }
}
