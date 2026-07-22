import Foundation

/// 금액 표시 — 웹 `formatPrice`(toLocaleString('ko-KR') + '원')와 동일.
func formatWon(_ price: Int) -> String {
    price.formatted(.number.grouping(.automatic)) + "원"
}
