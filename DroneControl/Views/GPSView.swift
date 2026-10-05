//
//  GPSView.swift
//  DroneControl
//
//  GPS tanilama sekmesi: GPS fiziksel olarak takili mi (SYS_STATUS sensor bitleri),
//  GPS_RAW_INT geliyor mu (mesaj sayaci / frekans), fix durumu ve tum ham alanlar,
//  GPS ile ilgili STATUSTEXT mesajlari.
//

import SwiftUI

struct GPSView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    // "son alis" suresi icin saniyede bir yenile
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    private let gpsSensorBit: UInt32 = 32   // MAV_SYS_STATUS_SENSOR_GPS (0x20)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                verdictCard
                linkCard
                fixCard
                positionCard
                accuracyCard
                rawCard
                gpsMessagesCard
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.18),
                    Color(red: 0.09, green: 0.13, blue: 0.24)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onReceive(ticker) { now = $0 }
    }
    
    // MARK: - Derived state
    private var raw: GPSRawData { mavlinkManager.gpsRaw }
    
    private var sensorPresent: Bool { mavlinkManager.sensorsPresent & gpsSensorBit != 0 }
    private var sensorEnabled: Bool { mavlinkManager.sensorsEnabled & gpsSensorBit != 0 }
    private var sensorHealthy: Bool { mavlinkManager.sensorsHealth & gpsSensorBit != 0 }
    
    /// GPS_RAW_INT son 3 s icinde geldi mi
    private var dataFlowing: Bool {
        guard let last = raw.lastReceived else { return false }
        return now.timeIntervalSince(last) < 3.0
    }
    
    private var heartbeatAlive: Bool {
        guard let hb = mavlinkManager.lastHeartbeatDate else { return false }
        return now.timeIntervalSince(hb) < 3.0
    }
    
    private var heartbeatAgeText: String {
        guard let hb = mavlinkManager.lastHeartbeatDate else { return "--" }
        let dt = now.timeIntervalSince(hb)
        return dt < 1 ? "<1 s" : String(format: "%.0f s", dt)
    }
    
    private var gpsRerequests: Int { mavlinkManager.streamRerequestCount[24] ?? 0 }
    
    private var secondsSinceLast: String {
        guard let last = raw.lastReceived else { return "never" }
        let dt = now.timeIntervalSince(last)
        return dt < 1 ? "<1 s ago" : String(format: "%.0f s ago", dt)
    }
    
    /// Genel yorum
    private var verdict: (text: String, detail: String, color: Color) {
        if !mavlinkManager.isConnected {
            return ("NOT CONNECTED", "No MAVLink link to the flight controller.", .red)
        }
        if mavlinkManager.sysStatusReceived && !sensorPresent {
            return ("GPS NOT DETECTED",
                    "SYS_STATUS reports no GPS sensor. Check wiring/port (SERIALx_PROTOCOL=5, GPS_TYPE) and power.",
                    .red)
        }
        if !heartbeatAlive {
            return ("NO LINK TO FC",
                    (mavlinkManager.lastHeartbeatDate == nil
                        ? "No HEARTBEAT received from the flight controller yet."
                        : "No HEARTBEAT from the flight controller for \(heartbeatAgeText).")
                    + " The telemetry link is down (FC power, ESP bridge, Wi-Fi) - not a GPS problem.",
                    .red)
        }
        if raw.received && !dataFlowing {
            return ("GPS STREAM STOPPED",
                    "FC is alive but GPS_RAW_INT stopped (FC reboot or lost request). The app re-requests it automatically - re-requested \(gpsRerequests) times so far.",
                    .orange)
        }
        if !raw.received || !dataFlowing {
            return ("NO GPS DATA",
                    "GPS_RAW_INT is not arriving. Either the FC has no GPS driver active or the stream is not enabled.",
                    .red)
        }
        if raw.fixType == 0 {
            return ("GPS DRIVER: NO GPS",
                    "FC is streaming GPS_RAW_INT but reports fix type 0 (no module talking on the port). Check TX/RX crossover and baud.",
                    .orange)
        }
        if raw.fixType == 1 {
            return ("GPS DETECTED - NO FIX",
                    "Module is communicating (\(raw.satellitesVisible == 255 ? "?" : "\(raw.satellitesVisible)") sats). Waiting for a fix - needs open sky.",
                    .orange)
        }
        if raw.fixType == 2 {
            return ("2D FIX", "Horizontal position only, altitude not valid yet.", .yellow)
        }
        if !sensorHealthy && mavlinkManager.sysStatusReceived {
            return ("\(raw.fixName) - UNHEALTHY",
                    "Fix present but FC flags GPS as unhealthy (HDOP/accuracy or lag). Check antenna placement/interference.",
                    .orange)
        }
        return (raw.fixName, "GPS healthy. \(raw.satellitesVisible) satellites, HDOP \(hdopText).", .green)
    }
    
    private var hdopText: String { raw.eph == UInt16.max ? "--" : String(format: "%.2f", Float(raw.eph) / 100) }
    private var vdopText: String { raw.epv == UInt16.max ? "--" : String(format: "%.2f", Float(raw.epv) / 100) }
    
    // MARK: - Cards
    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(verdict.color)
                    .frame(width: 14, height: 14)
                Text(verdict.text)
                    .font(.title3).bold()
                    .foregroundColor(.white)
                Spacer()
            }
            Text(verdict.detail)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(verdict.color.opacity(0.6), lineWidth: 1))
        .cornerRadius(12)
    }
    
    private var linkCard: some View {
        card("Hardware / Link") {
            statusRow("FC heartbeat", ok: heartbeatAlive,
                      text: heartbeatAlive ? "ALIVE" : (mavlinkManager.lastHeartbeatDate == nil ? "NONE" : "LOST \(heartbeatAgeText) ago"))
            statusRow("SYS_STATUS received", ok: mavlinkManager.sysStatusReceived,
                      text: mavlinkManager.sysStatusReceived ? "yes" : "waiting")
            statusRow("GPS sensor present", ok: sensorPresent,
                      text: mavlinkManager.sysStatusReceived ? (sensorPresent ? "PRESENT" : "ABSENT") : "--")
            statusRow("GPS sensor enabled", ok: sensorEnabled,
                      text: mavlinkManager.sysStatusReceived ? (sensorEnabled ? "ENABLED" : "DISABLED") : "--")
            statusRow("GPS sensor healthy", ok: sensorHealthy,
                      text: mavlinkManager.sysStatusReceived ? (sensorHealthy ? "HEALTHY" : "UNHEALTHY") : "--")
            Divider().background(Color.gray.opacity(0.4))
            statusRow("GPS_RAW_INT stream", ok: dataFlowing, text: dataFlowing ? "FLOWING" : "STALLED")
            row("Message count", "\(raw.messageCount)")
            row("Rate", raw.received ? String(format: "%.1f Hz (requested 5 Hz)", raw.rateHz) : "--")
            row("Last message", secondsSinceLast)
            row("Re-requested", "\(gpsRerequests)x")
        }
    }
    
    private var fixCard: some View {
        card("Fix") {
            HStack {
                Text(raw.fixName)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(fixColor)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(raw.satellitesVisible == 255 ? "--" : "\(raw.satellitesVisible)")")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("satellites")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            row("fix_type (raw)", "\(raw.fixType)")
            row("HDOP", hdopText)
            row("VDOP", vdopText)
            row("GPS time", gpsTimeText)
        }
    }
    
    private var positionCard: some View {
        card("Position (GPS_RAW_INT)") {
            let valid = raw.fixType >= 2
            row("Latitude", valid ? String(format: "%.7f", Double(raw.lat) / 1e7) : "--")
            row("Longitude", valid ? String(format: "%.7f", Double(raw.lon) / 1e7) : "--")
            row("Alt MSL", raw.fixType >= 3 ? String(format: "%.2f m", Double(raw.alt) / 1000) : "--")
            row("Alt ellipsoid", raw.fixType >= 3 && raw.altEllipsoid != 0
                ? String(format: "%.2f m", Double(raw.altEllipsoid) / 1000) : "--")
            row("Ground speed", raw.vel == UInt16.max ? "--" : String(format: "%.2f m/s", Float(raw.vel) / 100))
            row("Course over ground", raw.cog == UInt16.max ? "--" : String(format: "%.2f deg", Float(raw.cog) / 100))
            row("GPS yaw", raw.yaw == 0 ? "n/a" : String(format: "%.2f deg", Float(raw.yaw) / 100))
        }
    }
    
    private var accuracyCard: some View {
        card("Accuracy estimates") {
            row("Horizontal (h_acc)", raw.hAcc == 0 ? "--" : String(format: "%.2f m", Double(raw.hAcc) / 1000))
            row("Vertical (v_acc)", raw.vAcc == 0 ? "--" : String(format: "%.2f m", Double(raw.vAcc) / 1000))
            row("Speed (vel_acc)", raw.velAcc == 0 ? "--" : String(format: "%.2f m/s", Double(raw.velAcc) / 1000))
            row("Heading (hdg_acc)", raw.hdgAcc == 0 ? "--" : String(format: "%.2f deg", Double(raw.hdgAcc) / 1e5))
        }
    }
    
    private var rawCard: some View {
        card("Raw fields") {
            rawRow("time_usec", "\(raw.timeUsec)")
            rawRow("fix_type", "\(raw.fixType)")
            rawRow("lat", "\(raw.lat)")
            rawRow("lon", "\(raw.lon)")
            rawRow("alt", "\(raw.alt)")
            rawRow("eph", "\(raw.eph)")
            rawRow("epv", "\(raw.epv)")
            rawRow("vel", "\(raw.vel)")
            rawRow("cog", "\(raw.cog)")
            rawRow("satellites_visible", "\(raw.satellitesVisible)")
            rawRow("alt_ellipsoid", "\(raw.altEllipsoid)")
            rawRow("h_acc", "\(raw.hAcc)")
            rawRow("v_acc", "\(raw.vAcc)")
            rawRow("vel_acc", "\(raw.velAcc)")
            rawRow("hdg_acc", "\(raw.hdgAcc)")
            rawRow("yaw", "\(raw.yaw)")
            rawRow("sensors_present", String(format: "0x%08X", mavlinkManager.sensorsPresent))
            rawRow("sensors_enabled", String(format: "0x%08X", mavlinkManager.sensorsEnabled))
            rawRow("sensors_health", String(format: "0x%08X", mavlinkManager.sensorsHealth))
        }
    }
    
    private var gpsMessages: [VehicleMessage] {
        mavlinkManager.statusMessages
            .filter { $0.text.uppercased().contains("GPS") || $0.text.uppercased().contains("GNSS") }
            .suffix(15)
            .reversed()
    }
    
    private var gpsMessagesCard: some View {
        card("GPS status messages (STATUSTEXT)") {
            if gpsMessages.isEmpty {
                Text("No GPS-related messages yet. ArduPilot prints e.g. \"GPS 1: detected as u-blox\" at boot.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(gpsMessages) { m in
                    HStack(alignment: .top, spacing: 8) {
                        Text(timeString(m.date))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(m.severityName)
                            .font(.caption2).bold()
                            .foregroundColor(m.severity <= 3 ? .red : (m.severity == 4 ? .orange : .cyan))
                        Text(m.text)
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private var fixColor: Color {
        switch raw.fixType {
        case 0, 1: return .red
        case 2: return .yellow
        default: return .green
        }
    }
    
    private var gpsTimeText: String {
        guard raw.timeUsec > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(raw.timeUsec) / 1_000_000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date) + " UTC"
    }
    
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
    
    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
        }
    }
    
    private func rawRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.cyan)
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white)
        }
    }
    
    private func statusRow(_ label: String, ok: Bool, text: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(ok ? .green : .red)
        }
    }
}

#Preview {
    GPSView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
