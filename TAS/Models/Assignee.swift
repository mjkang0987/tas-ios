import Foundation

/// 요일별 근무 스케줄 — assignees/model.ts `DaySchedule`
/// 배열 순서: 월,화,수,목,금,토,일 (`KST.weekdayLabels`)
struct DaySchedule: Codable, Hashable {
    var enabled: Bool
    var start: String   // "HH:mm"
    var end: String     // "HH:mm"
}

/// 담당자(디자이너/스태프) — assignees/model.ts `Assignee`
struct Assignee: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var nameI18n: NameI18n?
    var schedule: [DaySchedule]
    var status: AssigneeStatus?
    var phone: String?
    var note: String?
    var color: String?

    /// summarizeSchedule(schedule) — assignees/model.ts
    var scheduleSummary: [ScheduleSummarySegment] { DaySchedule.summarize(schedule) }
}

/// 근무시간 요약의 한 구간 — assignees/model.ts `ScheduleSummarySegment`
struct ScheduleSummarySegment: Hashable {
    /// "월" 또는 "월~금"
    let days: String
    /// "10:00~20:00" 또는 "휴무"
    let hours: String
}

extension DaySchedule {
    /// summarizeSchedule(schedule) — assignees/model.ts
    /// 요일 7행을 같은 근무시간끼리 묶어 요약한다. 예: 월~금 10:00~20:00 · 토 10:00~18:00 · 일 휴무
    ///
    /// 7일치가 안 되는 스케줄은 모자란 요일을 휴무로 채운다(웹은 `schedule[i]`가 undefined면 휴무 키).
    static func summarize(_ schedule: [DaySchedule]) -> [ScheduleSummarySegment] {
        let labels = KST.weekdayLabels
        var segments: [ScheduleSummarySegment] = []
        var segmentStart = 0

        for index in labels.indices {
            let isLast = index == labels.count - 1
            // 다음 요일과 근무시간이 같으면 아직 구간이 안 끝났다(마지막 요일은 무조건 닫는다).
            if !isLast, workingHours(schedule, at: index) == workingHours(schedule, at: index + 1) { continue }

            segments.append(ScheduleSummarySegment(
                days: segmentStart == index
                    ? labels[segmentStart]
                    : "\(labels[segmentStart])~\(labels[index])",
                hours: workingHours(schedule, at: segmentStart) ?? "휴무"))
            segmentStart = index + 1
        }

        return segments
    }

    /// 구간을 가르는 기준값. 휴무면 nil — 꺼둔 요일에 남아 있는 start/end가 구간을 쪼개지 않는다.
    private static func workingHours(_ schedule: [DaySchedule], at index: Int) -> String? {
        guard index < schedule.count, schedule[index].enabled else { return nil }
        return "\(schedule[index].start)~\(schedule[index].end)"
    }
}

/// GET /api/assignees response envelope.
struct AssigneesResponse: Codable {
    var assignees: [Assignee]
}
