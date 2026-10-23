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

    /// 웹 `pointRefundOnCancel` — 결제한 예약을 취소·삭제할 때 고객 적립금에 더할 값
    /// (결제에 쓴 적립금 반환 − 그 결제로 준 적립 회수). 이미 취소됐거나 결제 전이면 0.
    static func refundOnCancel(_ reservation: Reservation) -> Int {
        guard reservation.status != .cancelled, reservation.hasCompletedPayment else { return 0 }
        return pointsUsed(in: reservation.paymentEntries ?? []) - (reservation.pointEarned ?? 0)
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

    /// 취소·삭제 환원(`PointMath.refundOnCancel`)을 고객에 적용 — 웹 `refundPointsOnCancel`.
    /// 잔액은 0 아래로 안 내려가고, 이력 잔액은 (이전 잔액 + 변화) 그대로 적는다(웹과 같다).
    static func refund(_ customer: Customer, delta: Int, reservationId: Int, now: String, id: String) -> Customer {
        let balance = (customer.points ?? 0) + delta
        var updated = customer
        updated.points = max(balance, 0)
        updated.pointHistories = (customer.pointHistories ?? []) + [PointHistoryEntry(
            id: id, type: .paymentAdjust, delta: delta, balance: balance,
            description: delta > 0 ? "예약 취소 — 결제에 쓴 적립금 반환" : "예약 취소 — 결제 적립금 회수",
            createdAt: now, relatedReservationId: reservationId)]
        return updated
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
            histories.append(PointHistoryEntry(
                id: makeId(), type: change.type, delta: change.delta, balance: change.balanceAfter,
                description: change.description, createdAt: now, relatedReservationId: reservationId))
        }
        updated.points = result.balance
        updated.pointHistories = histories
        return updated
    }
}

/// 적립금 충전(순수) — 웹 `AddressCustomerRecharge` handleCharge. 충전 화면과 고객 명단 펼친 행이 같이 쓴다.
/// 규칙을 고르면 기준금액 + 보너스가 적립되고 받은 돈은 기준금액, 직접 입력이면 둘 다 친 금액.
enum PointRecharge {
    /// 적립할 금액 — `rule` 이 nil 이면 직접 입력(음수는 0).
    static func amount(rule: RechargeRule?, custom: Int) -> Int {
        rule.map { $0.baseAmount + $0.bonusAmount } ?? max(0, custom)
    }

    /// 받은 돈(매출로 잡힌다) — 규칙이면 기준금액(보너스 제외), 직접 입력이면 충전액.
    static func paid(rule: RechargeRule?, custom: Int) -> Int {
        rule?.baseAmount ?? amount(rule: nil, custom: custom)
    }

    /// 충전을 반영한 고객 — 충전액이 0 이하면 nil(웹은 아무것도 안 한다). 이력은 웹처럼 끝에 붙인다.
    static func charged(_ customer: Customer, rule: RechargeRule?, custom: Int, method: PaymentMethod,
                        now: String, id: String) -> Customer? {
        let amount = amount(rule: rule, custom: custom)
        guard amount > 0 else { return nil }
        let balance = (customer.points ?? 0) + amount
        var updated = customer
        updated.points = balance
        updated.pointHistories = (customer.pointHistories ?? []) + [PointHistoryEntry(
            id: id, type: .recharge, delta: amount, balance: balance,
            description: rule == nil ? "적립금 직접 충전" : "적립금 기준 충전",
            createdAt: now, relatedReservationId: nil,
            paidAmount: paid(rule: rule, custom: custom), paymentMethod: method)]
        return updated
    }
}

/// 수동 적립·차감(순수) — 웹 고객 상세 수동 조정·안드로이드 `adjustPoints`. 적립금 관리 '적립' 탭과 조정 화면이 같이 쓴다.
/// 차감은 잔액까지만(0 아래로 안 간다). 금액이 0 이하이거나 바뀔 게 없으면 nil. 이력은 웹처럼 끝에 붙인다.
enum PointAdjust {
    static func adjusted(_ customer: Customer, amount: Int, add: Bool, reason: String = "",
                         now: String, id: String) -> Customer? {
        guard amount > 0 else { return nil }
        let current = customer.points ?? 0
        let delta = add ? amount : -min(amount, current)
        guard delta != 0 else { return nil }
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        var updated = customer
        updated.points = current + delta
        updated.pointHistories = (customer.pointHistories ?? []) + [PointHistoryEntry(
            id: id, type: add ? .manualAdd : .manualSubtract, delta: delta, balance: current + delta,
            description: trimmed.isEmpty ? (add ? "수동 적립" : "수동 차감") : trimmed,
            createdAt: now, relatedReservationId: nil)]
        return updated
    }
}
