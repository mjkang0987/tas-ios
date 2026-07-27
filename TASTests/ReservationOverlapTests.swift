import XCTest
@testable import TAS

/// 담당자 겹침(중복 예약) 판정 유틸 테스트 — 예약 폼 경고의 핵심 로직.
final class ReservationOverlapTests: XCTestCase {

    func testMinutesParsing() {
        XCTAssertEqual(ReservationOverlap.minutes("09:30"), 9 * 60 + 30)
        XCTAssertEqual(ReservationOverlap.minutes("00:00"), 0)
        XCTAssertEqual(ReservationOverlap.minutes("23:59"), 23 * 60 + 59)
        XCTAssertNil(ReservationOverlap.minutes("9:30:00"))
        XCTAssertNil(ReservationOverlap.minutes("abc"))
        XCTAssertNil(ReservationOverlap.minutes("10"))
    }

    func testIntervalsOverlap() {
        XCTAssertTrue(ReservationOverlap.intervalsOverlap(60, 120, 90, 150))   // 부분 겹침
        XCTAssertTrue(ReservationOverlap.intervalsOverlap(60, 200, 90, 120))   // 포함
        XCTAssertFalse(ReservationOverlap.intervalsOverlap(60, 120, 120, 180)) // 경계 접함=겹침 아님
        XCTAssertFalse(ReservationOverlap.intervalsOverlap(60, 120, 130, 180)) // 떨어짐
    }

    // MARK: - conflicts

    private func res(_ id: Int, _ start: String, _ end: String,
                     assignee: Int?, status: ReservationStatus? = .active,
                     date: String = "2026-07-24") -> Reservation {
        Reservation(id: id, date: date, startTime: start, endTime: end,
                    service: "컷", customerId: 1, assigneeId: assignee, status: status)
    }

    func testConflictSameAssigneeOverlap() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:30", endTime: "11:30", assigneeId: 7,
            among: [res(1, "10:00", "11:00", assignee: 7)])
        XCTAssertEqual(hits.map(\.id), [1])
    }

    func testDifferentAssigneeIgnored() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:30", endTime: "11:30", assigneeId: 7,
            among: [res(1, "10:00", "11:00", assignee: 8)])
        XCTAssertTrue(hits.isEmpty)
    }

    func testCancelledAndNoshowExcluded() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:30", endTime: "11:30", assigneeId: 7,
            among: [
                res(1, "10:00", "11:00", assignee: 7, status: .cancelled),
                res(2, "10:00", "11:00", assignee: 7, status: .noshow),
            ])
        XCTAssertTrue(hits.isEmpty)
    }

    func testSelfExcluded() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:00", endTime: "11:00", assigneeId: 7,
            among: [res(5, "10:00", "11:00", assignee: 7)], excludingId: 5)
        XCTAssertTrue(hits.isEmpty)
    }

    func testBoundaryTouchIsNotConflict() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "11:00", endTime: "12:00", assigneeId: 7,
            among: [res(1, "10:00", "11:00", assignee: 7)])
        XCTAssertTrue(hits.isEmpty)
    }

    func testNilAssigneeReturnsEmpty() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:30", endTime: "11:30", assigneeId: nil,
            among: [res(1, "10:00", "11:00", assignee: nil)])
        XCTAssertTrue(hits.isEmpty)
    }

    func testDifferentDateIgnored() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "10:30", endTime: "11:30", assigneeId: 7,
            among: [res(1, "10:00", "11:00", assignee: 7, date: "2026-07-25")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testMultipleConflictsSortedByStart() {
        let hits = ReservationOverlap.conflicts(
            date: "2026-07-24", startTime: "09:30", endTime: "13:00", assigneeId: 7,
            among: [
                res(1, "12:00", "12:30", assignee: 7),
                res(2, "10:00", "11:00", assignee: 7),
                res(3, "11:00", "11:30", assignee: 7),
            ])
        XCTAssertEqual(hits.map(\.id), [2, 3, 1])   // 시작시간 순
    }
}
