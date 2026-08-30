//
//  ParametersView.swift
//  DroneControl
//
//  Tum parametreleri cihazdan okur, kategorilere gruplar, duzenleyip geri yazar.
//

import SwiftUI

// MARK: - Kategori tanimlari
private struct ParamCategory {
    let name: String
    let icon: String
    let prefixes: [String]
}

// Sira onemli: bir parametre ilk eslesen kategoriye girer
private let categories: [ParamCategory] = [
    ParamCategory(name: "Servos", icon: "slider.horizontal.3",
                  prefixes: ["SERVO"]),
    ParamCategory(name: "Radio (RC)", icon: "gamecontroller",
                  prefixes: ["RC1", "RC2", "RC3", "RC4", "RC5", "RC6", "RC7",
                             "RC8", "RC9", "RC1_", "RC_", "RCMAP", "FLTMODE",
                             "THR_", "PILOT"]),
    ParamCategory(name: "AutoTune", icon: "wand.and.stars",
                  prefixes: ["AUTOTUNE"]),
    ParamCategory(name: "Attitude Control (ATC)", icon: "gyroscope",
                  prefixes: ["ATC_"]),
    ParamCategory(name: "Motors", icon: "fan",
                  prefixes: ["MOT_"]),
    ParamCategory(name: "GPS", icon: "location",
                  prefixes: ["GPS"]),
    ParamCategory(name: "Compass", icon: "safari",
                  prefixes: ["COMPASS"]),
    ParamCategory(name: "EKF / AHRS", icon: "cube.transparent",
                  prefixes: ["EK2_", "EK3_", "AHRS", "VISO"]),
    ParamCategory(name: "IMU / Vibration", icon: "waveform.path.ecg",
                  prefixes: ["INS_"]),
    ParamCategory(name: "Battery / Power", icon: "battery.75",
                  prefixes: ["BATT", "BRD_VBUS", "MOT_BAT"]),
    ParamCategory(name: "Navigation (Loiter/WP)", icon: "point.topleft.down.curvedto.point.bottomright.up",
                  prefixes: ["LOIT", "PSC", "WPNAV", "RTL_", "LAND_", "PHLD",
                             "CIRCLE", "SURFTRAK"]),
    ParamCategory(name: "Failsafe", icon: "exclamationmark.shield",
                  prefixes: ["FS_", "BATT_FS", "FENCE"]),
    ParamCategory(name: "Arming", icon: "lock.shield",
                  prefixes: ["ARMING", "DISARM"]),
    ParamCategory(name: "Telemetry / Serial Ports", icon: "antenna.radiowaves.left.and.right",
                  prefixes: ["SR0", "SR1", "SR2", "SR3", "SERIAL", "TELEM"]),
    ParamCategory(name: "Rangefinder / Optical Flow", icon: "arrow.down.to.line",
                  prefixes: ["RNGFND", "FLOW"]),
    ParamCategory(name: "Board / System", icon: "cpu",
                  prefixes: ["BRD_", "SCHED", "LOG_", "STAT_", "SYSID",
                             "FRAME", "NTF_"]),
]

private func categoryFor(_ paramName: String) -> String {
    for cat in categories {
        for p in cat.prefixes where paramName.hasPrefix(p) {
            return cat.name
        }
    }
    return "Other"
}

private func iconFor(_ categoryName: String) -> String {
    categories.first(where: { $0.name == categoryName })?.icon ?? "doc.text"
}

