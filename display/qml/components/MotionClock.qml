import QtQuick
import McFly

// The clock for a slow loop drawn in QML (a breath, a picture's Ken Burns):
// `time`, in seconds, moves on the wall-clock slots of 1/fps s that
// GradientTile, Backdrop, AuroraGlow and SpectrumGlow keep, so everything
// ambient changes on the same frames and the render loop sleeps in between.
// An Animator steps on every frame the panel draws, 60 a second for a drift
// of a pixel a second, and kept News and Projects drawing all the time with
// nobody touching them.
//
//   MotionClock { id: clock; playing: card.breathes }
//   opacity: 0.2 * (1 - Math.cos(Math.PI * clock.time / 2.2))
//
// Stopped, `time` holds where it was, so starting again never jumps. A step
// is never negative and at most 0.1 s, so a stall or a jump of the wall
// clock can't throw it far ahead.
Timer {
    id: clock

    property bool playing: false
    property int fps: Theme.motionFps
    property real time: 0

    property real _last: 0
    onPlayingChanged: _arm(true)
    onFpsChanged: _arm(false)
    Component.onCompleted: _arm(true)
    function _arm(fresh) {
        if (fresh)
            _last = Date.now()
        if (!playing || fps <= 0) {
            stop()
            return
        }
        const slot = 1000 / fps
        interval = Math.max(1, Math.ceil(slot - Date.now() % slot))
        restart()
    }
    onTriggered: {
        const now = Date.now()
        time += Math.max(0, Math.min((now - _last) / 1000, 0.1))
        _last = now
        _arm(false)
    }
}
