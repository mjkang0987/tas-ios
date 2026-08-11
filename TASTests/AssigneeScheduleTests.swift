import XCTest
@testable import TAS

/// 근무시간 요약(`DaySchedule.summarize`) — 웹 `summarizeSchedule`(tas #183) 이식본 검증.
/// 웹 `client/features/assignees/model.test.ts`의 케이스를 그대로 옮겼다.
///
/// 이 요약이 틀리면 담당자 목록에 **없는 근무시간이 표시된다**(예전 구현이 그랬다 —
/// 근무 요일을 전부 잇고 첫 요일의 시간만 붙였다).
final class AssigneeScheduleTests: XCTestCase {

    private static let open = (start: "10:00", end: "20:00")

    /// 요일 7행을 만든다. 인덱스(0=월 … 6=일)로 지정한 요일만 덮어쓴다.
    private func schedule(_ overrides: [Int: DaySchedule] = [:]) -> [DaySchedule] {
        (0..<7).map { index in
            overrides[index] ?? DaySchedule(enabled: true, start: Self.open.start, end: Self.open.end)
        }
    }

    private func off(start: String = "10:00", end: String = "20:00") -> DaySchedule {
        DaySchedule(enabled: false, start: start, end: end)
    }

    private func pairs(_ segments: [ScheduleSummarySegment]) -> [[String]] {
        segments.map { [$0.days, $0.hours] }
    }

    // MARK: - 연속 요일 묶기

    func testAllSevenDaysIdenticalCollapseToOneSegment() {
        XCTAssertEqual(pairs(DaySchedule.summarize(schedule())), [["월~일", "10:00~20:00"]])
    }

    func testDefaultScheduleSummarizesToTwoSegments() {
        // 평일 근무·주말 휴무(ShopCatalog.defaultSchedule 기본형).
        let weekdaysOnly = schedule([5: off(), 6: off()])
        XCTAssertEqual(pairs(DaySchedule.summarize(weekdaysOnly)), [
            ["월~금", "10:00~20:00"],
            ["토~일", "휴무"],
        ])
    }

    func testLastWeekdayIsNotDropped() {
        // 일(6)만 다른 경우. 루프 끝에서 구간을 닫지 않으면 이 항목이 통째로 사라진다.
        XCTAssertEqual(pairs(DaySchedule.summarize(schedule([6: off()]))), [
            ["월~토", "10:00~20:00"],
            ["일", "휴무"],
        ])
    }

    func testSingleDaySegmentHasNoTilde() {
        XCTAssertEqual(pairs(DaySchedule.summarize(schedule([0: off()]))), [
            ["월", "휴무"],
            ["화~일", "10:00~20:00"],
        ])
    }

    func testSameHoursSplitByAGapAreNotMerged() {
        // 월·수 근무 / 화 휴무 — 월과 수를 한 구간으로 합치면 화요일 휴무가 가려진다.
        let monAndWed = schedule([1: off(), 3: off(), 4: off(), 5: off(), 6: off()])
        XCTAssertEqual(pairs(DaySchedule.summarize(monAndWed)), [
            ["월", "10:00~20:00"],
            ["화", "휴무"],
            ["수", "10:00~20:00"],
            ["목~일", "휴무"],
        ])
    }

    // MARK: - 구간을 가르는 기준

    func testDifferentHoursSplitSegments() {
        let shortWeekend = schedule([
            5: DaySchedule(enabled: true, start: "10:00", end: "18:00"),
            6: DaySchedule(enabled: true, start: "10:00", end: "18:00"),
        ])
        XCTAssertEqual(pairs(DaySchedule.summarize(shortWeekend)), [
            ["월~금", "10:00~20:00"],
            ["토~일", "10:00~18:00"],
        ])
    }

    func testLeftoverHoursOnOffDaysDoNotSplitSegments() {
        // 체크만 해제하면 start/end는 편집 화면의 값이 그대로 남는다.
        let weekendOff = schedule([5: off(start: "09:00", end: "13:00"), 6: off()])
        XCTAssertEqual(pairs(DaySchedule.summarize(weekendOff)), [
            ["월~금", "10:00~20:00"],
            ["토~일", "휴무"],
        ])
    }

    func testSameHoursButDifferentEnabledStillSplits() {
        XCTAssertEqual(DaySchedule.summarize(schedule([6: off()])).map(\.hours), ["10:00~20:00", "휴무"])
    }

    // MARK: - 스케줄이 온전하지 않을 때

    func testEmptyScheduleIsAllOff() {
        XCTAssertEqual(pairs(DaySchedule.summarize([])), [["월~일", "휴무"]])
    }

    func testShortScheduleFillsMissingDaysAsOff() {
        XCTAssertEqual(pairs(DaySchedule.summarize(Array(schedule().prefix(5)))), [
            ["월~금", "10:00~20:00"],
            ["토~일", "휴무"],
        ])
    }

    func testEveryInputCoversAllSevenWeekdays() {
        let cases: [[DaySchedule]] = [[], schedule(), schedule([5: off(), 6: off()]), schedule([2: off()])]
        for input in cases {
            let covered = DaySchedule.summarize(input).flatMap { segment -> [String] in
                let bounds = segment.days.components(separatedBy: "~")
                guard let from = KST.weekdayLabels.firstIndex(of: bounds[0]) else { return [] }
                let to = bounds.count > 1 ? (KST.weekdayLabels.firstIndex(of: bounds[1]) ?? from) : from
                return Array(KST.weekdayLabels[from...to])
            }
            XCTAssertEqual(covered, KST.weekdayLabels, "입력 \(input.count)일치가 7일을 모두 덮지 않았다")
        }
    }
}
