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
///
/// 취소와 노쇼는 **색**으로 가른다 — 취소는 무채색, 노쇼는 붉은 기운(매출이 빈 자리라
/// 눈에 걸려야 한다). 무늬를 교차로 바꾸는 방식도 써 봤으나 나란히 두지 않으면
/// 구별이 어렵고 촘촘해져 글자를 가렸다.
struct HatchPattern: View {
    /// 노쇼면 붉게. 상태 배지의 노쇼 색(#EA4335)과 같은 계열이다.
    var noshow: Bool = false

    private var tint: Color {
        noshow ? BadgeTone.noshow.foreground.opacity(0.18) : Color.primary.opacity(0.05)
    }

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
            .stroke(tint, lineWidth: 6)
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
    /// 노쇼만 교차 빗금 — 취소와 가르기 위해. `isInactive` 와 함께 켠다.
    var isNoshow: Bool = false
    /// 확정대기(아직 수락 전인 온라인 신청) — 카드를 그대로 두고 그 위를 덮는다.
    var isPending: Bool = false
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
            // 확정대기는 배지가 아래를 차지하므로 내용을 위에 붙인다 — 가운데로 두면 좁은 칸에서
            // 배지가 이름을 그대로 덮어, 정작 "누가" 가 사라진다.
            .frame(width: width, height: height,
                   alignment: !isPending && height <= TimelineLayout.centerContentMaxHeight
                       ? .leading : .topLeading)
            .background {
                ZStack {
                    color.opacity(0.16)
                    if isInactive { HatchPattern(noshow: isNoshow) }
                }
            }
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            // 확정대기는 "있지만 아직 정해지지 않았다". 눌러서 상세에서 수락·거절해야 하므로
            // 딤도 배지도 터치를 먹지 않는다(`allowsHitTesting(false)`).
            .overlay {
                if isPending {
                    ZStack {
                        Color(.systemBackground).opacity(0.72)
                        // 아주 짧은 블록에는 배지가 안 들어간다 — 딤만 남긴다.
                        // 세로 가운데에 둔다. 내용은 위에 붙여 두므로(아래 frame alignment)
                        // 짧은 블록에서도 이름과 겹치지 않는다.
                        if height >= 34 {
                            // 집에 있는 배지 부품을 쓴다 — 혼자 진한 배경 + 흰 글자로 만들었더니
                            // 다른 배지(연한 배경 + 진한 글자)들 사이에서 겉돌았다.
                            ToneBadge(tone: .requested, text: "확정대기")
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

extension View {
    func timelineBlockChrome(color: Color, isInactive: Bool, isNoshow: Bool, isPending: Bool,
                             width: CGFloat, height: CGFloat) -> some View {
        modifier(TimelineBlockChrome(color: color, isInactive: isInactive, isNoshow: isNoshow,
                                     isPending: isPending, width: width, height: height))
    }
}
