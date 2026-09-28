import XCTest
@testable import OrarendApp

final class TimetableJSONTests: XCTestCase {
    /// Package `Resources/timetable.json` relative to this file.
    func jsonURL() throws -> URL {
        let thisFile = URL(fileURLWithPath: #file)
        // Tests/OrarendAppTests/<file> → package root is three levels up.
        let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = packageRoot.appendingPathComponent("Resources/timetable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Resources/timetable.json nem található: \(url.path)")
        }
        return url
    }

    func testBundledJSONDecodes() throws {
        let data = try Data(contentsOf: try jsonURL())
        let file = try JSONDecoder().decode(TimetableFile.self, from: data)
        let (bells, table) = try file.decoded()

        XCTAssertEqual(bells.count, 8)
        XCTAssertEqual(bells.first?.startMinutes, 8 * 60 + 15)
        XCTAssertEqual(table[2]?[1]?.commonSubject, "IR")   // hétfő 1. óra közös
        XCTAssertEqual(table[6]?[4]?.commonSubject, "KTERMTUD") // péntek dupla közös
    }

    func testJSONMatchesBuiltinStatus() throws {
        let data = try Data(contentsOf: try jsonURL())
        let file = try JSONDecoder().decode(TimetableFile.self, from: data)
        let (bells, table) = try file.decoded()

        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "hu_HU")
        cal.timeZone = TimeZone(secondsFromGMT: 3600)!

        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14 // hétfő
        comps.hour = 8; comps.minute = 30
        let date = cal.date(from: comps)!

        // JSON-ből töltött órarend ugyanazt adja, mint a beépített.
        let fromJSON = status(at: date, calendar: cal, bellSchedule: bells, timetable: table)
        let builtin = status(at: date, calendar: cal)
        XCTAssertEqual(fromJSON, builtin)
    }

    func testDayKeyVariants() {
        XCTAssertEqual(TimetableFile.weekday(for: "monday"), 2)
        XCTAssertEqual(TimetableFile.weekday(for: "Hétfő"), 2)
        XCTAssertEqual(TimetableFile.weekday(for: "2"), 2)
        XCTAssertEqual(TimetableFile.weekday(for: "friday"), 6)
        XCTAssertNil(TimetableFile.weekday(for: "nonsense"))
    }

    func testSplitDecoding() throws {
        let data = try Data(contentsOf: try jsonURL())
        let file = try JSONDecoder().decode(TimetableFile.self, from: data)
        let (_, table) = try file.decoded()

        // Hétfő 7. PROGAL csak INF-nek
        XCTAssertEqual(table[2]?[7]?.subject(for: .INF), "PROGAL")
        XCTAssertNil(table[2]?[7]?.subject(for: .LO))
        XCTAssertNil(table[2]?[7]?.subject(for: .PE))
        // Kedd 5. INF: MAT, LO/PÉ: DIGKULT; 6. fordítva
        XCTAssertEqual(table[3]?[5]?.subject(for: .INF), "MAT")
        XCTAssertEqual(table[3]?[5]?.subject(for: .LO), "DIGKULT")
        XCTAssertEqual(table[3]?[5]?.subject(for: .PE), "DIGKULT")
        XCTAssertEqual(table[3]?[6]?.subject(for: .INF), "DIGKULT")
        XCTAssertEqual(table[3]?[6]?.subject(for: .LO), "MAT")
        // Szerda 6. INF: INFTÁV, LO/PÉ: GAZDJOGIS
        XCTAssertEqual(table[4]?[6]?.subject(for: .INF), "INFTÁV")
        XCTAssertEqual(table[4]?[6]?.subject(for: .LO), "GAZDJOGIS")
        // Csütörtök 7. INF: GÉPÍ, LO/PÉ: KOM
        XCTAssertEqual(table[5]?[7]?.subject(for: .INF), "GÉPÍ")
        XCTAssertEqual(table[5]?[7]?.subject(for: .LO), "KOM")
        // Péntek 7. csak LO/PÉ-nek GÉPÍ
        XCTAssertNil(table[6]?[7]?.subject(for: .INF))
        XCTAssertEqual(table[6]?[7]?.subject(for: .LO), "GÉPÍ")
        XCTAssertEqual(table[6]?[7]?.subject(for: .PE), "GÉPÍ")
        // Közös óra mindenkinek ugyanaz
        XCTAssertEqual(table[2]?[1]?.commonSubject, "IR")
    }
}
