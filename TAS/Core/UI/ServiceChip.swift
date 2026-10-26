import SwiftUI

/// 시술(서비스) 배지 — 웹 `client/components/ui/ServiceChip.tsx` 이식.
///
/// 알약 칩: 배경은 서비스 색 9% 틴트(웹 `${color}18`), 글자는 서비스 색, 11pt semibold
/// (웹 `--xsmall-font: 11px` / `font-weight: 600`).
struct ServiceChip: View {
    let name: String
    let color: Color
    var font: Font = .caption2
    /// 끝난 예약(취소·노쇼)의 칩. 카드가 색을 잃는데 칩만 살아 있으면 거기로 눈이 간다
    /// — 웹도 같은 이유로 칩 글자를 죽인다.
    var inactive: Bool = false

    private var tint: Color { inactive ? .textTertiary : color }

    var body: some View {
        Text(name)
            .font(font.weight(.semibold))
            // 어두운 화면에서는 같은 색을 밝혀 읽히게(`Theme.swift` tintText·tintFill)
            .foregroundStyle(tint.tintText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.tintFill, in: Capsule())
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
    /// 끝난 예약이면 칩도 함께 죽인다.
    var inactive: Bool = false

    /// 같은 시술이 두 번 들어간 문자열("커트+커트")도 있을 수 있어 순번으로 식별한다.
    private struct Item: Identifiable {
        let id: Int
        let name: String
    }

    private var items: [Item] {
        // 목록 행마다 body가 재평가되는 자리다. '+'가 없으면 parseServiceString이
        // knownNames를 보기도 전에 반환하므로, 그 경우엔 Set을 짓지 않는다.
        let names = service.contains("+")
            ? ServiceColor.parseServiceString(service, knownNames: Set(colorMap.keys))
            : ServiceColor.parseServiceString(service)
        return names.enumerated().map { Item(id: $0.offset, name: $0.element) }
    }

    var body: some View {
        if wraps {
            WrapLayout(spacing: 6) { chips }
        } else {
            // 좁은 칸에서 HStack 은 칩들을 고르게 눌러 `여성…` `일…` 처럼 **둘 다** 읽을 수
            // 없게 만든다. 제 크기를 지키게 두고 넘치는 쪽을 자르면, 적어도 첫 칩은 온전히
            // 읽힌다(자르는 건 블록이 clipShape 로 한다).
            // minWidth 0 이 없으면 틀이 칩 줄 폭보다 좁아지지 못해, 큰 글자에서 예약 행과
            // 그 위 화면(고객 상세) 전체가 화면 밖으로 밀렸다 — 칸 폭에 맞추고 넘치는 칩은 여기서 자른다.
            HStack(spacing: 6) { chips }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
    }

    private var chips: some View {
        ForEach(items) { item in
            ServiceChip(
                name: item.name,
                color: ServiceColor.color(item.name, in: colorMap),
                font: font,
                inactive: inactive
            )
        }
    }
}
