// GPSInfoBar.qml - Fix / Satellites / HDOP
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

InfoBar {
    property string fixName: {
        var names = ["No GPS", "No Fix", "2D Fix", "3D Fix", "DGPS", "RTK Float", "RTK Fixed"]
        var t = mavlink.gpsFixType
        return t < names.length ? names[t] : "Unknown"
    }
    property color fixColor: mavlink.gpsFixType >= 3 ? Theme.green
                           : (mavlink.gpsSatellites > 0 ? Theme.yellow : Theme.red)
    property color hdopColor: mavlink.gpsHdop < 1.5 ? Theme.green
                            : (mavlink.gpsHdop < 3.0 ? Theme.yellow : Theme.red)

    InfoItem {
        icon: mavlink.gpsFixType >= 3 ? "●" : "○"
        label: "GPS Fix"
        value: fixName
        color: fixColor
        valueSize: 15
    }
    VDivider {}
    InfoItem {
        icon: "⩡"
        label: "Satellites"
        value: mavlink.gpsSatellites
        color: fixColor
    }
    VDivider {}
    InfoItem {
        icon: "⊕"
        label: "HDOP"
        value: mavlink.gpsHdop >= 99 ? "--" : mavlink.gpsHdop.toFixed(2)
        color: hdopColor
    }
}
