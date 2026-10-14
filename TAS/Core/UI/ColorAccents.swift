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
