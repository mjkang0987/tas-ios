import SwiftUI

/// 웹 formControl — 이름(13, 진회색) 위에 입력칸(높이 36, 1px 옅은 테두리, 6 둥글게).
/// 날짜·시간 고르기처럼 iOS 부품이 자기 모양을 가진 칸은 `bordered: false`로 이름만 붙인다.
struct FormField<Input: View>: View {
    let label: String
    var bordered = true
    @ViewBuilder let input: Input

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.tasMedium).foregroundStyle(Color.textSecondary)
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
