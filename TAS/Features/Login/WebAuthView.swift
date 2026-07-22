import SwiftUI
import WebKit

/// WKWebView 기반 로그인 뷰.
///
/// 백엔드는 NextAuth v5(JWT 세션 전략)라 로그인 성공 시 도메인에
/// `__Secure-authjs.session-token` 쿠키가 심긴다. 네이티브 앱은 이 쿠키를
/// `HTTPCookieStorage.shared`로 옮겨야 `URLSession`(=`APIClient`) 요청이
/// 인증된다. 그래서 웹 `/login`을 WKWebView로 띄우고, 로그인 완료 후
/// 세션 쿠키를 수확(harvest)한다.
///
/// ⚠️ 한계: Google OAuth는 임베디드 웹뷰(WKWebView)를 공식적으로 막는다
/// ("disallowed_useragent"). Kakao/Naver는 일반적으로 동작한다. Google까지
/// 안정적으로 지원하려면 백엔드에 커스텀 스킴(`tasios://auth-callback`)
/// 콜백을 추가해 `ASWebAuthenticationSession`으로 전환해야 한다(별도 과제).
struct WebAuthView: UIViewRepresentable {
    let startURL: URL
    let onSuccess: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebAuthView
        private var finished = false

        init(_ parent: WebAuthView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            harvestSessionIfPresent(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        /// 세션 쿠키가 생겼으면 공유 저장소로 옮기고 성공 콜백.
        private func harvestSessionIfPresent(in webView: WKWebView) {
            guard !finished else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished else { return }
                let hasSession = cookies.contains {
                    $0.name.contains(AppConfig.sessionCookieNameFragment)
                }
                guard hasSession else { return }

                cookies.forEach(HTTPCookieStorage.shared.setCookie)
                self.finished = true
                self.parent.onSuccess()
            }
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            // 사용자가 취소했거나 리다이렉트 중 끊긴 경우는 오류로 보지 않는다.
            if nsError.code == NSURLErrorCancelled { return }
            guard !finished else { return }
            parent.onError(error.localizedDescription)
        }
    }
}

/// WKWebView 로그인을 시트로 감싸는 화면(취소 버튼 포함).
struct WebAuthScreen: View {
    let startURL: URL
    let onSuccess: () -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    var body: some View {
        NavigationStack {
            WebAuthView(startURL: startURL, onSuccess: onSuccess, onError: onError)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("로그인")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소", action: onCancel)
                    }
                }
        }
    }
}
