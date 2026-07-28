import Foundation

/// 적립금 이력 유형 — customers/model.ts `PointHistoryType`
enum PointHistoryType: String, Codable, Hashable {
    case manualAdd = "manual_add"
    case manualSubtract = "manual_subtract"
    case recharge
    case paymentUse = "payment_use"
    case paymentEarn = "payment_earn"
    case paymentAdjust = "payment_adjust"

    var label: String {
        switch self {
        case .manualAdd: return "수동 적립"
        case .manualSubtract: return "수동 차감"
        case .recharge: return "충전"
        case .paymentUse: return "결제 사용"
        case .paymentEarn: return "결제 적립"
        case .paymentAdjust: return "적립 조정"
        }
    }
}

/// 적립금 이력 항목 — customers/model.ts `PointHistoryEntry`
struct PointHistoryEntry: Codable, Identifiable, Hashable {
    var id: String
    var type: PointHistoryType
    var delta: Int
    var balance: Int
    var description: String
    var createdAt: String
    var relatedReservationId: Int?
}

/// 고객 메모 태그 — customers/model.ts `CustomerMemoTag`
struct CustomerMemoTag: Codable, Hashable {
    var text: String
    var color: String
}

/// 고객 — customers/model.ts `Customer`
struct Customer: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var tel: String
    var points: Int? = nil
    var firstVisitDate: String? = nil
    var pointHistories: [PointHistoryEntry]? = nil
    var memoTags: [CustomerMemoTag]? = nil
    // allergyNote·claimNote·preferenceNote는 웹에서 제거됐다(tas #168, 마이그레이션 0018로
    // 컬럼 드롭). 입력 UI 없이 표시만 하던 임포트 시절 레거시라 앱에서도 배선을 지운다.

    /// isNewCustomerVisit(firstVisitDate, date) — customers/model.ts
    /// 예약 날짜가 이 고객의 첫 방문일과 같으면 신규 방문.
    func isNewCustomerVisit(on reservationDate: String) -> Bool {
        guard let firstVisitDate, !firstVisitDate.isEmpty else { return false }
        return firstVisitDate == reservationDate
    }

    /// formatTel(tel) — customers/model.ts
    var formattedTel: String {
        let digits = tel.filter(\.isNumber)
        if digits.count == 11 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(4)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        }
        if digits.count == 10 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        }
        return tel
    }
}

/// GET /api/customers response envelope.
struct CustomersResponse: Codable {
    var customers: [Customer]
}
