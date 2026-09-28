import XCTest
@testable import OrarendApp

final class ScheduleTests: XCTestCase {
    var cal: Calendar!

    override func setUp() {
        super.setUp()
        // ISO: hétfő = hét kezdete → stabil weekday-számok
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "hu_HU")
        c.timeZone = TimeZone(secondsFromGMT: 3600)! // CET, suli helyi idő
        cal = c
    }

    /// Adott hétköznap (2=Hé..6=Pé, 1=Vas, 7=Szo) + óra:perc → Date.
    /// 2026-09-14 egy hétfő, innen számolunk.
    func date(weekday: Int, h: Int, m: Int, s: Int = 0) -> Date {
        // 2026-09-14 = hétfő
        let mondayOffset = (weekday + 5) % 7  // Hé=0 … Vas=6
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14 + mondayOffset
        comps.hour = h; comps.minute = m; comps.second = s
        return cal.date(from: comps)!
    }

    func testLessonMorning() {
        // Hétfő 8:30 → 1. óra IR (8:15–9:00), 30p van hátra
        let st = status(at: date(weekday: 2, h: 8, m: 30), calendar: cal)
        XCTAssertEqual(st, .lesson(period: 1, subject: "IR", endMinutes: 9 * 60, remainingSec: 30 * 60, nextSubject: "TEST"))
        XCTAssertEqual(menuBarTitle(for: st), "IR · 30p")
    }

    func testBreakBetween1And2() {
        // 9:05 → szünet, köv: 2. óra TEST 9:10-kor
        let st = status(at: date(weekday: 2, h: 9, m: 5), calendar: cal)
        XCTAssertEqual(st, .breakTime(nextPeriod: 2, nextSubject: "TEST", nextStartMinutes: 9 * 60 + 10, remainingSec: 5 * 60))
    }

    func testLunchBreak9thGrade() {
        // 9.-es sáv: 4. óra 11:50-ig, 5. óra 12:00-tól → 11:55 szünet
        let st = status(at: date(weekday: 3, h: 11, m: 55), calendar: cal)
        if case .breakTime(let p, _, let start, _) = st {
            XCTAssertEqual(p, 5)
            XCTAssertEqual(start, 12 * 60)
        } else { XCTFail("szünetet vártam, kaptam: \(st)") }
    }

    func testBeforeSchool() {
        let st = status(at: date(weekday: 4, h: 7, m: 50), calendar: cal)
        if case .beforeSchool(let s, let p, _, _) = st {
            XCTAssertEqual(p, 1); XCTAssertEqual(s, "TÖRT")
        } else { XCTFail("beforeSchool-t vártam: \(st)") }
    }

    func testAfterSchool() {
        // Kedd utolsó tanított óra a 6. (13:55-ig). 14:30 → vége (7. üres).
        let st = status(at: date(weekday: 3, h: 14, m: 30), calendar: cal)
        XCTAssertEqual(st, .afterSchool)
        XCTAssertEqual(menuBarTitle(for: st), "Vége 🎉")
    }

    func testFridayDoubleLesson() {
        // Péntek 12:10 → 5. óra KTERMTUD (12:00–12:45)
        let st = status(at: date(weekday: 6, h: 12, m: 10), calendar: cal)
        if case .lesson(let p, let s, _, _, _) = st {
            XCTAssertEqual(p, 5); XCTAssertEqual(s, "KTERMTUD")
        } else { XCTFail("órát vártam: \(st)") }
    }

    func testWeekend() {
        XCTAssertEqual(status(at: date(weekday: 7, h: 10, m: 0), calendar: cal), .weekend)
        XCTAssertEqual(status(at: date(weekday: 1, h: 10, m: 0), calendar: cal), .weekend)
    }

    func testLastSecondsCountdown() {
        // 8:59:30 hétfőn → 30mp van hátra az 1. órából
        let st = status(at: date(weekday: 2, h: 8, m: 59, s: 30), calendar: cal)
        XCTAssertEqual(menuBarTitle(for: st), "IR · 30mp")
    }

    func testMonday7OnlyINF() {
        // Hétfő 14:10 (7. óra): INF-nek PROGAL, LO/PÉ-nek már vége (6. óra ANG volt az utolsó)
        let inf = status(at: date(weekday: 2, h: 14, m: 10), calendar: cal, group: .INF)
        if case .lesson(let p, let s, _, _, _) = inf {
            XCTAssertEqual(p, 7); XCTAssertEqual(s, "PROGAL")
        } else { XCTFail("INF-nek PROGAL-t vártam: \(inf)") }
        XCTAssertEqual(status(at: date(weekday: 2, h: 14, m: 10), calendar: cal, group: .LO), .afterSchool)
        XCTAssertEqual(status(at: date(weekday: 2, h: 14, m: 10), calendar: cal, group: .PE), .afterSchool)
        XCTAssertEqual(menuBarTitle(for: inf), "PROGAL · 35p")
    }

    func testTuesdaySplit() {
        // Kedd 5. óra (12:00–12:45): INF: MAT, LO/PÉ: DIGKULT
        let inf = status(at: date(weekday: 3, h: 12, m: 10), calendar: cal, group: .INF)
        let lo = status(at: date(weekday: 3, h: 12, m: 10), calendar: cal, group: .LO)
        if case .lesson(_, let s, _, _, _) = inf { XCTAssertEqual(s, "MAT") }
        else { XCTFail("INF-nek MAT-ot vártam: \(inf)") }
        if case .lesson(_, let s, _, _, _) = lo { XCTAssertEqual(s, "DIGKULT") }
        else { XCTFail("LO-nak DIGKULT-ot vártam: \(lo)") }
        // Kedd 6. óra: fordítva
        let inf6 = status(at: date(weekday: 3, h: 13, m: 20), calendar: cal, group: .INF)
        let lo6 = status(at: date(weekday: 3, h: 13, m: 20), calendar: cal, group: .LO)
        if case .lesson(_, let s, _, _, _) = inf6 { XCTAssertEqual(s, "DIGKULT") }
        else { XCTFail("INF-nek DIGKULT-ot vártam: \(inf6)") }
        if case .lesson(_, let s, _, _, _) = lo6 { XCTAssertEqual(s, "MAT") }
        else { XCTFail("LO-nak MAT-ot vártam: \(lo6)") }
    }

    func testFriday7OnlyLOPE() {
        // Péntek 7. óra (14:05–14:45): csak LO/PÉ-nek GÉPÍ, INF-nek vége 6. óra után
        let lo = status(at: date(weekday: 6, h: 14, m: 10), calendar: cal, group: .LO)
        if case .lesson(let p, let s, _, _, _) = lo {
            XCTAssertEqual(p, 7); XCTAssertEqual(s, "GÉPÍ")
        } else { XCTFail("LO-nak GÉPÍ-t vártam: \(lo)") }
        XCTAssertEqual(status(at: date(weekday: 6, h: 14, m: 10), calendar: cal, group: .INF), .afterSchool)
    }
}
