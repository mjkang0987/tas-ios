import Foundation

/// 요일별 근무 스케줄 — assignees/model.ts `DaySchedule`
/// 배열 순서: 월,화,수,목,금,토,일 (WEEKDAY_LABELS)
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
}

/// GET /api/assignees response envelope.
struct AssigneesResponse: Codable {
    var assignees: [Assignee]
}
