import SwiftUI

/// 시술(서비스) 배지 — 웹 `client/components/ui/ServiceChip.tsx` 이식.
///
/// 알약 칩: 배경은 서비스 색 9% 틴트(웹 `${color}18`), 글자는 서비스 색, 11pt semibold
/// (웹 `--xsmall-font: 11px` / `font-weight: 600`).
struct ServiceChip: View {
    let name: String
    let color: Color
    var font: Font = .caption2

    var body: some View {
        Text(name)
            .font(font.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.094), in: Capsule())
    }
}

/// 예약의 `service` 문자열("커트+펌")을 시술별 칩으로 나눠 보여준다.
/// 색 해석·문자열 분리는 전부 `ServiceColor`(웹 정의 이식)에 맡긴다.
struct ServiceChipList: View {
    /// 예약에 저장된 원문(`"커트+펌"`).
    let service: String
    /// 서비스명 → hex. `ServiceColor.buildServiceColorMap`이 만든 맵.
    let colorMap: [String: String]
    var font: Font = .caption2
    /// 목록 행처럼 높이가 흔들리면 안 되는 자리는 `false`(한 줄, 넘치면 잘림).
    /// 웹도 목록에선 `nowrap` + ellipsis를 쓴다.
    var wraps: Bool = true

    /// 같은 시술이 두 번 들어간 문자열("커트+커트")도 있을 수 있어 순번으로 식별한다.
    private struct Item: Identifiable {
        let id: Int
        let name: String
    }

    private var items: [Item] {
        ServiceColor.parseServiceString(service, knownNames: Set(colorMap.keys))
            .enumerated()
            .map { Item(id: $0.offset, name: $0.element) }
    }

    var body: some View {
        if wraps {
            ChipFlow(spacing: 6) { chips }
        } else {
            HStack(spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items) { item in
            ServiceChip(
                name: item.name,
                color: ServiceColor.color(item.name, in: colorMap),
                font: font
            )
        }
    }
}

/// 가로로 넘치면 다음 줄로 흐르는 배치 — 웹 `flex-wrap: wrap`.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    private func clamped(_ size: CGSize, to maxWidth: CGFloat) -> CGSize {
        CGSize(width: min(size.width, maxWidth), height: size.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var total = CGSize.zero
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            // 이상적 폭을 그대로 쓰면 칸보다 긴 칩("남자 디자인펌" 같은 긴 시술명)이
            // 밖으로 삐져나간다. 칩은 lineLimit(1)이라 스스로 줄이지 못하므로 여기서 자른다.
            let size = clamped(subview.sizeThatFits(.unspecified), to: maxWidth)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = clamped(subview.sizeThatFits(.unspecified), to: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            // 잘린 폭을 제안으로 넘겨야 Text가 말줄임으로 접힌다.
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
