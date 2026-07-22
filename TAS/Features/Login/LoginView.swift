import SwiftUI

/// 소셜 로그인 진입 화면 — GUIDE.md §1 (Google / Kakao / Naver).
///
/// 백엔드가 쿠키(JWT) 세션이라, 실제 로그인은 웹 `/login`을 WKWebView로 띄워
/// 진행하고(`WebAuthScreen`), 완료 후 세션 쿠키를 수확해 `URLSession`을 인증한다.
/// 웹 `/login` 페이지가 Google/Kakao/Naver 버튼을 렌더하므로 provider 선택은
/// 웹에서 이뤄진다(네이티브에서 provider별 CSRF POST를 재현하지 않기 위함).
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var showingWebAuth = false
    @State private var errorMessage: String?

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
                    showingWebAuth = true
                } label: {
                    Text("소셜 계정으로 로그인")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Text("Google · Kakao · Naver 지원")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("게스트로 둘러보기") {
                    // 게스트 모드는 웹에서 localStorage 기반. 앱 지원은 별도 과제(plan.md P3).
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingWebAuth) {
            WebAuthScreen(
                startURL: AppConfig.loginURL,
                onSuccess: {
                    showingWebAuth = false
                    Task { await session.didCompleteLogin() }
                },
                onCancel: { showingWebAuth = false },
                onError: { message in
                    showingWebAuth = false
                    errorMessage = message
                }
            )
        }
        .alert("로그인 오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
