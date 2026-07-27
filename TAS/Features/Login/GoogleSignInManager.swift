import Foundation
import UIKit
import GoogleSignIn

/// 네이티브 Google 로그인 래퍼(`GoogleSignIn` SDK). 웹 위임(ASWebAuth) 대신 iOS SDK로
/// 직접 로그인해 Google id_token을 얻고, 이를 백엔드가 Bearer 토큰으로 교환한다.
///
/// 동작 조건: Info.plist `GIDClientID`(iOS OAuth 클라이언트 ID)가 설정돼 있어야 한다.
/// 미설정이면 `SessionStore.signInGoogle`이 기존 웹 위임으로 폴백하므로, 이 타입은
/// 키가 준비된 뒤에만 호출된다. 셋업은 `docs/GOOGLE_SIGNIN.md` 참고.
@MainActor
final class GoogleSignInManager {
    /// 로그인 성공 시 백엔드로 넘길 자격 증명.
    struct Credential {
        /// Google OpenID Connect ID 토큰(JWT). 백엔드가 서명·audience를 검증해 사용자 식별.
        let idToken: String
        /// (선택) 서버 클라이언트 ID가 설정된 경우의 OAuth 인가 코드.
        let serverAuthCode: String?
    }

    enum SignInError: LocalizedError {
        case notConfigured
        case noPresenter
        case missingIDToken

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google 로그인 설정이 없습니다."
            case .noPresenter: return "로그인 화면을 표시할 수 없습니다."
            case .missingIDToken: return "Google 인증 토큰을 받지 못했습니다."
            }
        }
    }

    /// 네이티브 Google 로그인을 수행하고 id_token을 반환한다.
    func signIn() async throws -> Credential {
        guard let clientID = AppConfig.googleClientID else { throw SignInError.notConfigured }

        // 서버 클라이언트 ID가 있으면 id_token audience에 포함되도록 함께 구성.
        if let serverClientID = AppConfig.googleServerClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        } else {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        guard let presenter = Self.topViewController() else { throw SignInError.noPresenter }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw SignInError.missingIDToken }
        return Credential(idToken: idToken, serverAuthCode: result.serverAuthCode)
    }

    /// 사용자가 로그인 창을 닫아 취소한 경우(에러 메시지로 노출하지 않음).
    /// `kGIDSignInErrorDomain` / `kGIDSignInErrorCodeCanceled(-5)`.
    static func isUserCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == kGIDSignInErrorDomain && ns.code == -5
    }

    // MARK: - Presenter

    /// 현재 표시 중인 최상단 뷰컨트롤러. `WebAuthSession`의 keyWindow 탐색과 동일한 방식.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first) as? UIWindowScene
        guard let root = windowScene?.keyWindow?.rootViewController else { return nil }
        return topMost(from: root)
    }

    private static func topMost(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        return root
    }
}
