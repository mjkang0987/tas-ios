import Foundation

/// 공지 분류 — notices/model.ts `NoticeCategory`.
enum NoticeCategory: String, Codable, Hashable, CaseIterable {
    case notice, event, info

    var label: String {
        switch self {
        case .notice: return "공지"
        case .event: return "이벤트"
        case .info: return "안내"
        }
    }
}

/// 매장 공지 — notices/model.ts `StoreNotice`(공개 예약 페이지 노출).
struct StoreNotice: Codable, Identifiable, Hashable {
    var id: String
    var category: NoticeCategory
    var title: String
    var body: String
    var visible: Bool
    var pinned: Bool
    var createdAt: String   // ISO8601

    /// 고정 공지 최대 수 — notices/model.ts `MAX_PINNED_NOTICES`.
    static let maxPinned = 3
}

/// GET /api/notices 응답.
struct NoticesResponse: Codable {
    var notices: [StoreNotice]
}
