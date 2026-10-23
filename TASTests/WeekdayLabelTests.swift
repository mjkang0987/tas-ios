import XCTest
@testable import TAS

/// `KST.weekdayLabel(for:)` — 요일 라벨을 **날짜**에서 낸다.
///
/// 칼럼 순서(index)로 내던 때는 주 뷰(월요일 시작)에서만 맞았고, 기준일부터 시작하는
/// 3일 뷰에서는 요일이 밀렸다. 배열이 월요일 시작이라 `(weekday + 5) % 7` 변환이
/// 들어가는데, 이런 환산은 한 칸씩 어긋나기 쉬워 7요일을 모두 못박는다.
final class WeekdayLabelTests: XCTestCase {

    private func label(_ dayKey: String) -> String {
        guard let date = KST.dayKey.date(from: dayKey) else { return "" }
        return KST.weekdayLabel(for: date)
    }

    func testAllSevenWeekdays() {
        // 2026-10-12(월) ~ 2026-10-18(일)
        XCTAssertEqual(label("2026-10-12"), "월")
        XCTAssertEqual(label("2026-10-13"), "화")
        XCTAssertEqual(label("2026-10-14"), "수")
        XCTAssertEqual(label("2026-10-15"), "목")
        XCTAssertEqual(label("2026-10-16"), "금")
        XCTAssertEqual(label("2026-10-17"), "토")
        XCTAssertEqual(label("2026-10-18"), "일")
    }

    /// 주 경계를 넘는 3일(토·일·월)에서도 밀리지 않아야 한다 — index 방식이 깨지던 자리.
    func testAcrossWeekBoundary() {
        XCTAssertEqual(["2026-10-17", "2026-10-18", "2026-10-19"].map(label), ["토", "일", "월"])
    }

    /// 주는 일요일 시작(웹 캘린더와 같다) — 2026-10-22(목)이 든 주는 10-18(일)~10-24(토).
    func testWeekStartsOnSunday() {
        let date = KST.dayKey.date(from: "2026-10-22")!
        let week = KST.calendar.dateInterval(of: .weekOfYear, for: date)!
        XCTAssertEqual(KST.dayKey.string(from: week.start), "2026-10-18")
        XCTAssertEqual(KST.calendarWeekdayLabels.first, "일")
    }
}
