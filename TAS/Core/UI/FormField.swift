import SwiftUI

/// 웹 formControl — 이름(13, 진회색) 위에 입력칸(높이 36, 1px 옅은 테두리, 6 둥글게).
/// 날짜·시간 고르기처럼 iOS 부품이 자기 모양을 가진 칸은 `bordered: false`로 이름만 붙인다.
/// 이름 없이 칸만 필요하면(결제 줄처럼) `label: nil` — 그때는 입력에 접근성 이름을 직접 붙인다.
struct FormField<Input: View>: View {
    let label: String?
    var bordered = true
    @ViewBuilder let input: Input

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label).font(.tasMedium).foregroundStyle(Color.textSecondary)
            }
            if bordered {
                input
                    .font(.tasBody)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderLine))
            } else {
                input.font(.tasBody)
            }
        }
    }
}

/// 웹 select처럼 칸 전체가 눌리고 값은 왼쪽, 화살표는 오른쪽 — 고르는 목록은 iOS 메뉴.
/// `FormField` 안에 넣어 테두리를 받는다.
struct SelectMenu<Picker: View>: View {
    let title: String
    let value: String
    @ViewBuilder let picker: Picker

    var body: some View {
        Menu {
            picker
        } label: {
            HStack {
                Text(value).foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
