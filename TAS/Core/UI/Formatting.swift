import Foundation
import SwiftUI

/// 금액 표시 — 웹 `formatPrice`(toLocaleString('ko-KR') + '원')와 동일.
func formatWon(_ price: Int) -> String {
    price.formatted(.number.grouping(.automatic)) + "원"
}

/// 검색어가 걸린 구간만 강조한 Text — 웹 `HighlightMatch` 이식. 사용처가 `CustomerRow` 한 곳뿐이라
/// 별도 View 컴포넌트가 아니라 `formatWon`과 같은 자리의 순수 헬퍼로 둔다.
func highlightedText(_ text: String, range: Range<String.Index>?) -> Text {
    var attributed = AttributedString(text)
    guard let range,
          let start = AttributedString.Index(range.lowerBound, within: attributed),
          let end = AttributedString.Index(range.upperBound, within: attributed) else {
        return Text(attributed)
    }
    attributed[start..<end].backgroundColor = .yellow.opacity(0.35)
    return Text(attributed)
}
