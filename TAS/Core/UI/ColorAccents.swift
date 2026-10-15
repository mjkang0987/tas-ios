import SwiftUI

/// 색 점(담당자/카테고리 색 표시). 공용 재사용.
struct ColorDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 좌측 색 액센트 바(예약 카드·서비스 행의 담당자/카테고리 색).
struct ColorAccentBar: View {
    let color: Color?
    var width: CGFloat = 3
    var height: CGFloat = 30

    var body: some View {
        if let color {
            Capsule().fill(color).frame(width: width, height: height)
        }
    }
}

/// 취소·노쇼 카드의 빗금 — 웹 `repeating-linear-gradient(-45deg, …)` 대응.
/// 색만 흐리게 하면 "조금 덜 중요한 예약"으로 읽혀, 끝난 건임을 무늬로 못박는다.
struct HatchPattern: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 12
            let span = geo.size.width + geo.size.height
            Path { path in
                var x = -geo.size.height
                while x < span {
                    path.move(to: CGPoint(x: x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Color.primary.opacity(0.05), lineWidth: 6)
        }
    }
}

/// 타임라인 블록의 겉모양 — 안쪽 여백·세로 정렬·바탕·빗금·담당자 색 띠·모서리.
///
/// 일 뷰와 주·3일 뷰는 블록 **안에 담는 내용**이 정당하게 다르다(일 뷰는 시간·이름·시술칩,
/// 좁은 칼럼은 이름만). 그런데 겉모양까지 각자 들고 있었더니 한쪽만 고쳐지는 일이 반복됐다
/// — 빗금이 일 뷰에만 들어갔고, 프레임을 패딩보다 먼저 잡아 블록이 제 칸보다 커지는 버그는
/// 주·3일에만 있었고, 여백 값도 갈렸다. 겉모양은 한 벌로 둔다.
struct TimelineBlockChrome: ViewModifier {
    let color: Color
    let isInactive: Bool
    let width: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            // 왼쪽 3pt 는 담당자 색 띠가 덮는다 — 그만큼 더 밀지 않으면 글자가 띠에 붙는다.
            .padding(.leading, 3)
            // 패딩이 프레임보다 먼저여야 한다. 순서가 뒤집히면 패딩이 칸 **밖에** 붙어
            // 블록이 제 레인보다 커지고 옆 레인을 침범한다.
            .frame(width: width, height: height,
                   alignment: height <= TimelineLayout.centerContentMaxHeight ? .leading : .topLeading)
            .background {
                ZStack {
                    color.opacity(0.16)
                    if isInactive { HatchPattern() }
                }
            }
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

extension View {
    func timelineBlockChrome(color: Color, isInactive: Bool, width: CGFloat, height: CGFloat) -> some View {
        modifier(TimelineBlockChrome(color: color, isInactive: isInactive, width: width, height: height))
    }
}
