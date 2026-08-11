import Foundation

/// 오너 확정 대기 항목의 종류 — `server/api/book-requests.ts` `kindOf()`
enum BookingRequestKind: String, Codable, Hashable {
    /// 신규 예약 신청(`status='requested'`) — 수락하면 예약 확정, 거절하면 취소.
    case new
    /// 변경 요청 — 수락하면 저장된 payload가 예약에 반영되고, 거절하면 요청만 사라진다.
    case change
    /// 취소 요청 — 수락하면 예약이 취소되고, 거절하면 예약이 그대로 유지된다.
    case cancel

    var label: String {
        switch self {
        case .new: return "신규 예약 신청"
        case .change: return "변경 요청"
        case .cancel: return "취소 요청"
        }
    }
}

/// 요청이 가리키는 예약 시간대 — `toRequestDto`의 `current`/`requestedChange`
struct BookingRequestSlot: Codable, Hashable {
    var date: String            // "YYYY-MM-DD"
    var startTime: String       // "HH:mm"
    var endTime: String         // "HH:mm"
    var serviceSummary: String
}

/// 온라인 예약 요청(오너 승인 대기) — `GET /api/book-requests`의 `requests[]`
///
/// 고객은 공개 예약 페이지(`book.takeaseat.co.kr/{slug}/r/{token}`)에서 변경·취소를 **요청**만 하고,
/// 서버는 이를 즉시 반영하지 않고 `pendingAction`으로 세워 둔다. 오너가 수락해야 예약에 반영된다.
struct BookingRequest: Codable, Identifiable, Hashable {
    /// 서버 cuid — 수락/거절(`POST`) 대상 지정에 쓴다.
    var id: String
    /// 앱·웹이 쓰는 정수 예약 id. 서버가 null을 줄 수 있어 옵셔널.
    var legacyId: Int?
    var kind: BookingRequestKind
    var customerName: String
    var assigneeName: String?
    var requestedAt: String?
    var current: BookingRequestSlot
    /// `kind == .change`일 때만 채워진다(고객이 요청한 새 시간대).
    var requestedChange: BookingRequestSlot?
}

/// GET /api/book-requests response envelope.
struct BookingRequestsResponse: Codable {
    var requests: [BookingRequest]
}

/// POST /api/book-requests의 `decision`.
enum BookingDecision: String, Codable {
    case approve
    case reject
}
