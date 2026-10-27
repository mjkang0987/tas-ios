import XCTest
@testable import TAS

/// 알림 종 '곧 시작'·종 표시 — 웹 notifications.test.ts 와 같은 경우를 본다.
final class UpcomingReservationsTests: XCTestCase {
    private func r(_ id: Int, _ start: String, _ status: ReservationStatus? = nil, date: String = "2026-10-22") -> Reservation {
        Reservation(id: id, date: date, startTime: start, endTime: "23:00", service: "커트", customerId: 1, status: status)
    }

    /// KST 기준 시각.
    private func kst(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = KST.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    private lazy var now = kst("2026-10-22 13:40")

    func testSoonInOrderAndNextOne() {
        let list = [r(1, "14:30"), r(2, "14:00"), r(3, "13:30"), r(4, "14:10", .cancelled), r(5, "16:00"),
                    r(6, "14:50"), r(7, "14:20", .requested), r(8, "10:00", date: "2026-10-23")]
        let (soon, next) = UpcomingReservations.compute(list, now: now)
        XCTAssertEqual(soon.map { [$0.reservation.id, $0.minutesUntil] }, [[2, 20], [1, 50]])
        XCTAssertEqual(next?.reservation.id, 6)
        XCTAssertEqual(next?.minutesUntil, 70)
    }

    func testStartingNowAndNothingLeft() {
        XCTAssertEqual(UpcomingReservations.compute([r(1, "13:40")], now: now).soon.first?.minutesUntil, 0)
        let empty = UpcomingReservations.compute([r(1, "09:00")], now: now)
        XCTAssertTrue(empty.soon.isEmpty)
        XCTAssertNil(empty.next)
        XCTAssertEqual([0, 20, 60, 150].map(UpcomingReservations.untilLabel), ["지금", "20분 후", "1시간 후", "2시간 30분 후"])
    }

    func testBellIndicator() {
        XCTAssertTrue(UpcomingReservations.bellIndicator(todo: 2, soon: 3) == (2, false))
        XCTAssertTrue(UpcomingReservations.bellIndicator(todo: 0, soon: 1) == (0, true))
        XCTAssertTrue(UpcomingReservations.bellIndicator(todo: 0, soon: 0) == (0, false))
    }
}
