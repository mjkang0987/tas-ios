import SwiftUI

/// 연락처 — 누르면 전화 앱(웹 `tel:`·안드로이드 `ACTION_DIAL` 과 같은 링크). 번호가 없으면 글자만.
/// 예약 상세·고객 상세가 같이 쓴다.
struct TelLink: View {
    let customer: Customer

    var body: some View {
        let digits = customer.tel.filter(\.isNumber)
        if !digits.isEmpty, let url = URL(string: "tel:\(digits)") {
            Link(customer.formattedTel, destination: url)
                .accessibilityHint("전화 걸기")
        } else {
            Text(customer.formattedTel)
        }
    }
}
