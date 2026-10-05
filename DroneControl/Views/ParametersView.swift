//
//  ParametersView.swift
//  DroneControl
//
//  Tum parametreleri cihazdan okur, kategorilere gruplar, duzenleyip geri yazar.
//  Lokal .param dosyasindan (Mission Planner / QGC formati) yukleme de yapar.
//

import SwiftUI
import UniformTypeIdentifiers

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
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
#else
    private let compact = false
#endif
    
    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = []
    @State private var editingParam: String? = nil
    @State private var editValue: String = ""
    @State private var recentlyWritten: Set<String> = []
    @State private var showRestoreConfirm = false
    @State private var showFileImporter = false
    @State private var loadedFile: LoadedParamFile? = nil
    @State private var showWriteResult = false
    
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
                
                if let result = mavlinkManager.paramWriteResult, !mavlinkManager.paramWriteInProgress {
                    writeResultBanner(result)
                        .padding(.horizontal)
                }
                
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
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { loadParamFile(url) }
                case .failure(let error):
                    presentLoadedFile(LoadedParamFile(fileName: "", parse: .init(),
                                                      error: "Cannot open file: \(error.localizedDescription)"))
                }
            }
            .sheet(item: $loadedFile) { file in
                ParamFileSheet(file: file,
                               onWrite: { items in
                                   mavlinkManager.writeParameters(items, source: "file")
                                   loadedFile = nil
                               },
                               onCancel: { loadedFile = nil })
                    .environmentObject(mavlinkManager)
            }
            .sheet(isPresented: $showWriteResult) {
                if let result = mavlinkManager.paramWriteResult {
                    ParamWriteResultSheet(result: result,
                                          onReboot: {
                                              mavlinkManager.rebootFlightController()
                                              showWriteResult = false
                                          },
                                          onClose: { showWriteResult = false })
                        .environmentObject(mavlinkManager)
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
                        Text(compact ? "Read" : "Read from Vehicle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(mavlinkManager.isConnected ? Color.cyan : Color.gray)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!mavlinkManager.isConnected || mavlinkManager.paramWriteInProgress)
                .buttonStyle(.plain)
                
                Button(action: { showFileImporter = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.arrow.up.fill")
                            .font(.system(size: 13))
                        Text(compact ? "File" : "Load from File")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(mavlinkManager.paramWriteInProgress)
                .buttonStyle(.plain)
                
                Button(action: { showRestoreConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 13))
                        Text(compact ? "Defaults" : "Restore Defaults")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(mavlinkManager.isConnected ? Color.orange : Color.gray)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!mavlinkManager.isConnected || mavlinkManager.paramWriteInProgress)
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
            
            // Toplu yazma ilerlemesi: 1. turda gonderilen, tekrar turlarinda dogrulanan adet
            if mavlinkManager.paramWriteInProgress {
                HStack(spacing: 10) {
                    ProgressView(value: Double(mavlinkManager.paramWritePass == 1
                                               ? mavlinkManager.paramWriteSent
                                               : mavlinkManager.paramWriteConfirmed),
                                 total: Double(max(mavlinkManager.paramWriteTotal, 1)))
                        .tint(.orange)
                    Text((mavlinkManager.paramWritePass > 1 ? "retry \(mavlinkManager.paramWritePass)  " : "")
                         + "\u{2713}\(mavlinkManager.paramWriteConfirmed)/\(mavlinkManager.paramWriteTotal)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                    Button(action: { mavlinkManager.cancelParamWrite() }) {
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
    
    // MARK: Dosyadan yukleme
    private func loadParamFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 2 * 1024 * 1024 else {
                presentLoadedFile(LoadedParamFile(fileName: name, parse: .init(),
                                                  error: "File too large for a parameter file"))
                return
            }
            let parsed = ParameterFile.parse(data)
            print("[PARAM] File \(name): \(parsed.entries.count) params, \(parsed.errors.count) bad lines, \(parsed.duplicates) duplicates")
            presentLoadedFile(LoadedParamFile(fileName: name, parse: parsed,
                                              error: parsed.entries.isEmpty
                                                  ? "No parameters found - expected NAME,VALUE lines" : nil))
        } catch {
            presentLoadedFile(LoadedParamFile(fileName: name, parse: .init(),
                                              error: "Cannot open file: \(error.localizedDescription)"))
        }
    }
    
    /// fileImporter kapanirken ayni anda sheet acmak iOS'ta sessizce basarisiz olabiliyor
    private func presentLoadedFile(_ file: LoadedParamFile) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            loadedFile = file
        }
    }
    
    private func writeResultBanner(_ r: MAVLinkManager.ParamWriteResult) -> some View {
        let bad = !r.failed.isEmpty || r.error != nil || r.cancelled
        let text: String = {
            if let err = r.error {
                return "\u{26A0} \(err)" + (r.ok > 0 ? "  (\(r.ok)/\(r.total) confirmed)" : "")
            }
            var t = (r.cancelled ? "Cancelled - " : "\u{2713} ") + "\(r.ok)/\(r.total) parameters confirmed"
            if !r.failed.isEmpty { t += ", \(r.failed.count) failed" }
            return t + ". Reboot the vehicle to apply."
        }()
        return HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Details") { showWriteResult = true }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)
                .buttonStyle(.plain)
            Button(action: { mavlinkManager.clearParamWriteResult() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background((bad ? Color.orange : Color.green).opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(bad ? Color.orange : Color.green, lineWidth: 1))
        .cornerRadius(8)
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

// MARK: - Dosyadan yukleme: onizleme + yazma
struct LoadedParamFile: Identifiable {
    let id = UUID()
    let fileName: String
    let parse: ParameterFile.ParseResult
    let error: String?
    var loaded: Bool { !parse.entries.isEmpty }
}

struct ParamFileSheet: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let file: LoadedParamFile
    let onWrite: ([(String, Float)]) -> Void
    let onCancel: () -> Void
    
    @State private var keepCalibration = true
    @State private var onlyChanged = true
    
    private var plan: ParameterFile.Plan {
        ParameterFile.plan(entries: file.parse.entries, vehicle: mavlinkManager.parameters,
                           keepCalibration: keepCalibration, onlyChanged: onlyChanged)
    }
    
    var body: some View {
        let plan = self.plan
        let vehicleLoaded = !mavlinkManager.parameters.isEmpty
        let canWrite = file.loaded && !plan.items.isEmpty && mavlinkManager.isConnected
            && !mavlinkManager.isArmed && !mavlinkManager.paramWriteInProgress
        
        VStack(spacing: 12) {
            Text("Load parameter file")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Text(file.fileName)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.cyan)
                .lineLimit(1)
                .truncationMode(.middle)
            
            if let error = file.error {
                Text("\u{26A0} \(error)")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if file.loaded {
                Text(summaryText)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !file.parse.errors.isEmpty {
                    Text(file.parse.errors.prefix(3).joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                optionToggle(isOn: $keepCalibration,
                             title: "Keep this vehicle's calibration",
                             detail: "Skips compass/accel/gyro offsets, level trim, RC min/max/trim, power module and sensor IDs (\(plan.skippedCalibration) params)")
                optionToggle(isOn: $onlyChanged,
                             title: "Write only changed values",
                             detail: vehicleLoaded ? "Compared against the parameters read from the vehicle"
                                                   : "Vehicle parameters not read yet - every value will be written")
                
                HStack(spacing: 4) {
                    statCell(plan.items.count, "to write", .cyan)
                    statCell(plan.changed, "changed", .orange)
                    statCell(plan.same, "same", .green)
                    statCell(plan.unknown, "not on vehicle", .gray)
                }
                
                if !plan.changes.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(plan.changes) { c in
                                HStack(spacing: 6) {
                                    Text(c.name)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(c.oldValue.map(formatValue) ?? "-")
                                        .foregroundColor(.gray)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                    Text(formatValue(c.newValue))
                                        .foregroundColor(c.oldValue == nil ? .gray : .cyan)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: min(220, CGFloat(plan.changes.count) * 26 + 8))
                    .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                    .cornerRadius(10)
                }
                
                if mavlinkManager.isArmed {
                    warning("\u{26A0} Vehicle is armed - disarm before writing parameters.", .red)
                } else if !mavlinkManager.isConnected {
                    warning("Not connected - connect to the vehicle to write.", .orange)
                }
                if plan.unknown > 0 && vehicleLoaded {
                    warning("Parameters not on the vehicle usually appear after an *_ENABLE / *_TYPE change and a reboot. Load the file again after rebooting.", .gray)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                if file.loaded {
                    Button(action: { onWrite(plan.items) }) {
                        Text("Write \(plan.items.count) parameters")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canWrite ? Color.red : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canWrite)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .presentationDetents([.large])
        .background(Color(red: 0.07, green: 0.07, blue: 0.12))
    }
    
    private var summaryText: String {
        var t = "\(file.parse.entries.count) parameters in file"
        if file.parse.duplicates > 0 { t += ", \(file.parse.duplicates) duplicates (last value used)" }
        if !file.parse.errors.isEmpty { t += ", \(file.parse.errors.count) unreadable lines ignored" }
        return t
    }
    
    private func optionToggle(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isOn.wrappedValue ? .cyan : .gray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func statCell(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func warning(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Toplu yazma sonucu
struct ParamWriteResultSheet: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let result: MAVLinkManager.ParamWriteResult
    let onReboot: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text(result.source == "defaults" ? "Restore defaults result" : "Parameter file write result")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Text("\(result.ok) of \(result.total) confirmed by the vehicle" + (result.error.map { "\n" + $0 } ?? ""))
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            if !result.failed.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(result.failed) { f in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(f.name).foregroundColor(.white)
                                    Spacer()
                                    Text(formatValue(f.value)).foregroundColor(.cyan)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                Text(f.reason)
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 260)
                .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                .cornerRadius(10)
            }
            
            Text("Most changes take effect after a reboot. Parameters that appear only after enabling a feature need a reboot and a second load.")
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                Button(action: onReboot) {
                    Text("Reboot Vehicle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mavlinkManager.isConnected && !mavlinkManager.isArmed ? Color.orange : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!mavlinkManager.isConnected || mavlinkManager.isArmed)
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .presentationDetents([.medium, .large])
        .background(Color(red: 0.07, green: 0.07, blue: 0.12))
    }
}

#Preview {
    ParametersView()
        .environmentObject(MAVLinkManager.shared)
}
