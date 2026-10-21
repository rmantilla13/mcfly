import QtQuick

// "McFly" in the logo's face, Exo 2 Black Italic (resources/fonts, SIL OFL),
// as the boot clip, the apps and the console set it.
Text {
    text: "McFly"
    color: "white"
    font.family: exo.font.family
    font.styleName: exo.font.styleName
    font.weight: exo.font.weight
    font.italic: true
    font.pixelSize: 32
    renderType: Text.QtRendering

    FontLoader {
        id: exo
        source: "qrc:/McFly/resources/fonts/Exo2-BlackItalic.ttf"
    }
}
