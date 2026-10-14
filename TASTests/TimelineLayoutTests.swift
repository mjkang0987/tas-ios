import XCTest
@testable import TAS

/// 겹친 예약의 레인 배치(`TimelineLayout`) — 일·주 타임라인 공용.
///
/// 주 뷰는 이 결과로 **칼럼 폭**까지 정한다(`maxLanes` × 레인폭). 레인 수가 틀리면
/// 칸이 좁아 블록이 겹쳐 그려지거나, 쓸데없이 넓어져 가로 스크롤이 길어진다.
final class TimelineLayoutTests: XCTestCase {

    private func res(_ id: Int, _ start: String, _ end: String) -> Reservation {
        Reservation(id: id, date: "2026-10-08", startTime: start, endTime: end,
                    service: "컷", customerId: 1, assigneeId: 1, status: .active)
    }

    func testNoOverlapUsesOneLane() {
        let placed = TimelineLayout.place([res(1, "10:00", "11:00"), res(2, "11:00", "12:00")])
        XCTAssertEqual(placed.count, 2)
        XCTAssertTrue(placed.allSatisfy { $0.laneCount == 1 && $0.laneIndex == 0 })
        XCTAssertEqual(TimelineLayout.maxLanes(placed), 1)
    }

    /// 경계만 맞닿는 건 겹침이 아니다(`ReservationOverlap.intervalsOverlap`과 같은 규칙).
    func testTouchingEdgesAreNotOverlap() {
        let placed = TimelineLayout.place([res(1, "10:00", "11:00"), res(2, "11:00", "12:00")])
        XCTAssertEqual(TimelineLayout.maxLanes(placed), 1)
    }

    func testOverlapGetsSeparateLanes() {
        let placed = TimelineLayout.place([res(1, "10:00", "11:00"), res(2, "10:30", "11:30")])
        XCTAssertEqual(Set(placed.map(\.laneIndex)), [0, 1])
        XCTAssertEqual(TimelineLayout.maxLanes(placed), 2)
    }

    /// A-B, B-C 가 겹치면 A-C 가 안 겹쳐도 **한 묶음**이다 — 묶음이 쪼개지면 레인 번호가
    /// 묶음마다 0부터 다시 매겨져 B 옆자리가 비거나 겹쳐 그려진다.
    /// 한 묶음이라도 A가 끝난 뒤 시작하는 C는 A의 레인을 물려받으므로 레인은 2개다.
    func testTransitiveChainSharesOneCluster() {
        let placed = TimelineLayout.place([
            res(1, "10:00", "11:00"),
            res(2, "10:30", "11:30"),
            res(3, "11:10", "12:00"),   // A와는 안 겹치고 B와만 겹친다
        ])
        // 셋이 같은 묶음이면 laneCount 가 전부 같다. 쪼개졌다면 1과 2가 섞인다.
        XCTAssertEqual(Set(placed.map(\.laneCount)), [2])
        XCTAssertEqual(TimelineLayout.maxLanes(placed), 2)

        let lane = Dictionary(uniqueKeysWithValues: placed.map { ($0.reservation.id, $0.laneIndex) })
        XCTAssertEqual(lane[1], lane[3])
        XCTAssertNotEqual(lane[1], lane[2])
    }

    /// 끝난 레인은 다시 쓴다 — 하루 종일 겹치지 않는 한 칼럼이 무한정 넓어지지 않는다.
    func testFinishedLaneIsReused() {
        let placed = TimelineLayout.place([
            res(1, "10:00", "12:00"),
            res(2, "10:00", "10:30"),
            res(3, "10:30", "11:00"),   // 2번이 쓰던 레인을 물려받는다
        ])
        XCTAssertEqual(TimelineLayout.maxLanes(placed), 2)
        let byId = Dictionary(uniqueKeysWithValues: placed.map { ($0.reservation.id, $0.laneIndex) })
        XCTAssertEqual(byId[2], byId[3])
    }

    func testBrokenOrInvertedTimesAreDropped() {
        let placed = TimelineLayout.place([
            res(1, "", "11:00"),
            res(2, "12:00", "11:00"),
            res(3, "10:00", "10:00"),
            res(4, "10:00", "11:00"),
        ])
        XCTAssertEqual(placed.map(\.reservation.id), [4])
    }

    func testEmptyInput() {
        XCTAssertTrue(TimelineLayout.place([]).isEmpty)
        XCTAssertEqual(TimelineLayout.maxLanes([]), 1)
    }
}
