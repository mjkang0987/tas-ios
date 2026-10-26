import SwiftUI

/// 메모 태그 편집 — 웹 `AddressCustomerTags`(편집)·`CustomerMemoTagSection` 이식. 고객 수정 폼·고객 명단 펼친 행이 같이 쓴다.
/// 웹 차례: 입력 + '추가'(엔터도 추가) [+ '완료'] → 색 8개 → 태그(누르면 삭제).
struct MemoTagEditor: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let tags: [CustomerMemoTag]
    @Binding var text: String
    @Binding var color: String
    var error: String? = nil
    let onAdd: () -> Void
    let onRemove: (CustomerMemoTag) -> Void
    /// 명단 행처럼 편집을 닫는 자리가 따로 있으면 '완료'를 단다(폼은 저장 버튼이 닫는다).
    var onDone: (() -> Void)? = nil

    /// 웹 `MEMO_TAG_COLORS` — 이름은 낭독기용(안드로이드와 같다).
    static let colors: [(hex: String, name: String)] = [
        ("#4285F4", "파랑"), ("#34A853", "초록"), ("#EA4335", "빨강"), ("#FBBC04", "노랑"),
        ("#FF6D01", "주황"), ("#46BDC6", "청록"), ("#9334E6", "보라"), ("#E91E8C", "분홍"),
    ]

    /// 웹 addTag — 앞뒤 공백을 빼고 비었으면 그대로, 같은 글자 태그가 있으면 오류, 아니면 끝에 붙인다.
    static func adding(_ text: String, color: String, to tags: [CustomerMemoTag]) -> (tags: [CustomerMemoTag], error: String?) {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return (tags, nil) }
        if tags.contains(where: { $0.text == value }) { return (tags, "같은 메모 태그가 이미 있습니다.") }
        return (tags + [CustomerMemoTag(text: value, color: color)], nil)
    }

    var body: some View {
        // 큰 글자에서는 버튼이 입력칸을 눌러 글자가 안 보인다 — 입력칸 한 줄, 버튼은 그 아래로
        let inputRow = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
        VStack(alignment: .leading, spacing: 10) {
            inputRow {
                FormField(label: nil) {
                    TextField("메모 태그 입력", text: $text)
                        .submitLabel(.done)
                        .onSubmit(onAdd)
                        .accessibilityLabel("메모 태그 입력")
                }
                Button("추가", action: onAdd)
                    .buttonStyle(.action(.primary))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                if let onDone {
                    Button("완료", action: onDone).buttonStyle(.action())
                }
            }

            HStack(spacing: 2) {
                ForEach(Self.colors, id: \.hex) { option in
                    Button { color = option.hex } label: {
                        Circle()
                            .fill(Color(hex: option.hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay { if option.hex == color { Circle().strokeBorder(.primary, lineWidth: 2) } }
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("태그 색 \(option.name)")
                    .accessibilityAddTraits(option.hex == color ? .isSelected : [])
                }
            }

            if !tags.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { item in
                        removableTag(item.element)
                    }
                }
            }

            if let error {
                Text(error).font(.tasMedium).foregroundStyle(Color.dangerText)
            }
        }
    }

    /// 태그 알약 + ✕ — 알약 전체가 삭제 버튼(작은 ✕만 누르게 하면 손가락에 너무 작다).
    private func removableTag(_ tag: CustomerMemoTag) -> some View {
        Button { onRemove(tag) } label: {
            HStack(spacing: 4) {
                Text(tag.text).lineLimit(1)
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background((Color(hex: tag.color) ?? .secondary).forWhiteText, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.text) 태그 삭제")
    }
}
