import Foundation

/// Csengetési rend 9. évfolyam szerint (második kép, jobb oszlop).
/// 8. óra nincs a csengetési táblában → fallback: 15:00–15:45 (órarend kép alja).
/// Könnyen átírható itt.
public struct BellPeriod: Equatable {
    public let number: Int
    public let startMinutes: Int  // éjfél óta, pl. 8:15 = 495
    public let endMinutes: Int

    public init(_ number: Int, _ startH: Int, _ startM: Int, _ endH: Int, _ endM: Int) {
        self.number = number
        self.startMinutes = startH * 60 + startM
        self.endMinutes = endH * 60 + endM
    }

    public var startLabel: String { Self.fmt(startMinutes) }
    public var endLabel: String { Self.fmt(endMinutes) }

    public static func fmt(_ m: Int) -> String {
        String(format: "%d:%02d", m / 60, m % 60)
    }
}

public let bellSchedule: [BellPeriod] = [
    BellPeriod(1, 8, 15, 9, 0),
    BellPeriod(2, 9, 10, 9, 55),
    BellPeriod(3, 10, 10, 10, 55),
    BellPeriod(4, 11, 5, 11, 50),
    BellPeriod(5, 12, 0, 12, 45),
    BellPeriod(6, 13, 10, 13, 55),
    BellPeriod(7, 14, 5, 14, 45),
    // Fallback, lásd komment fent:
    BellPeriod(8, 15, 0, 15, 45),
]

/// Csoportok: INF külön sávon, LO és PÉ mindig együtt (ugyanaz az órájuk),
/// de külön választhatók a Settingsben.
public enum StudentGroup: String, CaseIterable, Equatable, Codable {
    case INF = "INF"
    case LO = "LO"
    case PE = "PÉ"

    public var displayName: String {
        switch self {
        case .INF: return "INF"
        case .LO: return "LO"
        case .PE: return "PÉ"
        }
    }

    /// JSON-kulcs variánsok ("PÉ", "PE", "P", "LOPE", "LO/PÉ", …) → csoport.
    /// A "LOPÉ"/"LOPE"/"LO-PÉ"/"LO/PÉ" mindkét csoportra (LO + PÉ) vonatkozik.
    public static func groups(forKey key: String) -> [StudentGroup]? {
        let k = key.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: "É", with: "E")
        switch k {
        case "INF", "I": return [.INF]
        case "LO", "L": return [.LO]
        case "PE", "PÉ", "P": return [.PE]
        case "LOPE", "LOPÉ", "LO-PE", "LO-PÉ", "LO/PE", "LO/PÉ", "LO_PE", "LO_PÉ":
            return [.LO, .PE]
        default: return nil
        }
    }
}

/// Egy tanóra: vagy mindenkinek közös, vagy csoportbontott.
/// - Közös: `subjects` mindhárom csoportra ugyanazt tartalmazza (vagy `common`).
/// - Bontott: csak annak van órája, aki a dict-ben szerepel (hiányzó = lyukas).
///   Pl. hétfő 7. `{"INF": "PROGAL"}` → LO/PÉ-nek lyukas.
///   Péntek 7. `{"LO": "GÉPÍ", "PÉ": "GÉPÍ"}` → INF-nek lyukas.
public struct GroupLesson: Equatable {
    public var subjects: [StudentGroup: String]

    public init(_ subjects: [StudentGroup: String]) {
        self.subjects = subjects
    }

    public init(common: String) {
        self.subjects = [.INF: common, .LO: common, .PE: common]
    }

    /// Adott csoport órája (nil = neki lyukas).
    public func subject(for group: StudentGroup) -> String? {
        subjects[group]
    }

    /// Van-e bárkinek órája ebben a sávban?
    public var isEmpty: Bool { subjects.isEmpty }

    /// Közös-e (mindhárom csoportnak ugyanaz)?
    public var commonSubject: String? {
        guard let inf = subjects[.INF], let lo = subjects[.LO], let pe = subjects[.PE],
              inf == lo, lo == pe
        else { return nil }
        return inf
    }

