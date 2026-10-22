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
    /// '노출' — 고객 예약 페이지에 표시(최대 `maxVisible`).
    var visible: Bool
    /// 웹·앱 모두 더 이상 쓰지 않는다(옛 '상단 고정'). 서버가 계속 돌려주므로 디코드 호환용으로만 두고,
    /// 저장 때는 받은 값을 그대로 돌려보낸다.
    var pinned: Bool
    var createdAt: String   // ISO8601

    /// 노출 공지 최대 수 — notices/model.ts `MAX_VISIBLE_NOTICES`.
    static let maxVisible = 3

    /// '노출'을 켤 수 있는지 — 서버 409 `visible_limit` 과 같은 규칙.
    /// 한도는 숨김 → 노출 전환 때만 본다(이미 노출 중이던 공지는 한도 도입 전 초과분이어도 수정 가능).
    /// - Parameter otherVisibleCount: 이 공지를 뺀 노출 공지 수.
    static func canShow(wasVisible: Bool, otherVisibleCount: Int) -> Bool {
        wasVisible || otherVisibleCount < maxVisible
    }
}

/// GET /api/notices 응답.
struct NoticesResponse: Codable {
    var notices: [StoreNotice]
}
