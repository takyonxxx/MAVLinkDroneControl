//
//  MessagesView.swift
//  DroneControl
//
//  Vehicle STATUSTEXT messages (PreArm errors, EKF, GPS...) + EKF health card.
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    enum Filter: String, CaseIterable {
        case all = "All"
        case warnings = "Warnings+"
        case errors = "Errors+"
    }
    @State private var filter: Filter = .all
    
    private var filtered: [VehicleMessage] {
        switch filter {
        case .all: return mavlinkManager.statusMessages
        case .warnings: return mavlinkManager.statusMessages.filter { $0.severity <= 4 }
        case .errors: return mavlinkManager.statusMessages.filter { $0.severity <= 3 }
        }
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()
            
            VStack(spacing: 10) {
                StatusBar()
                    .padding(.horizontal)
                
                EKFHealthCard()
                    .padding(.horizontal)
                
                filterBar
                    .padding(.horizontal)
                
                if filtered.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    messageList
                }
            }
        }
    }
    
    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button(action: { filter = f }) {
                    Text(f.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(filter == f ? Color.cyan : Color(red: 0.12, green: 0.12, blue: 0.18))
                        .foregroundColor(filter == f ? .black : .gray)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Text("\(filtered.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
            
            Button(action: { mavlinkManager.statusMessages.removeAll() }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text(mavlinkManager.isConnected
                 ? "No messages yet.\nPreArm and status messages will appear here."
                 : "Connect to the vehicle first.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .onChange(of: mavlinkManager.statusMessages.count) { _ in
                // Yeni mesaj gelince en alta kaydir
                if let last = filtered.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

// MARK: - Message Row
private struct MessageRow: View {
    let message: VehicleMessage
    
    private var color: Color {
        switch message.severity {
        case 0...2: return .red
        case 3: return .red
        case 4: return .orange
        case 5: return .yellow
        case 6: return .white
        default: return .gray
        }
    }
    
    private var icon: String {
        switch message.severity {
        case 0...3: return "xmark.octagon.fill"
        case 4: return "exclamationmark.triangle.fill"
        case 5: return "info.circle.fill"
        default: return "info.circle"
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: message.date))
                    Text(message.severityName)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(8)
    }
}

// MARK: - EKF Health Card
struct EKFHealthCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    private let bitPosHorizAbs: UInt16 = 1 << 4
    private let bitConstPos: UInt16 = 1 << 7
    
    private var stateText: String {
        if !mavlinkManager.ekfReportReceived { return "EKF: waiting for data" }
        if mavlinkManager.ekfFlags & bitPosHorizAbs != 0 { return "EKF: position OK — Loiter ready" }
        if mavlinkManager.ekfFlags & bitConstPos != 0 { return "EKF: no position source (waiting for GPS fix)" }
        return "EKF: degraded (flags: \(mavlinkManager.ekfFlags))"
    }
    
    private var stateColor: Color {
        if !mavlinkManager.ekfReportReceived { return .gray }
        if mavlinkManager.ekfFlags & bitPosHorizAbs != 0 { return .green }
        if mavlinkManager.ekfFlags & bitConstPos != 0 { return .yellow }
        return .red
    }
    
    private func varColor(_ v: Float) -> Color {
        if v < 0.5 { return .green }
        if v < 1.0 { return .yellow }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(stateText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            
            if mavlinkManager.ekfReportReceived {
                HStack(spacing: 14) {
                    varianceItem("Compass", mavlinkManager.ekfCompassVariance)
                    varianceItem("Position", mavlinkManager.ekfPosHorizVariance)
                    varianceItem("Velocity", mavlinkManager.ekfVelocityVariance)
                    Spacer()
                    Text("< 0.5 good")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.18),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(10)
    }
    
    private func varianceItem(_ label: String, _ value: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Text(String(format: "%.2f", value))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(varColor(value))
        }
    }
}

#Preview {
    MessagesView()
        .environmentObject(MAVLinkManager.shared)
}
