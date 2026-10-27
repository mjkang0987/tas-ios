import XCTest
@testable import TAS

/// 예약 변경 확인 — 웹 getChangedFields·isPastTime 과 같은 경우를 본다.
final class ReservationDiffTests: XCTestCase {
    private let base = Reservation(id: 1, date: "2026-10-27", startTime: "14:00", endTime: "15:00", service: "커트",
                                   customerId: 1, assigneeId: 2, price: 20000)

    private func diff(_ a: Reservation) -> [ReservationDiff.Item] {
        ReservationDiff.fields(before: base, after: a, labels: .default, assigneeName: { $0.map { "담당\($0)" } ?? "미지정" })
    }

    func testNoChangeAndOldChannelCountsAsPhone() {
        XCTAssertEqual(diff(base), [])
        var a = base
        a.channel = .phone
        XCTAssertEqual(diff(a), [], "경로 없던 예약을 전화예약으로 저장해도 변경 아님")
    }

    func testChangedFieldsInWebOrder() {
        var a = base
        a.startTime = "16:00"
        a.assigneeId = nil
        a.price = 25000
        a.memo = "앞머리"
        XCTAssertEqual(diff(a), [
            .init(label: "시작시간", before: "14:00", after: "16:00"),
            .init(label: "담당자", before: "담당2", after: "미지정"),
            .init(label: "가격", before: "20,000원", after: "25,000원"),
            .init(label: "요청사항", before: "", after: "앞머리"),
        ])
    }

    func testIsPastComparesInKST() {
        // 2026-10-27 14:00 KST = 05:00 UTC
        let now = ISO8601DateFormatter().date(from: "2026-10-27T05:00:00Z")!
        XCTAssertTrue(ReservationDiff.isPast(date: "2026-10-27", startTime: "13:59", now: now))
        XCTAssertFalse(ReservationDiff.isPast(date: "2026-10-27", startTime: "14:00", now: now))
        XCTAssertTrue(ReservationDiff.isPast(date: "2026-10-26", startTime: "23:00", now: now))
        XCTAssertFalse(ReservationDiff.isPast(date: "2026-10-28", startTime: "09:00", now: now))
    }
}