    /// GUI-lista szöveg a saját csoport kiemeléséhez.
    /// - Közös → "MAT"
    /// - INF vs LO/PÉ → "INF: MAT · LO/PÉ: DIGKULT"
    /// - Csak INF → "PROGAL (csak INF)"
    public func displayText(ownGroup: StudentGroup) -> String {
        if let c = commonSubject { return c }
        let own = subjects[ownGroup]
        // LO/PÉ összevonva, ha ugyanaz
        let lo = subjects[.LO]
        let pe = subjects[.PE]
        let inf = subjects[.INF]
        if lo != nil, lo == pe {
            let other: String? = (ownGroup == .INF) ? lo : inf
            let otherLabel = (ownGroup == .INF) ? "LO/PÉ" : "INF"
            switch (own, other) {
            case (let o?, let t?):
                return "\(o) · \(otherLabel): \(t)"
            case (let o?, nil):
                if ownGroup == .INF { return "\(o) (csak INF)" }
                return "\(o) (csak LO/PÉ)"
            case (nil, let t?):
                return "lyukas · \(otherLabel): \(t)"
            case (nil, nil):
                // Pl. LO-nak van, PÉ-nek nincs — ritka, de kezeljük
                return subjects.map { "\($0.key.displayName): \($0.value)" }.sorted().joined(separator: " · ")
            }
        }
        // Általános eset (LO ≠ PÉ)
        var parts: [String] = []
        for g in StudentGroup.allCases {
            if let s = subjects[g] {
                parts.append(g == ownGroup ? s : "\(g.displayName): \(s)")
            }
        }
        if subjects[ownGroup] == nil { parts.insert("lyukas", at: 0) }
        return parts.joined(separator: " · ")
    }

    /// Rövid felirat csak a saját csoportról (menübar / fejléc).
    public func shortText(ownGroup: StudentGroup) -> String? {
        subjects[ownGroup]
    }
}

/// 9B órarend csoportbontással.
/// - Ami közös (nincs bontás), az mindenkihez tartozik.
/// - Hétfő 7. PROGAL csak INF-nek.
/// - Kedd 5. INF: MAT, LO/PÉ: DIGKULT; 6. fordítva.
/// - INFTÁV / IKT / PROGAL mindig INF; GAZDJOGISM / KOM mindig LO/PÉ.
/// - Csütörtök 5. LO/PÉ: GÉPÍ, INF: PROGAL.
/// - Csütörtök 7. LO/PÉ: KOM, INF: GÉPÍ.
/// - Péntek 7. GÉPÍ csak LO/PÉ-nek.
/// Kulcs: hétfő=2 … péntek=6 (Calendar weekday).
public let timetable: [Int: [Int: GroupLesson]] = [
    2: [1: GroupLesson(common: "IR"), 2: GroupLesson(common: "TEST"),
        3: GroupLesson(common: "MUNKISM"), 4: GroupLesson(common: "KTERMTUD"),
        5: GroupLesson(common: "MAT"), 6: GroupLesson(common: "ANG"),
        7: GroupLesson([.INF: "PROGAL"])],
    3: [1: GroupLesson(common: "MNY"), 2: GroupLesson(common: "TEST"),
        3: GroupLesson(common: "SPA/NÉM"), 4: GroupLesson(common: "TÖRT"),
        5: GroupLesson([.INF: "MAT", .LO: "DIGKULT", .PE: "DIGKULT"]),
        6: GroupLesson([.INF: "DIGKULT", .LO: "MAT", .PE: "MAT"])],
    4: [1: GroupLesson(common: "TÖRT"), 2: GroupLesson(common: "IR"),
        3: GroupLesson(common: "MAT"), 4: GroupLesson(common: "ANG"),
        5: GroupLesson(common: "OFŐ"),
        6: GroupLesson([.INF: "INFTÁV", .LO: "GAZDJOGIS", .PE: "GAZDJOGIS"]),
        7: GroupLesson([.INF: "IKT", .LO: "KOM", .PE: "KOM"])],
    5: [1: GroupLesson(common: "IR"),
        2: GroupLesson([.INF: "INFTÁV", .LO: "GAZDJOGIS", .PE: "GAZDJOGIS"]),
        3: GroupLesson(common: "ANG"), 4: GroupLesson(common: "SPA/NÉM"),
        5: GroupLesson([.INF: "PROGAL", .LO: "GÉPÍ", .PE: "GÉPÍ"]),
        6: GroupLesson(common: "TÖRT"),
        7: GroupLesson([.INF: "GÉPÍ", .LO: "KOM", .PE: "KOM"])],
    6: [1: GroupLesson(common: "TEST"), 2: GroupLesson(common: "ANG"),
        3: GroupLesson(common: "SPA/NÉM"), 4: GroupLesson(common: "KTERMTUD"),
        5: GroupLesson(common: "KTERMTUD"),
        6: GroupLesson([.INF: "INFTÁV", .LO: "GAZDJOGIS", .PE: "GAZDJOGIS"]),
        7: GroupLesson([.LO: "GÉPÍ", .PE: "GÉPÍ"])],
]

