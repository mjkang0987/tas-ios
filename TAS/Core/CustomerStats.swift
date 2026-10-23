import Foundation

/// 고객별 예약 집계 — 웹 `address.tsx`의 `customerStats`·`AddressCustomerReservations`의
/// `getEffectiveStatus` 이식.
///
/// **핵심 규칙:** 상태가 없는 과거 예약은 `completed`로 친다. 웹은 예약을 끝내도 상태를
/// 바꾸지 않는 경우가 많아, 날짜가 지났으면 완료로 간주해야 화면 숫자가 맞는다.
/// 이 규칙이 없으면 지난 예약이 전부 '예약'으로 남아 카운트가 실제와 어긋난다.
enum CustomerStats {

    /// 화면에 실제로 보여줄 상태 — 저장된 status + 날짜로 결정.
    enum EffectiveStatus: String, CaseIterable {
        case booked, completed, cancelled, noshow

        /// 고객 요약 행의 배지 순서 — 웹 `AddressCustomerSummary`는 예약/취소/완료/노쇼다.
        /// 상세의 그룹 순서(`allCases`: 예약/완료/취소/노쇼)와 **다르다** — 웹이 실제로 그렇다.
        static let summaryOrder: [EffectiveStatus] = [.booked, .cancelled, .completed, .noshow]

        /// 웹 `STATUS_GROUPS`의 라벨.
        var label: String {
            switch self {
            case .booked: return "예약"
            case .completed: return "완료"
            case .cancelled: return "취소"
            case .noshow: return "노쇼"
            }
        }
    }

    /// 고객 한 명의 집계 — 웹 `CustomerStats`.
    struct Summary: Equatable {
        var recentService: String?   // 취소·노쇼 제외 최신 예약의 시술. 없으면 nil.
        var booked: Int
        var cancelled: Int
        var completed: Int
        var noshow: Int

        static let empty = Summary(recentService: nil, booked: 0, cancelled: 0, completed: 0, noshow: 0)

        func count(_ status: EffectiveStatus) -> Int {
            switch status {
            case .booked: return booked
            case .completed: return completed
            case .cancelled: return cancelled
            case .noshow: return noshow
            }
        }

        var total: Int { booked + cancelled + completed + noshow }
    }

    /// getEffectiveStatus(r, today) — 웹과 동일 순서로 판정한다(순서가 곧 우선순위).
    static func effectiveStatus(_ reservation: Reservation, today: String) -> EffectiveStatus {
        switch reservation.status {
        case .cancelled: return .cancelled
        case .noshow: return .noshow
        case .completed: return .completed
        default: return reservation.date < today ? .completed : .booked
        }
    }

    /// 고객 예약 목록 → 집계. `today`는 매장 기준(KST) "YYYY-MM-DD".
    static func summarize(_ reservations: [Reservation], today: String) -> Summary {
        var summary = Summary.empty
        for r in reservations {
            switch effectiveStatus(r, today: today) {
            case .booked: summary.booked += 1
            case .completed: summary.completed += 1
            case .cancelled: summary.cancelled += 1
            case .noshow: summary.noshow += 1
            }
        }
        summary.recentService = recentService(reservations)
        return summary
    }

    /// 취소·노쇼를 뺀 뒤 날짜·시작시간 내림차순 첫 건의 시술.
    static func recentService(_ reservations: [Reservation]) -> String? {
        reservations
            .filter { $0.status != .cancelled && $0.status != .noshow }
            .max { $0.precedes($1) }
            .map(\.service)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 미래 → 과거(날짜 내림, 시간 내림) — 웹 `sortFutureFirst`.
    static func sortedFutureFirst(_ reservations: [Reservation]) -> [Reservation] {
        reservations.sorted { $1.precedes($0) }
    }

    /// 상태별로 묶인 예약 묶음 — `ForEach`가 바로 쓰도록 Identifiable.
    /// (튜플 배열 + 키패스 id는 쓰지 않는다.)
    struct Group: Identifiable {
        let status: EffectiveStatus
        let items: [Reservation]
        var id: EffectiveStatus { status }
    }

    /// 예약을 상태별로 묶는다. 빈 그룹은 뺀다(웹 `nonEmptyGroups`).
    static func groups(_ reservations: [Reservation], today: String) -> [Group] {
        EffectiveStatus.allCases.compactMap { status in
            let items = reservations.filter { effectiveStatus($0, today: today) == status }
            return items.isEmpty ? nil : Group(status: status, items: sortedFutureFirst(items))
        }
    }

    /// 고객별로 묶어 한 번에 집계 — 목록 화면이 행마다 다시 훑지 않도록.
    static func byCustomer(_ reservationsByCustomer: [Int: [Reservation]], today: String) -> [Int: Summary] {
        reservationsByCustomer.mapValues { summarize($0, today: today) }
    }
}
