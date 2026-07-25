import Foundation

/// 적립금(포인트) 계산 — 결제 화면의 적립/사용 산식을 View에서 분리해 테스트 가능하게 둔다.
/// (웹 결제 로직과 동일: 적립금 결제분은 적립 기준액에서 제외.)
enum PointMath {
    /// 적립 기준액에 대한 적립액 = base × rate% (내림). rate ≤ 0이면 0.
    static func earnedAmount(base: Int, rate: Int) -> Int {
        rate > 0 ? (base * rate) / 100 : 0
    }

    /// 결제 항목 중 적립금(`.points`) 사용 합계.
    static func pointsUsed(in entries: [PaymentEntry]) -> Int {
        entries.filter { $0.method == .points }.map(\.amount).reduce(0, +)
    }

    /// 적립 기준액 = 적립금 결제분을 제외한 결제 합계.
    static func nonPointTotal(in entries: [PaymentEntry]) -> Int {
        entries.filter { $0.method != .points }.map(\.amount).reduce(0, +)
    }
}

/// 결제에 따른 고객 적립금 잔액·이력 계산(순수). id/timestamp는 호출부가 부여한다.
/// 기존 적립·사용분 대비 **차액만** 반영해 재저장(수정) 시에도 정확하다.
enum PointLedger {
    /// 잔액에 반영할 변화 한 건(사용 또는 적립).
    struct Change: Equatable {
        let type: PointHistoryType
        let delta: Int          // 잔액 증감(사용은 음수, 적립은 양수)
        let balanceAfter: Int   // 이 변화 적용 후 잔액
        let description: String
    }

    /// 사용(차감)을 먼저, 그다음 적립을 반영한 새 잔액과 변화 목록을 돌려준다.
    /// 잔액은 0 미만으로 내려가지 않는다.
    static func changes(currentBalance: Int,
                        previousEarned: Int, newEarned: Int,
                        previousUsed: Int, newUsed: Int) -> (balance: Int, changes: [Change]) {
        var balance = currentBalance
        var out: [Change] = []

        let useDelta = newUsed - previousUsed        // >0: 추가 사용, <0: 사용 취소(환원)
        if useDelta != 0 {
            balance = max(0, balance - useDelta)
            out.append(Change(type: .paymentUse, delta: -useDelta, balanceAfter: balance,
                              description: useDelta > 0 ? "예약 결제 사용" : "예약 결제 사용 취소"))
        }

        let earnDelta = newEarned - previousEarned
        if earnDelta != 0 {
            balance = max(0, balance + earnDelta)
            out.append(Change(type: .paymentEarn, delta: earnDelta, balanceAfter: balance,
                              description: earnDelta > 0 ? "예약 결제 적립" : "예약 결제 적립 조정"))
        }

        return (balance, out)
    }

    /// 계산된 변화를 고객에 적용해 갱신된 `Customer`를 돌려준다(변화 없으면 nil).
    /// 이력 항목의 id/시각은 순수성 유지를 위해 호출부가 주입한다.
    static func apply(to customer: Customer,
                      previousEarned: Int, newEarned: Int,
                      previousUsed: Int, newUsed: Int,
                      reservationId: Int, now: String, makeId: () -> String) -> Customer? {
        let result = changes(currentBalance: customer.points ?? 0,
                             previousEarned: previousEarned, newEarned: newEarned,
                             previousUsed: previousUsed, newUsed: newUsed)
        guard !result.changes.isEmpty else { return nil }
        var updated = customer
        var histories = updated.pointHistories ?? []
        for change in result.changes {
            histories.insert(PointHistoryEntry(
                id: makeId(), type: change.type, delta: change.delta, balance: change.balanceAfter,
                description: change.description, createdAt: now, relatedReservationId: reservationId), at: 0)
        }
        updated.points = result.balance
        updated.pointHistories = histories
        return updated
    }
}