public enum SchoolStatus: Equatable {
    case weekend
    case noSchoolToday
    case beforeSchool(firstSubject: String, period: Int, startMinutes: Int, remainingSec: Int)
    case lesson(period: Int, subject: String, endMinutes: Int, remainingSec: Int, nextSubject: String?)
    case freePeriod(nextSubject: String?, nextStartMinutes: Int?, remainingSec: Int)
    case breakTime(nextPeriod: Int, nextSubject: String?, nextStartMinutes: Int, remainingSec: Int)
    case afterSchool
}

public func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

public func secondsSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
    let c = calendar.dateComponents([.hour, .minute, .second], from: date)
    return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
}

/// A menübar-logika szíve. Minden kiszámítható belőle, ezért unit-tesztelhető.
/// A `group` a saját csoportod: a menübar CSAK ennek a tárgyát mutatja,
/// a csoportbontás részletezése a GUI (popover lista) dolga.
/// Alapból a beépített órarendet használja; a `bellSchedule`/`timetable`
/// paraméterekkel JSON-ből töltött órarend is beadható (lásd TimetableStore).
public func status(
    at date: Date,
    calendar: Calendar = .current,
    bellSchedule bellsOverride: [BellPeriod]? = nil,
    timetable tableOverride: [Int: [Int: GroupLesson]]? = nil,
    group: StudentGroup = .INF
) -> SchoolStatus {
    let bells = bellsOverride ?? bellSchedule
    let table = tableOverride ?? timetable
    let weekday = calendar.component(.weekday, from: date) // 1=vas, 7=szo
    if weekday == 1 || weekday == 7 { return .weekend }
    guard let dayTable = table[weekday], !dayTable.isEmpty else { return .noSchoolToday }

    let nowSec = secondsSinceMidnight(date, calendar: calendar)
    let periods = bells.sorted { $0.number < $1.number }

    // Csak a saját csoportod számít bele a "tanított" sávokba:
    // ha neked lyukas (pl. hétfő 7. LO/PÉ-nek), az nem tart bent tovább.
    func ownSubject(_ period: Int) -> String? {
        dayTable[period]?.subject(for: group)
    }
    // De a sáv létezik, ha BÁRKINEK van órája (a GUI ezt mutatja).
    func anyLesson(_ period: Int) -> Bool {
        guard let l = dayTable[period] else { return false }
        return !l.isEmpty
    }

    let taughtPeriods = periods.filter { ownSubject($0.number) != nil }
    guard let first = taughtPeriods.first, let last = taughtPeriods.last else {
        return .noSchoolToday
    }

    func sec(_ minutes: Int) -> Int { minutes * 60 }

    // Tanítás előtt
    if nowSec < sec(first.startMinutes) {
        let subj = ownSubject(first.number) ?? ""
        return .beforeSchool(
            firstSubject: subj, period: first.number,
            startMinutes: first.startMinutes,
            remainingSec: sec(first.startMinutes) - nowSec
        )
    }
    // Tanítás után
    if nowSec >= sec(last.endMinutes) { return .afterSchool }

    for (idx, p) in periods.enumerated() {
        let s = sec(p.startMinutes), e = sec(p.endMinutes)
        // Óra alatt
        if nowSec >= s && nowSec < e {
            if let subj = ownSubject(p.number) {
                // következő saját órád keresése (nem csak p.number+1, mert lehet lyukas)
                var nextSubj: String? = nil
                for q in periods where q.number > p.number {
                    if let t = ownSubject(q.number) { nextSubj = t; break }
                }
                return .lesson(
                    period: p.number, subject: subj,
                    endMinutes: p.endMinutes,
                    remainingSec: e - nowSec,
                    nextSubject: nextSubj
                )
            } else {
                // Neked lyukas ebben a sávban (másoknak lehet órája).
                // Ha már nincs több saját órád, vége — ne mutasson "szünetet" mások órája miatt.
                var ns: String? = nil; var nStart: Int? = nil
                for q in periods where q.number > p.number {
                    if let t = ownSubject(q.number) { ns = t; nStart = q.startMinutes; break }
                }
                // Ha a sávban senkinek sincs órája, az is sima lyukas.
                _ = anyLesson(p.number)
                return .freePeriod(nextSubject: ns, nextStartMinutes: nStart, remainingSec: e - nowSec)
            }
        }
        // Szünet: e és a következő csengetés kezdete között
        if idx + 1 < periods.count {
            let n = periods[idx + 1]
            let ns = sec(n.startMinutes)
            if nowSec >= e && nowSec < ns {
                // Ha már az utolsó SAJÁT órád után vagyunk, az afterSchool
                // (pl. hétfő 7. csak INF-nek → LO/PÉ-nek 6. óra vége után vége van;
                //  péntek 7. csak LO/PÉ-nek → INF-nek 6. óra vége után vége van)
                let anyLessonLeft: Bool = periods.contains { q in
                    q.number >= n.number && ownSubject(q.number) != nil
                }
                if !anyLessonLeft { return .afterSchool }
                let nextSubj = ownSubject(n.number) // lehet nil → neked lyukas következik
                return .breakTime(
                    nextPeriod: n.number, nextSubject: nextSubj,
                    nextStartMinutes: n.startMinutes,
                    remainingSec: ns - nowSec
                )
            }
        }
    }
    return .afterSchool
}

