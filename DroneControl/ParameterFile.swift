//
//  ParameterFile.swift
//  DroneControl
//
//  Parser for ArduPilot parameter files saved by Mission Planner / MAVProxy
//  ("NAME,VALUE" or "NAME VALUE") and QGroundControl ("SYS COMP NAME VALUE TYPE").
//  Lines starting with '#' or '//' are comments. Port-twin of DroneControlQt/src/ParameterFile.cpp.
//

import Foundation

enum ParameterFile {

    struct Entry {
        let name: String
        var value: Float
        let line: Int
    }

    struct ParseResult {
        var entries: [Entry] = []        // file order, duplicates collapsed (last value wins)
        var errors: [String] = []        // "line N: <text>" for unparsable lines
        var duplicates = 0
    }

    enum Kind {
        case normal
        case readOnly       // STAT_*, FORMAT_VERSION - never written
        case calibration    // per-airframe calibration / board IDs - optional skip
    }

    struct Change: Identifiable {
        let name: String
        let oldValue: Float?             // nil: not on the vehicle (or vehicle list not read)
        let newValue: Float
        var id: String { name }
    }

    struct Plan {
        var items: [(String, Float)] = []
        var changed = 0
        var same = 0
        var unknown = 0
        var skippedCalibration = 0
        var skippedReadOnly = 0
        var changes: [Change] = []       // preview, max 500 rows
    }

    // MARK: - Parse

    static func parse(_ data: Data) -> ParseResult {
        var result = ParseResult()
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }              // UTF-8 BOM
        text = text.replacingOccurrences(of: "\r\n", with: "\n")          // "\r\n" is one Character in Swift
        let lines = text.components(separatedBy: "\n")

        var index: [String: Int] = [:]   // name -> position in result.entries

        for (i, rawLine) in lines.enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            if let hash = line.firstIndex(of: "#") {                       // trailing comment
                line = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            }

            let t = line.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
            var name = ""
            var valueText = ""
            if t.count >= 4, Int(t[0]) != nil, Int(t[1]) != nil {
                // QGroundControl: <sysid> <compid> <name> <value> <type>
                name = t[2]
                valueText = t[3]
            } else if t.count >= 2 {
                // Mission Planner / MAVProxy: <name>,<value>
                name = t[0]
                valueText = t[1]
            }

            guard isValidName(name), let v = Double(valueText), v.isFinite else {
                result.errors.append("line \(i + 1): \(String(rawLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48)))")
                continue
            }

            name = name.uppercased()
            if let pos = index[name] {
                result.entries[pos].value = Float(v)
                result.duplicates += 1
            } else {
                index[name] = result.entries.count
                result.entries.append(Entry(name: name, value: Float(v), line: i + 1))
            }
        }
        return result
    }

    private static func isValidName(_ name: String) -> Bool {
        guard (1...16).contains(name.count) else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    // MARK: - Classify

    // Counters / format markers the vehicle owns
    private static let readOnlyRegex = try! NSRegularExpression(pattern: "^(STAT_|FORMAT_VERSION$)")
    // Values earned on a specific airframe/board: sensor calibration, level trim,
    // RC endpoints, power module calibration, sensor device IDs
    private static let calibrationRegex = try! NSRegularExpression(pattern:
        "^(" +
        "COMPASS_(OFS|DIA|ODI|MOT)\\d?_|COMPASS_SCALE\\d?$|COMPASS_DEV_ID\\d?$|COMPASS_PRIO\\d_ID$|" +
        "INS_(ACC|GYR)\\d?(OFFS|SCAL)_|INS_(ACC|GYR)\\d?_(CALTEMP|ID)$|INS_TCAL|" +
        "AHRS_TRIM_|" +
        "RC\\d+_(MIN|MAX|TRIM)$|" +
        "BATT\\d?_(AMP_PERVLT|VOLT_MULT|AMP_OFFSET)$|" +
        "BARO\\d?_(GND_PRESS|DEVID)$|GND_ABS_PRESS" +
        ")")

    static func classify(_ name: String) -> Kind {
        let range = NSRange(name.startIndex..., in: name)
        if readOnlyRegex.firstMatch(in: name, range: range) != nil { return .readOnly }
        if calibrationRegex.firstMatch(in: name, range: range) != nil { return .calibration }
        return .normal
    }

    static func valuesEqual(_ a: Float, _ b: Float) -> Bool {
        if a == b { return true }
        return abs(a - b) <= 1e-6 + 1e-5 * max(abs(a), abs(b))
    }

    // MARK: - Write plan

    /// Decides what to write: skips read-only (always) and calibration values (optional),
    /// and - when `onlyChanged` - values the vehicle already has.
    static func plan(entries: [Entry], vehicle: [String: Float],
                     keepCalibration: Bool, onlyChanged: Bool) -> Plan {
        var plan = Plan()
        for e in entries {
            switch classify(e.name) {
            case .readOnly:
                plan.skippedReadOnly += 1
                continue
            case .calibration where keepCalibration:
                plan.skippedCalibration += 1
                continue
            default:
                break
            }
            let current = vehicle[e.name]
            if let current = current, valuesEqual(current, e.value) {
                plan.same += 1
                if onlyChanged { continue }
            } else {
                if current != nil { plan.changed += 1 } else { plan.unknown += 1 }
                if plan.changes.count < 500 {
                    plan.changes.append(Change(name: e.name, oldValue: current, newValue: e.value))
                }
            }
            plan.items.append((e.name, e.value))
        }
        return plan
    }
}
