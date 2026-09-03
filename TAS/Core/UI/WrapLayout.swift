import SwiftUI

/// 가로로 넘치면 다음 줄로 흐르는 배치 — 웹 `flex-wrap: wrap`.
///
/// 시술 칩(`ServiceChipList`)·고객 목록의 상태 카운트 배지·매치된 메모 태그가 함께 쓴다.
/// 셋 다 자식에 `lineLimit(1)`을 둬 한 줄에 밀어넣으면 내용이 잘린다 — 줄바꿈이 답이다.
struct WrapLayout: Layout {
    var spacing: CGFloat

    /// 줄바꿈 규칙은 여기 한 벌만 둔다. 측정(`sizeThatFits`)과 배치(`placeSubviews`)가
    /// 각자 계산하면 둘이 어긋나는 순간 마지막 줄이 잘리는데, 컴파일러는 잡아주지 않는다.
    ///
    /// 칸보다 긴 칩("남자 디자인펌" 같은 긴 시술명)은 폭을 잘라둔다 — 칩은 `lineLimit(1)`이라
    /// 스스로 줄이지 못하고, 잘린 폭을 제안으로 받아야 말줄임으로 접힌다.
    private func layout(_ subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, rects: [CGRect]) {
        var rects: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(ideal.width, maxWidth), height: ideal.height)

            if x > 0, x + size.width > maxWidth {
                totalWidth = max(totalWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rects.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        totalWidth = max(totalWidth, x - spacing)
        return (CGSize(width: max(0, totalWidth), height: y + rowHeight), rects)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, rect) in zip(subviews, layout(subviews, maxWidth: bounds.width).rects) {
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(rect.size)
            )
        }
    }
}
