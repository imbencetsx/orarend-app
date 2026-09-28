import Foundation
import Combine

/// JSON-file based timetable.
///
/// File format (`timetable.json`):
/// ```json
/// {
///   "bellSchedule": [{ "number": 1, "start": "8:15", "end": "9:00" }],
///   "timetable": { "monday": { "1": "IR", "2": "TEST" } }
/// }
/// ```
/// - Times are `"H:MM"` (24h).
/// - Day keys accept english names (`monday`…`friday`, also `saturday`/`sunday`),
///   hungarian names (`hétfő`, `kedd`, …) or Calendar weekday numbers (`"2"`…`"6"`).
/// - A `null` subject (or a missing period) means a free period.
///
/// Lookup order:
/// 1. `~/Library/Application Support/OrarendApp/timetable.json` (user-editable override)
/// 2. Bundled `timetable.json` (next to the app / in `Resources/`)
/// 3. Built-in defaults from `Schedule.swift`
///
/// On first launch the bundled file is copied to Application Support so the
/// user immediately has an editable copy.
public struct TimetableFile: Codable {
    public struct BellEntry: Codable {
        public var number: Int
        public var start: String
        public var end: String

        public init(number: Int, start: String, end: String) {
            self.number = number
            self.start = start
            self.end = end
        }
    }

    public var bellSchedule: [BellEntry]
    /// Day key → period key → subject (`nil` = free period).
    public var timetable: [String: [String: String?]]

    public init(bellSchedule: [BellEntry], timetable: [String: [String: String?]]) {
        self.bellSchedule = bellSchedule
        self.timetable = timetable
    }

    // MARK: - Parsing

    public enum LoadError: LocalizedError {
        case emptyBellSchedule
        case emptyTimetable
        case invalidTime(String)

        public var errorDescription: String? {
            switch self {
            case .emptyBellSchedule: return "A bellSchedule üres."
            case .emptyTimetable: return "A timetable üres."
            case .invalidTime(let s): return "Érvénytelen idő: \(s) (várt formátum: 8:15)."
            }
        }
    }

    /// `"8:15"` → minutes since midnight.
    public static func parseTime(_ s: String) throws -> Int {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m)
        else { throw LoadError.invalidTime(s) }
        return h * 60 + m
    }

    public static func formatTime(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Day key → Calendar weekday (1=Sunday … 7=Saturday).
    public static func weekday(for dayKey: String) -> Int? {
        let k = dayKey.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = Int(k), (1...7).contains(n) { return n }
        switch k {
        case "monday", "mon", "hétfő", "hetfo", "h", "hé": return 2
        case "tuesday", "tue", "kedd", "k", "ke": return 3
        case "wednesday", "wed", "szerda", "sze": return 4
        case "thursday", "thu", "csütörtök", "csutortok", "cs": return 5
        case "friday", "fri", "péntek", "pentek", "p", "pé": return 6
        case "saturday", "sat", "szombat", "szo": return 7
        case "sunday", "sun", "vasárnap", "vasarnap", "v": return 1
        default: return nil
        }
    }

    public func decoded() throws -> (bells: [BellPeriod], table: [Int: [Int: String]]) {
        var bells: [BellPeriod] = []
        for e in bellSchedule {
            let s = try Self.parseTime(e.start)
            let en = try Self.parseTime(e.end)
            bells.append(BellPeriod(number: e.number, startMinutes: s, endMinutes: en))
        }
        guard !bells.isEmpty else { throw LoadError.emptyBellSchedule }

        var table: [Int: [Int: String]] = [:]
        for (dayKey, periods) in timetable {
            guard let wd = Self.weekday(for: dayKey) else { continue }
            var day: [Int: String] = [:]
            for (periodKey, subject) in periods {
                guard let p = Int(periodKey), let s = subject, !s.isEmpty else { continue }
                day[p] = s
            }
            if !day.isEmpty { table[wd] = day }
        }
        guard !table.isEmpty else { throw LoadError.emptyTimetable }
        return (bells.sorted { $0.number < $1.number }, table)
    }
}

extension BellPeriod {
    init(number: Int, startMinutes: Int, endMinutes: Int) {
        self.init(number, startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    }
}

// MARK: - Store

/// Loads the timetable from JSON, publishes it for SwiftUI, falls back to built-ins.
public final class TimetableStore: ObservableObject {
    @Published public private(set) var bells: [BellPeriod] = bellSchedule
    @Published public private(set) var table: [Int: [Int: String]] = timetable
    @Published public private(set) var sourceURL: URL?
    @Published public private(set) var errorMessage: String?

    public init() {
        load()
    }

    /// `~/Library/Application Support/OrarendApp/timetable.json`
    public static var userFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OrarendApp/timetable.json")
    }

    /// Bundled default (app bundle Resources, or package `Resources/` during dev).
    public static func bundledFileURL() -> URL? {
        // 1. Real app bundle (OrarendApp.app/Contents/Resources via build-app.sh,
        //    or SwiftPM-declared resources).
        if let url = Bundle.main.url(forResource: "timetable", withExtension: "json"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // 2. Dev fallback: package `Resources/timetable.json` relative to this file.
        //    This file lives in Sources/OrarendApp/ → package root is ../..
        let thisFile = URL(fileURLWithPath: #file)
        let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let devURL = packageRoot.appendingPathComponent("Resources/timetable.json")
        if FileManager.default.fileExists(atPath: devURL.path) { return devURL }
        return nil
    }

    /// (Re)load from disk. Keeps the previous values on failure and reports the error.
    public func load() {
        let fm = FileManager.default
        let userURL = Self.userFileURL

        // First launch: seed an editable copy from the bundled default.
        if !fm.fileExists(atPath: userURL.path), let bundled = Self.bundledFileURL() {
            try? fm.createDirectory(at: userURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.copyItem(at: bundled, to: userURL)
        }

        if fm.fileExists(atPath: userURL.path) {
            do {
                let file = try decode(from: userURL)
                try apply(file, source: userURL)
                errorMessage = nil
                return
            } catch {
                // User file broken → try bundled fallback, keep error visible.
                if let bundled = Self.bundledFileURL(),
                   let file = try? decode(from: bundled),
                   let d = try? file.decoded() {
                    bells = d.bells
                    table = d.table
                    sourceURL = bundled
                }
                errorMessage = "Hiba a \(userURL.path) fájlban: \(error.localizedDescription)"
                return
            }
        }

        if let bundled = Self.bundledFileURL(),
           let file = try? decode(from: bundled),
           let d = try? file.decoded() {
            bells = d.bells
            table = d.table
            sourceURL = bundled
            errorMessage = nil
        } else {
            bells = bellSchedule
            table = timetable
            sourceURL = nil
            errorMessage = nil
        }
    }

    private func decode(from url: URL) throws -> TimetableFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TimetableFile.self, from: data)
    }

    private func apply(_ file: TimetableFile, source: URL) throws {
        let d = try file.decoded()
        bells = d.bells
        table = d.table
        sourceURL = source
    }
}
