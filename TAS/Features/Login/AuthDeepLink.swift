import Foundation

/// `tasios://auth/callback` 딥링크 파싱. clipnote `AuthDeepLink` 이식.
/// - `tasios://auth/callback?code=…`  → 1회성 code 교환 대상
/// - `tasios://auth/callback?error=…` → 로그인 실패 사유
enum AuthDeepLink: Equatable {
    case code(String)
    case error(String)

    static let scheme = "tasios"

    static func parse(_ url: URL) -> AuthDeepLink? {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host == "auth",
              comps.path == "/callback" else { return nil }

        func query(_ name: String) -> String? {
            comps.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        if let code = query("code") { return .code(code) }
        if let error = query("error") { return .error(error) }
        return nil
    }
}