// MARK: - Ana gorunum
struct ParametersView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = []
    @State private var editingParam: String? = nil
    @State private var editValue: String = ""
    @State private var recentlyWritten: Set<String> = []
    @State private var showRestoreConfirm = false
    
    // Kategori adi -> [(isim, deger)] sirali
    private var grouped: [(category: String, params: [(String, Float)])] {
        let filter = searchText.uppercased()
        var buckets: [String: [(String, Float)]] = [:]
        for (name, value) in mavlinkManager.parameters {
            if !filter.isEmpty && !name.uppercased().contains(filter) { continue }
            buckets[categoryFor(name), default: []].append((name, value))
        }
        let order = categories.map { $0.name } + ["Other"]
        return order.compactMap { cat in
            guard var list = buckets[cat], !list.isEmpty else { return nil }
            list.sort { $0.0 < $1.0 }
            return (cat, list)
        }
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()
            
            VStack(spacing: 10) {
                StatusBar()
                    .padding(.horizontal)
                
                headerBar
                    .padding(.horizontal)
                
                searchBar
                    .padding(.horizontal)
                
                if mavlinkManager.parameters.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    paramList
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingParam != nil },
            set: { if !$0 { editingParam = nil } }
        )) {
            if let name = editingParam {
                ParamEditSheet(
                    paramName: name,
                    currentValue: mavlinkManager.parameters[name] ?? 0,
                    editValue: $editValue,
                    onSend: { newValue in
                        mavlinkManager.setParameter(name: name, value: newValue)
                        recentlyWritten.insert(name)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            recentlyWritten.remove(name)
                        }
                        editingParam = nil
                    },
                    onCancel: { editingParam = nil }
                )
            }
        }
    }
    
    // MARK: Ust bar: oku butonu + ilerleme
    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: { mavlinkManager.requestAllParameters() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13))
                        Text("Read from Vehicle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(mavlinkManager.isConnected ? Color.cyan : Color.gray)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!mavlinkManager.isConnected || mavlinkManager.restoreInProgress)
                .buttonStyle(.plain)
                
                Button(action: { showRestoreConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 13))
                        Text("Restore Defaults")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(mavlinkManager.isConnected ? Color.orange : Color.gray)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!mavlinkManager.isConnected || mavlinkManager.restoreInProgress)
                .buttonStyle(.plain)
                
                if mavlinkManager.paramDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Spacer()
                
                Text(progressText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            if mavlinkManager.restoreInProgress {
                HStack(spacing: 10) {
                    ProgressView(value: Double(mavlinkManager.restoreProgress),
                                 total: Double(max(mavlinkManager.restoreTotal, 1)))
                        .tint(.orange)
                    Text("\(mavlinkManager.restoreProgress)/\(mavlinkManager.restoreTotal)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                    Button(action: { mavlinkManager.cancelRestore() }) {
                        Text("Cancel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog(
            "Restore default parameters?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Write \(DefaultParameters.values.count) parameters", role: .destructive) {
                mavlinkManager.restoreDefaultParameters()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Writes the known-good snapshot to the vehicle, overwriting current values. Takes about \(DefaultParameters.values.count / 40 + 5) seconds. Reboot the vehicle afterwards.")
        }
    }
    
    private var progressText: String {
        let got = mavlinkManager.parameters.count
        let total = mavlinkManager.paramTotalCount
        if total > 0 { return "\(got) / \(total)" }
        return got > 0 ? "\(got)" : ""
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search parameters (e.g. LOIT, MOT_PWM)", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(red: 0.12, green: 0.12, blue: 0.18))
        .cornerRadius(8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text(mavlinkManager.isConnected
                 ? "No parameters loaded yet.\nTap \"Read from Vehicle\" to start."
                 : "Connect to the vehicle first.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: Liste
    private var paramList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(grouped, id: \.category) { group in
                    categorySection(group.category, group.params)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
    
    private func categorySection(_ name: String,
                                 _ params: [(String, Float)]) -> some View {
        let isExpanded = expandedCategories.contains(name) || !searchText.isEmpty
        return VStack(spacing: 0) {
            Button(action: {
                if expandedCategories.contains(name) {
                    expandedCategories.remove(name)
                } else {
                    expandedCategories.insert(name)
                }
            }) {
                HStack {
                    Image(systemName: iconFor(name))
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                        .frame(width: 22)
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(params.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider().background(Color.gray.opacity(0.2))
                ForEach(params, id: \.0) { (pname, pvalue) in
                    paramRow(pname, pvalue)
                    if pname != params.last?.0 {
                        Divider().background(Color.gray.opacity(0.1))
                    }
                }
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(10)
    }
    
    private func paramRow(_ name: String, _ value: Float) -> some View {
        Button(action: {
            editValue = formatValue(value)
            editingParam = name
        }) {
            HStack {
                Text(name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                if recentlyWritten.contains(name) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                Text(formatValue(value))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func formatValue(_ v: Float) -> String {
    if v == v.rounded() && abs(v) < 1e7 {
        return String(format: "%.0f", v)
    }
    return String(format: "%g", v)
}

// MARK: - Duzenleme sayfasi
struct ParamEditSheet: View {
    let paramName: String
    let currentValue: Float
    @Binding var editValue: String
    let onSend: (Float) -> Void
    let onCancel: () -> Void
    
    private var parsedValue: Float? {
        Float(editValue.replacingOccurrences(of: ",", with: "."))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(paramName)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            HStack(spacing: 6) {
                Text("Current value:")
                    .foregroundColor(.gray)
                Text(formatValue(currentValue))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .font(.system(size: 14))
            
            TextField("New value", text: $editValue)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color(red: 0.12, green: 0.12, blue: 0.18))
                .cornerRadius(10)
                .foregroundColor(.white)
#if os(iOS)
                .keyboardType(.numbersAndPunctuation)
#endif
            
            if parsedValue == nil {
                Text("Invalid number")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            
            Text("The value is written to the vehicle immediately.\nSome parameters take effect after reboot.")
                .font(.system(size: 11))
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let v = parsedValue { onSend(v) }
                }) {
                    Text("Write to Vehicle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(parsedValue != nil ? Color.cyan : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(parsedValue == nil)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .presentationDetents([.height(360)])
        .background(Color(red: 0.07, green: 0.07, blue: 0.12))
    }
}

#Preview {
    ParametersView()
        .environmentObject(MAVLinkManager.shared)
}
