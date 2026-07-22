import Foundation

/// App-wide configuration.
///
/// The base URL points at the takeaseat (TAS) web backend, which exposes the
/// data API under `/api/*` (see the `tas` repo, `server/api/`).
///
/// Default is production. To target another environment, set the
/// `TAS_API_BASE_URL` key in Info.plist (e.g. via a Debug-only
/// `INFOPLIST_KEY_TAS_API_BASE_URL` build setting) — no code change needed:
///   - dev:   https://dev.takeaseat.co.kr
///   - local: http://localhost:3000  (needs an ATS exception for HTTP)
enum AppConfig {
    static let apiBaseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "TAS_API_BASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://takeaseat.co.kr")!
    }()

    /// Cookie name carrying the invite code during social login — GUIDE.md §1-1.
    static let inviteCookieName = "tas-invite-code"

    /// 웹 로그인 페이지 (NextAuth `pages.signIn = '/login'`).
    static var loginURL: URL { apiBaseURL.appendingPathComponent("login") }

    /// 모바일 로그인 시작 URL. 웹 `/login`을 ASWebAuth로 열되, 로그인 완료 후
    /// 모바일 브리지(`/api/mobile-auth/complete?nonce=…`)로 돌아오도록 callbackUrl을 실어 보낸다.
    static func mobileLoginURL(nonce: String) -> URL? {
        let completePath = "/api/mobile-auth/complete?nonce=\(nonce)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = completePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? completePath
        return URL(string: "\(loginURL.absoluteString)?callbackUrl=\(encoded)&mobile=1")
    }
}
