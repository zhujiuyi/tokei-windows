pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    // 与相邻控件对齐:右上角按钮与设置页输入框 40、窗口图标按钮 34,取 36 兼顾两种行高。
    // 不设高度时控件由 11px 文本撑出(约 22–26px),在按钮/开关旁边显得"扁"。
    implicitHeight: 36

    palette.text: "#e6ebf3"

    contentItem: Text {
        leftPadding: 10
        rightPadding: 34
        text: control.displayText
        color: "#e6ebf3"
        font.pixelSize: 12
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
                context.strokeStyle = "#a5afbe"
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
            color: "#e6ebf3"
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 7
            color: optionDelegate.highlighted ? "#293444" : optionDelegate.hovered ? "#252b35" : "transparent"
        }
    }

    popup: Popup {
        y: control.height - 1
        width: control.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + padding * 2, 224)
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90; easing.type: Easing.InCubic } }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Rectangle {
            color: "#1b2028"
            border.color: "#343c49"
            radius: 10
        }
    }

    background: Rectangle {
        radius: 10
        color: control.down ? "#252b35" : control.hovered ? "#242a34" : "#20252e"
        border.color: control.activeFocus ? "#86aef0" : control.hovered ? "#465365" : "#343c49"
        border.width: control.activeFocus ? 1.3 : 1
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
}
