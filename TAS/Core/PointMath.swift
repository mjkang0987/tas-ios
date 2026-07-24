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
