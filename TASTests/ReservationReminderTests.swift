import XCTest
@testable import TAS

/// 예약 알림 대상·시각·내용 — 안드로이드 ReminderTest 와 같은 경우를 본다.
final class ReservationReminderTests: XCTestCase {
    private let names = [1: "김민지"]

    private func r(_ id: Int, _ date: String, _ start: String, status: ReservationStatus? = nil, service: String = "남성커트", customerId: Int = 1) -> Reservation {
        Reservation(id: id, date: date, startTime: start, endTime: "23:00", service: service, customerId: customerId, status: status)
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

    func testLeadLabels() {
        XCTAssertEqual(ReservationReminder.leadOptions.map(ReservationReminder.leadLabel), ["끔", "10분 전", "30분 전", "1시간 전"])
    }

    func testItemContentAndTime() {
        let item = ReservationReminder.item(for: r(1, "2026-10-22", "14:00"), customerNames: names, leadMinutes: 30)
        XCTAssertEqual(item?.fireDate, kst("2026-10-22 13:30"))
        XCTAssertEqual(item?.title, "예약 30분 전")
        XCTAssertEqual(item?.body, "14:00 김민지 · 남성커트")
        // 고객을 못 찾으면 캘린더와 같은 "고객 #id", 서비스가 비면 뺀다
        XCTAssertEqual(ReservationReminder.item(for: r(2, "2026-10-22", "14:00", service: "", customerId: 9), customerNames: names, leadMinutes: 30)?.body, "14:00 고객 #9")
    }

    func testOnlyActiveReservations() {
        for status in [ReservationStatus.cancelled, .noshow, .completed, .requested] {
            XCTAssertNil(ReservationReminder.item(for: r(1, "2026-10-22", "14:00", status: status), customerNames: names, leadMinutes: 30))
        }
        XCTAssertNotNil(ReservationReminder.item(for: r(1, "2026-10-22", "14:00", status: .active), customerNames: names, leadMinutes: 30))
        XCTAssertNil(ReservationReminder.item(for: r(1, "2026-10-22", "14:00"), customerNames: names, leadMinutes: 0))
        XCTAssertNil(ReservationReminder.item(for: r(1, "2026-10-22", "2시"), customerNames: names, leadMinutes: 30))
    }

    func testUpcomingWindowOrderAndLimit() {
        let now = kst("2026-10-22 09:00")
        let list = [
            r(1, "2026-10-22", "09:20"), // 08:50 — 지남
            r(2, "2026-10-22", "09:40"), // 09:10
            r(3, "2026-11-25", "10:00"), // 30일 넘음
            r(4, "2026-10-22", "09:31"), // 09:01
        ]
        XCTAssertEqual(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 30, now: now).map(\.reservationId), [4, 2])
        XCTAssertEqual(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 30, now: now, limit: 1).map(\.reservationId), [4])
        XCTAssertEqual(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 0, now: now).count, 0)
    }

    func testLateItem() {
        let late = ReservationReminder.lateItem(for: r(1, "2026-10-22", "14:00"), customerNames: names, lateMinutes: 15)
        XCTAssertEqual(late?.fireDate, kst("2026-10-22 14:15"))
        XCTAssertEqual(late?.kind, .late)
        XCTAssertEqual(late?.title, "손님이 아직 안 오셨나요?")
        XCTAssertEqual(late?.body, "14:00 김민지 · 남성커트 — 예약 15분 지남")
        for status in [ReservationStatus.cancelled, .noshow, .completed, .requested] {
            XCTAssertNil(ReservationReminder.lateItem(for: r(1, "2026-10-22", "14:00", status: status), customerNames: names, lateMinutes: 15))
        }
        // 결제까지 끝났으면 손님은 온 것
        var paid = r(1, "2026-10-22", "14:00")
        paid.paymentCompleted = true
        XCTAssertNil(ReservationReminder.lateItem(for: paid, customerNames: names, lateMinutes: 15))
        XCTAssertNil(ReservationReminder.lateItem(for: r(1, "2026-10-22", "14:00"), customerNames: names, lateMinutes: 0))
        XCTAssertEqual([0, 5, 30].map(ReservationReminder.lateLabel), ["끔", "5분 후", "30분 후"])
    }

    func testUpcomingIncludesLate() {
        let now = kst("2026-10-22 09:00")
        let list = [r(1, "2026-10-22", "09:40")] // 시작 전 09:10, 지각 09:55
        XCTAssertEqual(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 30, now: now, lateMinutes: 15).map(\.kind), [.before, .late])
        XCTAssertEqual(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 0, now: now, lateMinutes: 15).map(\.kind), [.late])
        XCTAssertTrue(ReservationReminder.upcoming(list, customerNames: names, leadMinutes: 0, now: now, lateMinutes: 0).isEmpty)
    }
}