// MARK: - Megjelenítés

/// Rövid menübar-felirat, pl. "IR · 12p", "SZ · 5p · MAT", "Kezd 8:15", "Vége".
public func menuBarTitle(for st: SchoolStatus) -> String {
    switch st {
    case .weekend: return "Hétvége"
    case .noSchoolToday: return "Nincs suli"
    case .afterSchool: return "Vége 🎉"
    case .beforeSchool(let subj, _, let start, _):
        return "Kezd \(BellPeriod.fmt(start)) · \(subj)"
    case .lesson(_, let subj, _, let rem, _):
        return "\(subj) · \(compactDuration(rem))"
    case .freePeriod(_, _, let rem):
        return "Lyukas · \(compactDuration(rem))"
    case .breakTime(_, let next, _, let rem):
        if let n = next { return "SZ · \(compactDuration(rem)) · \(n)" }
        return "SZ · \(compactDuration(rem))"
    }
}

/// "12p", "45mp", "1ó 5p" formátum.
public func compactDuration(_ sec: Int) -> String {
    if sec < 60 { return "\(sec)mp" }
    let m = (sec + 59) / 60  // felfelé kerekítve, hogy "0p" sose legyen óra alatt
    if m < 60 { return "\(m)p" }
    return "\(m / 60)ó \(m % 60)p"
}

public func fullCountdown(_ sec: Int) -> String {
    let m = sec / 60, s = sec % 60
    if m >= 60 { return String(format: "%d:%02d:%02d", m / 60, m % 60, s) }
    return String(format: "%d:%02d", m, s)
}
