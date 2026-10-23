import XCTest
@testable import TAS

/// 월 달력 칸(앞뒤 달 날짜 포함)과 캘린더 합계 규칙.
@MainActor
final class CalendarMonthTests: XCTestCase {
    private func keys(_ year: Int, _ month: Int) -> [String] {
        let first = KST.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return CalendarView.monthGridDates(first).map { KST.dayKey.string(from: $0) }
    }

    func testOctober2026StartsOnSundaySep27AndEndsOnSaturday() {
        // 2026-10-01 은 목요일, 10-31 은 토요일 → 9/27(일)부터 10/31 까지 5주
        let k = keys(2026, 10)
        XCTAssertEqual(k.first, "2026-09-27")
        XCTAssertEqual(k.last, "2026-10-31")
        XCTAssertEqual(k.count, 35)
    }

    func testDecember2026FillsNextMonthToSaturday() {
        // 12-01 화요일, 12-31 목요일 → 11/29(일)부터 1/2(토)까지
        let k = keys(2026, 12)
        XCTAssertEqual(k.first, "2026-11-29")
        XCTAssertEqual(k.last, "2027-01-02")
        XCTAssertEqual(k.count % 7, 0)
    }

    func testFebruary2015IsExactlyFourWeeks() {
        // 2015-02-01 일요일, 28일 토요일 — 앞뒤 칸 없이 4주
        let k = keys(2015, 2)
        XCTAssertEqual(k.first, "2015-02-01")
        XCTAssertEqual(k.last, "2015-02-28")
        XCTAssertEqual(k.count, 28)
    }

    func testBookedTotalExcludesCancelledNoshowAndRequested() {
        func r(_ status: ReservationStatus?) -> Reservation {
            var x = Reservation(id: 1, date: "2026-10-23", startTime: "10:00", endTime: "11:00", service: "커트", customerId: 1)
            x.status = status
            return x
        }
        XCTAssertTrue(CalendarViewModel.countsAsBooked(r(nil)))
        XCTAssertTrue(CalendarViewModel.countsAsBooked(r(.completed)))
        XCTAssertFalse(CalendarViewModel.countsAsBooked(r(.cancelled)))
        XCTAssertFalse(CalendarViewModel.countsAsBooked(r(.noshow)))
        XCTAssertFalse(CalendarViewModel.countsAsBooked(r(.requested)))
    }
}
