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

/// 9B órarend, összevont csoportnevekkel (pl. "SPA/NÉM", "MAT").
/// Ha egy sávban nincs órád (lyukas / nincs), az nil.
/// Hétfő 7. csak egy csoportnak PROGAL → itt "PROGAL"-ként szerepel;
/// ha neked akkor lyukas, vedd ki vagy hagyd figyelmen kívül.
/// Péntek 4–5. összevont dupla KTERMTUD → mindkettő KTERMTUD.
/// Kulcs: hétfő=2 … péntek=6 (Calendar weekday).
public let timetable: [Int: [Int: String]] = [
    2: [1: "IR", 2: "TEST", 3: "MUNKISM", 4: "KTERMTUD", 5: "MAT", 6: "ANG", 7: "PROGAL"],
    3: [1: "MNY", 2: "TEST", 3: "SPA/NÉM", 4: "TÖRT", 5: "MAT/DIGKULT", 6: "DIGKULT/MAT"],
    4: [1: "TÖRT", 2: "IR", 3: "MAT", 4: "ANG", 5: "OFŐ", 6: "GAZDJOGIS/INFTÁV", 7: "KOM/IKT"],
    5: [1: "IR", 2: "GAZDJOGIS/INFTÁV", 3: "ANG", 4: "SPA/NÉM", 5: "GÉPÍ/PROGAL", 6: "TÖRT", 7: "KOM/GÉPÍ"],
    6: [1: "TEST", 2: "ANG", 3: "SPA/NÉM", 4: "KTERMTUD", 5: "KTERMTUD", 6: "GAZDJOGIS/INFTÁV", 7: "GÉPÍ"],
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
public func status(at date: Date, calendar: Calendar = .current) -> SchoolStatus {
    let weekday = calendar.component(.weekday, from: date) // 1=vas, 7=szo
    if weekday == 1 || weekday == 7 { return .weekend }
    guard let dayTable = timetable[weekday], !dayTable.isEmpty else { return .noSchoolToday }

    let nowSec = secondsSinceMidnight(date, calendar: calendar)
    let periods = bellSchedule.sorted { $0.number < $1.number }

    let taughtPeriods = periods.filter { dayTable[$0.number] != nil }
    guard let first = taughtPeriods.first, let last = taughtPeriods.last else {
        return .noSchoolToday
    }

    func sec(_ minutes: Int) -> Int { minutes * 60 }

    // Tanítás előtt
    if nowSec < sec(first.startMinutes) {
        let subj = dayTable[first.number] ?? ""
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
            if let subj = dayTable[p.number] {
                // következő tanított óra keresése (nem csak p.number+1, mert lehet lyukas)
                var nextSubj: String? = nil
                for q in periods where q.number > p.number {
                    if let t = dayTable[q.number] { nextSubj = t; break }
                }
                return .lesson(
                    period: p.number, subject: subj,
                    endMinutes: p.endMinutes,
                    remainingSec: e - nowSec,
                    nextSubject: nextSubj
                )
            } else {
                // Lyukas óra tanítási időben (pl. hétfő 7. ha neked nincs PROGAL-od)
                var ns: String? = nil; var nStart: Int? = nil
                for q in periods where q.number > p.number {
                    if let t = dayTable[q.number] { ns = t; nStart = q.startMinutes; break }
                }
                return .freePeriod(nextSubject: ns, nextStartMinutes: nStart, remainingSec: e - nowSec)
            }
        }
        // Szünet: e és a következő csengetés kezdete között
        if idx + 1 < periods.count {
            let n = periods[idx + 1]
            let ns = sec(n.startMinutes)
            if nowSec >= e && nowSec < ns {
                // Ha már az utolsó tanított óra után vagyunk, az afterSchool
                // (pl. kedd 7–8. üres → 6. óra vége után ne "szünetet" mutasson)
                let anyLessonLeft: Bool = periods.contains { q in
                    q.number >= n.number && dayTable[q.number] != nil
                }
                if !anyLessonLeft { return .afterSchool }
                let nextSubj = dayTable[n.number] // lehet nil → lyukas következik
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
