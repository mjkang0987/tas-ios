import AuthenticationServices
import UIKit

/// `ASWebAuthenticationSession`을 async로 감싼다.
/// 진짜 Safari 컨텍스트라 Google OAuth도 허용된다(임베디드 웹뷰의 한계 없음).
/// clipnote가 Supabase SDK로 얻던 것을 여기선 직접 구성한다.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// 웹 로그인을 열고 커스텀 스킴 콜백 URL(tasios://…)을 반환한다.
    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: ASWebAuthenticationSessionError(.canceledLogin))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first) as? UIWindowScene
            return windowScene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
