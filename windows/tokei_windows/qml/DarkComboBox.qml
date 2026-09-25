pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    palette.text: "#e6e6ea"

    contentItem: Text {
        leftPadding: 10
        rightPadding: 34
        text: control.displayText
        color: "#e6e6ea"
        font.pixelSize: 11
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Item {
        width: 30
        height: control.height
        x: control.width - width
        y: 0

        Canvas {
            id: arrow
            width: 12
            height: 8
            anchors.centerIn: parent

            onPaint: {
                var context = getContext("2d")
                context.clearRect(0, 0, width, height)
                context.beginPath()
                context.moveTo(2, 2)
                context.lineTo(width / 2, height - 2)
                context.lineTo(width - 2, 2)
                context.strokeStyle = "#a6a7b0"
                context.lineWidth = 1.5
                context.lineCap = "round"
                context.lineJoin = "round"
                context.stroke()
            }
        }
    }

    delegate: ItemDelegate {
        id: optionDelegate
        required property int index
        width: control.width - 8
        height: 36
        text: control.textAt(optionDelegate.index)
        highlighted: control.highlightedIndex === optionDelegate.index
        hoverEnabled: true

        contentItem: Text {
            text: optionDelegate.text
            leftPadding: 10
            color: "#e6e6ea"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 5
            color: optionDelegate.highlighted ? "#473435" : optionDelegate.hovered ? "#34353d" : "transparent"
        }
    }

    popup: Popup {
        y: control.height - 1
        width: control.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + padding * 2, 224)

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Rectangle {
            color: "#25262d"
            border.color: "#555660"
            radius: 8
        }
    }

    background: Rectangle {
        radius: 8
        color: control.down ? "#32333b" : "#2c2d34"
        border.color: control.activeFocus ? "#a75c4b" : "#464750"
        border.width: control.activeFocus ? 1.3 : 1
    }
}
