import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import McFly

// "Read it on your phone": a QR code of a url on a white square, with a
// title, a line of help and the domain. Used by the story detail and Setup.
Rectangle {
    id: panel
    property string url: ""
    property string title: qsTr("Read it on your phone")
    property string caption: qsTr("Point the camera at the code to open the article.")
    property string domain: ""
    property int codeSize: Theme.small ? 112 : 148

    implicitHeight: codeSize + 32
    radius: Theme.radiusSm
    color: Theme.surface

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 18
        Rectangle {
            Layout.preferredWidth: panel.codeSize
            Layout.preferredHeight: panel.codeSize
            radius: 12
            color: "white"
            Image {
                anchors.centerIn: parent
                width: parent.width - 8; height: width
                source: panel.url ? "image://qr/" + encodeURIComponent(panel.url) : ""
                sourceSize: Qt.size(width, width)
                smooth: false
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Label { text: panel.title; color: Theme.text; font.pixelSize: Theme.fontSm + 1; font.weight: Font.DemiBold }
            Label { Layout.fillWidth: true; text: panel.caption; color: Theme.textMuted; font.pixelSize: Theme.fontXs + 1; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; visible: text.length > 0; text: panel.domain; color: Theme.accent; font.pixelSize: Theme.fontSm; font.weight: Font.Medium; elide: Text.ElideRight }
        }
    }
}
