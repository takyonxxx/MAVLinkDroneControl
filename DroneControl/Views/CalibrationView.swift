//
//  CalibrationView.swift
//  DroneControl
//
//  Sensor kalibrasyon sekmesi:
//   - Pusula: MAV_CMD_DO_START_MAG_CAL -> MAG_CAL_PROGRESS (yuzde + geodesic bolum maskesi)
//             -> MAG_CAL_REPORT (fitness puani) -> MAV_CMD_DO_ACCEPT_MAG_CAL (parametrelere yaz)
//   - Gyro:   MAV_CMD_PREFLIGHT_CALIBRATION param1=1 (arac sabit durmali, ~2 s)
//   - Baro:   MAV_CMD_PREFLIGHT_CALIBRATION param3=1 (yer basinci)
//

import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    private var canCalibrate: Bool {
        mavlinkManager.isConnected && !mavlinkManager.isArmedByPilot
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !mavlinkManager.isConnected {
                    banner("Not connected", .red)
                } else if mavlinkManager.isArmedByPilot {
                    banner("Vehicle is ARMED - disarm before calibrating", .red)
                }
                
                compassCard
                gyroCard
                baroCard
                messagesCard
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
    
    // MARK: - Compass
    private var compassIds: [UInt8] {
        Array(Set(mavlinkManager.magCalProgress.keys).union(mavlinkManager.magCalReports.keys)).sorted()
    }
    
    /// Tum pusulalarin ortalama ilerlemesi
    private var overallPct: Int {
        let p = mavlinkManager.magCalProgress.values
        guard !p.isEmpty else { return 0 }
        if !mavlinkManager.magCalReports.isEmpty && !mavlinkManager.magCalRunning { return 100 }
        return Int(p.map { Int($0.completionPct) }.reduce(0, +) / p.count)
    }
    
    private var compassCard: some View {
        card("Compass", icon: "safari") {
            Text("Rotate the vehicle slowly around all axes until every section fills. Keep away from metal, magnets and motors running.")
                .font(.caption)
                .foregroundColor(.gray)
            
            // Genel ilerleme
            HStack {
                Text(mavlinkManager.magCalRunning ? "CALIBRATING" :
                     (mavlinkManager.magCalReports.isEmpty ? "IDLE" : "COMPLETE"))
                    .font(.caption).bold()
                    .foregroundColor(mavlinkManager.magCalRunning ? .orange : .white)
                Spacer()
                Text("\(overallPct)%")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(overallPct >= 100 ? .green : .cyan)
            }
            ProgressView(value: Double(overallPct), total: 100)
                .tint(overallPct >= 100 ? .green : .cyan)
            
            if let ack = mavlinkManager.magCalStartAck {
                row("Start ACK", ack, color: ack == "ACCEPTED" ? .green : .red)
            }
            
            // Pusula bazinda detay
            ForEach(compassIds, id: \.self) { id in
                compassDetail(id)
            }
            
            // Kayit durumu
            if !mavlinkManager.magCalReports.isEmpty && !mavlinkManager.magCalRunning {
                Divider().background(Color.gray.opacity(0.4))
                if mavlinkManager.magCalSaved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Offsets written to parameters (COMPASS_OFS_*). Reboot the FC to apply.")
                            .font(.caption).foregroundColor(.green)
                    }
                    Button(action: { mavlinkManager.rebootFlightController() }) {
                        Label("Reboot flight controller", systemImage: "arrow.clockwise")
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                } else if let ack = mavlinkManager.magCalAcceptAck {
                    row("Accept ACK", ack, color: .red)
                } else if mavlinkManager.magCalReports.values.allSatisfy({ $0.success }) {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Writing offsets to device...")
                            .font(.caption).foregroundColor(.orange)
                    }
                    Button(action: { mavlinkManager.acceptCompassCalibration() }) {
                        Text("Accept & save manually")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                } else {
                    Text("Calibration did not succeed - fix the issue above and start again.")
                        .font(.caption).foregroundColor(.red)
                }
            }
            
            HStack(spacing: 10) {
                Button(action: { mavlinkManager.startCompassCalibration() }) {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canCalibrate && !mavlinkManager.magCalRunning ? Color.cyan : Color.gray)
                        .cornerRadius(8)
                }
                .disabled(!canCalibrate || mavlinkManager.magCalRunning)
                
                Button(action: { mavlinkManager.cancelCompassCalibration() }) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mavlinkManager.magCalRunning ? Color.red : Color.gray)
                        .cornerRadius(8)
                }
                .disabled(!mavlinkManager.magCalRunning)
            }
        }
    }
    
    private func compassDetail(_ id: UInt8) -> some View {
        let prog = mavlinkManager.magCalProgress[id]
        let rep = mavlinkManager.magCalReports[id]
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Compass \(id + 1)")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Spacer()
                if let p = prog {
                    Text(rep?.statusName ?? p.statusName)
                        .font(.caption2).bold()
                        .foregroundColor(statusColor(rep?.status ?? p.status))
                }
            }
            
            if let p = prog {
                HStack {
                    Text("\(p.completionPct)%")
                        .font(.system(.title3, design: .monospaced)).bold()
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("attempt \(p.attempt)  sections \(p.sectionsDone)/80")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                sectionGrid(p.completionMask)
                if mavlinkManager.magCalRunning {
                    Text(directionHint(p))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            if let r = rep {
                Divider().background(Color.gray.opacity(0.3))
                HStack(alignment: .firstTextBaseline) {
                    Text("Fitness")
                        .font(.caption).foregroundColor(.gray)
                    Text(String(format: "%.2f", r.fitness))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(fitnessColor(r.fitness))
                    Text("mGauss RMS")
                        .font(.caption2).foregroundColor(.gray)
                    Spacer()
                    Text(r.qualityText)
                        .font(.caption).bold()
                        .foregroundColor(fitnessColor(r.fitness))
                }
                row("Offsets", String(format: "%.1f  %.1f  %.1f", r.ofsX, r.ofsY, r.ofsZ))
                row("Diag", String(format: "%.3f  %.3f  %.3f", r.diagX, r.diagY, r.diagZ))
                row("Off-diag", String(format: "%.3f  %.3f  %.3f", r.offdiagX, r.offdiagY, r.offdiagZ))
                row("Scale factor", String(format: "%.3f", r.scaleFactor))
                row("Orientation", "\(r.oldOrientation) -> \(r.newOrientation)  (conf \(String(format: "%.1f", r.orientationConfidence)))")
                row("Autosaved", r.autosaved ? "yes" : "no (ACCEPT sent)")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    /// 80 geodesic bolum: 8 satir x 10 sutun, dolu = veri toplandi
    private func sectionGrid(_ mask: [UInt8]) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { rowIdx in
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { colIdx in
                        let bit = rowIdx * 10 + colIdx
                        let set = bit < 80 && (mask[bit / 8] >> (bit % 8)) & 1 == 1
                        RoundedRectangle(cornerRadius: 2)
                            .fill(set ? Color.green : Color.white.opacity(0.12))
                            .frame(height: 10)
                    }
                }
            }
        }
    }
    
    private func directionHint(_ p: MagCalProgressData) -> String {
        // direction vektoru govde cercevesinde; en buyuk bilesene gore ipucu
        let x = p.directionX, y = p.directionY, z = p.directionZ
        if abs(x) < 0.01 && abs(y) < 0.01 && abs(z) < 0.01 { return "Keep rotating..." }
        let ax = abs(x), ay = abs(y), az = abs(z)
        if ax >= ay && ax >= az { return x > 0 ? "Point nose UP more" : "Point nose DOWN more" }
        if ay >= ax && ay >= az { return y > 0 ? "Roll RIGHT side down" : "Roll LEFT side down" }
        return z > 0 ? "Turn vehicle UPSIDE DOWN" : "Hold vehicle LEVEL / upright"
    }
    
    private func statusColor(_ s: UInt8) -> Color {
        switch s {
        case 4: return .green
        case 5, 6, 7: return .red
        case 2, 3: return .orange
        default: return .gray
        }
    }
    
    private func fitnessColor(_ f: Float) -> Color {
        switch f {
        case ..<10: return .green
        case ..<20: return .yellow
        case ..<40: return .orange
        default: return .red
        }
    }
    
    // MARK: - Gyro
    private var gyroCard: some View {
        card("Gyroscope", icon: "gyroscope") {
            Text("Place the vehicle on a stable surface and do not touch it. Takes a few seconds; the FC replies when finished.")
                .font(.caption)
                .foregroundColor(.gray)
            simpleCalStatus(mavlinkManager.gyroCalState)
            Button(action: { mavlinkManager.calibrateGyro() }) {
                Label("Calibrate gyro", systemImage: "play.fill")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canCalibrate && !isInProgress(mavlinkManager.gyroCalState) ? Color.cyan : Color.gray)
                    .cornerRadius(8)
            }
            .disabled(!canCalibrate || isInProgress(mavlinkManager.gyroCalState))
        }
    }
    
    // MARK: - Baro
    private var baroCard: some View {
        card("Barometer", icon: "barometer") {
            Text("Sets current pressure as ground reference (altitude = 0). Vehicle must be stationary, out of wind.")
                .font(.caption)
                .foregroundColor(.gray)
            simpleCalStatus(mavlinkManager.baroCalState)
            Button(action: { mavlinkManager.calibrateBarometer() }) {
                Label("Calibrate barometer", systemImage: "play.fill")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canCalibrate && !isInProgress(mavlinkManager.baroCalState) ? Color.cyan : Color.gray)
                    .cornerRadius(8)
            }
            .disabled(!canCalibrate || isInProgress(mavlinkManager.baroCalState))
        }
    }
    
    private func isInProgress(_ s: SimpleCalState) -> Bool {
        if case .inProgress = s { return true }
        return false
    }
    
    private func simpleCalStatus(_ s: SimpleCalState) -> some View {
        HStack {
            switch s {
            case .idle:
                Circle().fill(Color.gray).frame(width: 8, height: 8)
                Text("Idle").font(.caption).foregroundColor(.gray)
            case .inProgress(let start):
                ProgressView().scaleEffect(0.7)
                Text(String(format: "In progress... %.0f s", now.timeIntervalSince(start)))
                    .font(.caption).foregroundColor(.orange)
            case .success(let t):
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Done - \(t)").font(.caption).foregroundColor(.green)
            case .failed(let t):
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                Text("Failed - \(t)").font(.caption).foregroundColor(.red)
            }
            Spacer()
        }
    }
    
    // MARK: - STATUSTEXT
    private var calMessages: [VehicleMessage] {
        let keys = ["CALIB", "COMPASS", "MAG", "GYRO", "BARO", "PRESSURE", "INS"]
        return mavlinkManager.statusMessages
            .filter { m in keys.contains { m.text.uppercased().contains($0) } }
            .suffix(12)
            .reversed()
    }
    
    private var messagesCard: some View {
        card("Calibration messages", icon: "text.bubble") {
            if calMessages.isEmpty {
                Text("No calibration messages yet.")
                    .font(.caption).foregroundColor(.gray)
            } else {
                ForEach(calMessages) { m in
                    HStack(alignment: .top, spacing: 8) {
                        Text(timeString(m.date))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(m.text)
                            .font(.caption)
                            .foregroundColor(m.severity <= 3 ? .red : (m.severity == 4 ? .orange : .white))
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
    
    private func banner(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.subheadline).bold()
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(color.opacity(0.6))
            .cornerRadius(8)
    }
    
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundColor(.cyan)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    private func row(_ label: String, _ value: String, color: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

#Preview {
    CalibrationView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
