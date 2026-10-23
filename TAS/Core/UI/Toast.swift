import SwiftUI

/// 토스트 — 웹 `toastStore`·안드로이드 `TasToast`: 위쪽 가운데에 3초, × 로 바로 닫기, 낭독기가 곧바로 읽는다(웹 role=alert).
/// 저장·삭제 결과처럼 "됐다"를 알리는 한 줄. 화면마다 `.toast($toast)` 로 붙인다(시트 위에도 그 시트에 붙이면 보인다).
struct Toast: Equatable, Identifiable {
    enum Kind { case success, error, info }
    let text: String
    var kind: Kind = .success
    let id = UUID()

    /// 웹·안드로이드 색 — 흰 글자 대비 4.5:1 이상.
    fileprivate var background: Color {
        switch kind {
        case .success: return Color(hex: "#1A7F3C") ?? .green
        case .error: return Color(hex: "#C5221F") ?? .red
        case .info: return Color(hex: "#1E293B") ?? .black
        }
    }

    fileprivate var icon: String {
        switch kind {
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        case .info: return "info.circle"
        }
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.icon).accessibilityHidden(true)
                    Text(toast.text).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Button { self.toast = nil } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("알림 닫기")
                }
                .foregroundStyle(.white)
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                .background(toast.background, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    AccessibilityNotification.Announcement(toast.text).post()
                    try? await Task.sleep(for: .seconds(3))
                    if self.toast?.id == toast.id { self.toast = nil }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastModifier(toast: toast)) }
}
