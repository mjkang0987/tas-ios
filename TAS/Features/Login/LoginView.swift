import SwiftUI

/// 소셜 로그인 진입 화면 — GUIDE.md §1 (Google / Kakao / Naver).
///
/// clipnote-ios처럼 `ASWebAuthenticationSession`(진짜 Safari)으로 웹 `/login`을 열어
/// 로그인하고, `tasios://auth/callback?code=`를 받아 Bearer 토큰으로 교환한다
/// (`SessionStore.signIn`). Safari 컨텍스트라 Google OAuth도 정상 동작한다.
/// provider 선택은 웹 `/login` 페이지에서 이뤄진다.
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var isAuthenticating = false

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
                Button {
                    Task {
                        isAuthenticating = true
                        await session.signIn()
                        isAuthenticating = false
                    }
                } label: {
                    Group {
                        if isAuthenticating {
                            ProgressView()
                        } else {
                            Text("소셜 계정으로 로그인")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)

                Text("Google · Kakao · Naver 지원")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .alert("로그인 오류", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("확인", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
