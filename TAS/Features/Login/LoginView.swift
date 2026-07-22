import SwiftUI

/// Social-login entry screen — GUIDE.md §1 (Google / Kakao / Naver / 게스트).
///
/// TODO: wire each button to `ASWebAuthenticationSession` opening
/// `\(AppConfig.apiBaseURL)/api/auth/signin/<provider>` and, on callback, call
/// `session.didCompleteLogin()`. For now the buttons are placeholders so the
/// skeleton builds and the navigation gate is demonstrable.
struct LoginView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "chair.lounge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("take a seat")
                    .font(.largeTitle.bold())
                Text("미용실 예약·고객·매출 관리")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                providerButton("Google 로 시작", provider: "google")
                providerButton("Kakao 로 시작", provider: "kakao")
                providerButton("Naver 로 시작", provider: "naver")

                Button("게스트로 둘러보기") {
                    // 게스트 모드는 웹에서 localStorage 기반. 여기서는 미구현 안내.
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    private func providerButton(_ title: String, provider: String) -> some View {
        Button {
            Task { await startLogin(provider: provider) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
    }

    private func startLogin(provider: String) async {
        // Placeholder: real implementation launches the OAuth web flow.
        // await WebAuth.start(provider: provider); await session.didCompleteLogin()
        _ = provider
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
