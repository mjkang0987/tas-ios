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
