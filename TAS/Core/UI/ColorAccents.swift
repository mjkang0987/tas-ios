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
