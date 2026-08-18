import XCTest
@testable import TAS

/// 휴무 판정(`Store.closedKind(on:)`) — 웹 `getStoreClosedKind` 이식본 검증.
///
/// 핵심은 요일 인덱스 변환이다. 앱·웹 공통 dayIndex 는 0=월 … 6=일 인데
/// `Calendar.weekday` 는 1=일 … 7=토라, 변환을 빼먹거나 방향을 틀리면
/// **하루씩 밀린 요일에 휴무가 표시된다.**
final class StoreClosedKindTests: XCTestCase {

    private func store(dates: [String] = [], weekdays: [Int] = []) -> Store {
        Store(id: "s1", name: "매장", closedDates: dates, closedWeekdays: weekdays)
    }

    // 2026-08-17(월) … 2026-08-23(일). (날짜, dayIndex)
    private static let week: [(key: String, index: Int)] = [
        ("2026-08-17", 0), ("2026-08-18", 1), ("2026-08-19", 2), ("2026-08-20", 3),
        ("2026-08-21", 4), ("2026-08-22", 5), ("2026-08-23", 6),
    ]

    func testClosedDateReturnsDateKind() {
        XCTAssertEqual(store(dates: ["2026-08-18"]).closedKind(on: "2026-08-18"), .date)
        XCTAssertNil(store(dates: ["2026-08-18"]).closedKind(on: "2026-08-19"))
    }

    func testClosedWeekdayMatchesOnlyThatWeekday() {
        for (key, index) in Self.week {
            let s = store(weekdays: [index])
            XCTAssertEqual(s.closedKind(on: key), .weekday, "dayIndex \(index) 는 \(key) 여야 한다")

            for other in Self.week where other.key != key {
                XCTAssertNil(s.closedKind(on: other.key), "dayIndex \(index) 인데 \(other.key) 가 휴무로 잡혔다")
            }
        }
    }

    /// 일요일은 Calendar.weekday=1, dayIndex=6 — 변환 실수를 가장 잘 드러낸다.
    func testSundayIndex() {
        XCTAssertEqual(store(weekdays: [6]).closedKind(on: "2026-08-23"), .weekday)
        XCTAssertNil(store(weekdays: [0]).closedKind(on: "2026-08-23"))
    }

    func testClosedDateWinsOverWeekday() {
        let s = store(dates: ["2026-08-18"], weekdays: [1])
        XCTAssertEqual(s.closedKind(on: "2026-08-18"), .date)
    }

    func testEmptySettingsAndBrokenDateAreNil() {
        XCTAssertNil(store().closedKind(on: "2026-08-18"))
        XCTAssertNil(store(weekdays: [0, 1, 2, 3, 4, 5, 6]).closedKind(on: "날짜아님"))
    }

    func testLabels() {
        XCTAssertEqual(StoreClosedKind.date.label, "휴업일")
        XCTAssertEqual(StoreClosedKind.weekday.label, "정기휴무")
    }
}
