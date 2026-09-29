// Theme.qml - DroneControlQt
// Colors and fonts mirroring the SwiftUI app (iOS system colors, dark palette).
pragma Singleton
import QtQuick

QtObject {
    // Backgrounds
    readonly property color bg: "#0D0D1A"          // (0.05, 0.05, 0.10)
    readonly property color bgHeader: "#14141F"    // (0.08, 0.08, 0.12)
    readonly property color card: "#1A1A26"        // (0.10, 0.10, 0.15)
    readonly property color card2: "#1F1F2E"       // (0.12, 0.12, 0.18)
    readonly property color card3: "#262633"       // (0.15, 0.15, 0.20)
    readonly property color barBg: "#333340"       // (0.20, 0.20, 0.25)
    readonly property color gradTop: "#1A1A2E"     // (0.10, 0.10, 0.18)
    readonly property color gradBottom: "#17213D"  // (0.09, 0.13, 0.24)
    readonly property color sheetBg: "#12121F"     // (0.07, 0.07, 0.12)
    readonly property color overlay: "#4D000000"   // black 30 %

    // iOS system colors
    readonly property color cyan: "#32ADE6"
    readonly property color green: "#34C759"
    readonly property color orange: "#FF9500"
    readonly property color red: "#FF3B30"
    readonly property color blue: "#007AFF"
    readonly property color yellow: "#FFCC00"
    readonly property color purple: "#AF52DE"
    readonly property color indigo: "#5856D6"
    readonly property color teal: "#5AC8FA"
    readonly property color mint: "#00C7BE"
    readonly property color pink: "#FF2D55"
    readonly property color brown: "#A2845E"
    readonly property color gray: "#8E8E93"
    readonly property color white: "#FFFFFF"
    readonly property color black: "#000000"

    readonly property color buttonBlue1: "#3366CC"   // (0.2, 0.4, 0.8)
    readonly property color buttonBlue2: "#4D80E6"   // (0.3, 0.5, 0.9)
    readonly property color armGreen1: "#33B34D"     // (0.2, 0.7, 0.3)
    readonly property color armGreen2: "#4DCC66"     // (0.3, 0.8, 0.4)
    readonly property color armRed1: "#CC3333"       // (0.8, 0.2, 0.2)
    readonly property color armRed2: "#E64D4D"       // (0.9, 0.3, 0.3)

    readonly property string mono: fixedFontFamily

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function batteryColor(percent) {
        if (percent > 50) return green
        if (percent > 20) return orange
        return red
    }

    function voltageColor(v) {
        if (v > 11.5) return green
        if (v > 10.5) return orange
        return red
    }

    function gpsColor(fixType) {
        if (fixType >= 3 && fixType <= 7) return green
        if (fixType === 2) return orange
        return red
    }

    function gpsFixName(fixType) {
        var names = ["No GPS", "No Fix", "2D", "3D", "DGPS", "RTK Float", "RTK Fixed"]
        return fixType < names.length ? names[fixType] : "Unknown"
    }

    function servoProportion(pwm) {
        var c = Math.max(1000, Math.min(2000, pwm))
        return (c - 1000) / 1000.0
    }

    function servoColor(pwm, mid) {
        if (pwm < 1100) return blue
        if (pwm > 1900) return red
        if (Math.abs(pwm - 1500) < 50) return green
        return mid === undefined ? cyan : mid
    }
}
