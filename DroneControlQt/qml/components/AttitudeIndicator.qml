// AttitudeIndicator.qml - artificial horizon + roll scale + compass rose
// (port of AttitudeIndicator.swift, drawn with Canvas)
import QtQuick
import DroneControl 1.0

Item {
    id: root
    property real roll: 0
    property real pitch: 0
    property real heading: 0
    property bool showHeadingBox: true

    // Outer size of the item; the instrument itself is drawn a little smaller so the
    // compass rose around the ring is not clipped.
    readonly property real size: Math.min(width, height) * 0.82

    onRollChanged: canvas.requestPaint()
    onPitchChanged: canvas.requestPaint()
    onHeadingChanged: canvas.requestPaint()
    onSizeChanged: canvas.requestPaint()

    function cardinalDirection(h) {
        var d = Math.round(h) % 360
        if (d < 0) d += 360
        if (d >= 337 || d < 23) return "N"
        if (d < 68) return "NE"
        if (d < 113) return "E"
        if (d < 158) return "SE"
        if (d < 203) return "S"
        if (d < 248) return "SW"
        if (d < 293) return "W"
        return "NW"
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height
            var s = root.size
            var cx = w / 2, cy = h / 2
            var r = s / 2
            ctx.reset()
            ctx.clearRect(0, 0, w, h)

            // Background circle
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fillStyle = Theme.card
            ctx.fill()

            // --- Horizon (clipped to circle, rotated by -roll, shifted by pitch) ---
            ctx.save()
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.clip()
            ctx.translate(cx, cy)
            ctx.rotate(-root.roll * Math.PI / 180)
            ctx.translate(0, root.pitch * s / 60.0)

            var sky = ctx.createLinearGradient(0, -s, 0, 0)
            sky.addColorStop(0, "#3366CC")
            sky.addColorStop(1, "#6699E6")
            ctx.fillStyle = sky
            ctx.fillRect(-s * 1.5, -s * 2, s * 3, s * 2)

            var ground = ctx.createLinearGradient(0, 0, 0, s)
            ground.addColorStop(0, "#664D33")
            ground.addColorStop(1, "#4D331A")
            ctx.fillStyle = ground
            ctx.fillRect(-s * 1.5, 0, s * 3, s * 2)

            // Horizon line
            ctx.fillStyle = Theme.white
            ctx.fillRect(-s * 1.5, -1.5, s * 3, 3)

            // Pitch ladder
            ctx.font = "500 " + Math.max(8, s * 0.05) + "px " + Theme.mono
            ctx.textBaseline = "middle"
            var ladder = [-20, -10, 10, 20]
            for (var i = 0; i < ladder.length; i++) {
                var a = ladder[i]
                var y = -a * s / 60.0
                var lw = s * 0.3
                ctx.fillStyle = Theme.white
                ctx.fillRect(-lw / 2, y - 1, lw, 2)
                ctx.textAlign = "right"
                ctx.fillText(String(Math.abs(a)), -lw / 2 - 4, y)
                ctx.textAlign = "left"
                ctx.fillText(String(Math.abs(a)), lw / 2 + 4, y)
            }
            ctx.restore()

            // --- Aircraft reference symbol (yellow) ---
            ctx.fillStyle = Theme.yellow
            ctx.fillRect(cx - s * 0.2, cy - 1.5, s * 0.15, 3)
            ctx.fillRect(cx + s * 0.05, cy - 1.5, s * 0.15, 3)
            ctx.beginPath()
            ctx.arc(cx, cy, 4, 0, Math.PI * 2)
            ctx.fill()
            ctx.fillRect(cx - 1.5, cy, 3, s * 0.08)

            // --- Outer ring ---
            ctx.beginPath()
            ctx.arc(cx, cy, r - 1, 0, Math.PI * 2)
            ctx.strokeStyle = Theme.white
            ctx.lineWidth = 2
            ctx.stroke()

            // --- Roll marks ---
            var marks = [0, 10, 20, 30, 45, 60]
            for (var m = 0; m < marks.length; m++) {
                var ang = marks[m]
                var len = (ang === 0 || ang === 30 || ang === 60) ? s * 0.08 : s * 0.05
                var sides = ang === 0 ? [1] : [1, -1]
                for (var k = 0; k < sides.length; k++) {
                    ctx.save()
                    ctx.translate(cx, cy)
                    ctx.rotate(sides[k] * ang * Math.PI / 180)
                    ctx.fillStyle = Theme.white
                    ctx.fillRect(-1, -s * 0.46 - len / 2, 2, len)
                    ctx.restore()
                }
            }

            // --- Compass rose (rotates with heading) ---
            var cardinals = [["N", 0], ["E", 90], ["S", 180], ["W", 270]]
            ctx.textAlign = "center"
            ctx.textBaseline = "bottom"
            for (var c = 0; c < cardinals.length; c++) {
                var name = cardinals[c][0]
                var angle = cardinals[c][1]
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate((angle - root.heading) * Math.PI / 180)
                var col = name === "N" ? Theme.red : Theme.white
                ctx.fillStyle = col
                ctx.fillRect(-1, -s * 0.54 + s * 0.01, 2, s * 0.04)
                ctx.font = "bold " + Math.max(8, s * 0.05) + "px sans-serif"
                ctx.fillText(name, 0, -s * 0.54 + s * 0.01 - 2)
                ctx.restore()
            }
            var inter = [["NE", 45], ["SE", 135], ["SW", 225], ["NW", 315]]
            for (var q = 0; q < inter.length; q++) {
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate((inter[q][1] - root.heading) * Math.PI / 180)
                ctx.fillStyle = Theme.gray
                ctx.fillRect(-0.5, -s * 0.54 + s * 0.02, 1, s * 0.03)
                ctx.font = "500 " + Math.max(7, s * 0.04) + "px sans-serif"
                ctx.fillText(inter[q][0], 0, -s * 0.54 + s * 0.02 - 2)
                ctx.restore()
            }
        }
    }

    // Heading readout (cardinal + numeric), top-left like the iOS app
    Column {
        visible: root.showHeadingBox
        spacing: 8
        x: Math.max(0, (root.width - root.size) / 2 - root.size * 0.12)
        y: Math.max(0, (root.height - root.size) / 2 - root.size * 0.02)

        Rectangle {
            radius: height / 2
            color: Theme.buttonBlue1
            width: cardText.implicitWidth + 16
            height: cardText.implicitHeight + 6
            Text {
                id: cardText
                anchors.centerIn: parent
                text: root.cardinalDirection(root.heading)
                color: Theme.white
                font.bold: true
                font.pixelSize: Math.max(10, root.size * 0.06)
            }
        }
        Rectangle {
            radius: 5
            color: Theme.withAlpha(Theme.black, 0.7)
            border.color: Theme.cyan
            border.width: 1.5
            width: hdgText.implicitWidth + 16
            height: hdgText.implicitHeight + 6
            Text {
                id: hdgText
                anchors.centerIn: parent
                text: Math.round(root.heading) + "°"
                color: Theme.white
                font.bold: true
                font.family: Theme.mono
                font.pixelSize: Math.max(10, root.size * 0.06)
            }
        }
    }
}
