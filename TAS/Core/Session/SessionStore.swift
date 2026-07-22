import Foundation
import Observation

/// Authentication + current-store context for the app.
///
/// The TAS backend uses social login (Google / Kakao / Naver) that sets a
/// session cookie. This skeleton models the state machine; wiring the actual
/// `ASWebAuthenticationSession` flow is a TODO in `LoginView`.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(SessionUser)
    }

    var state: State = .loading
    var currentStore: Store?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var user: SessionUser? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// Probe the backend for an existing session on launch.
    func bootstrap() async {
        state = .loading
        do {
            let store = try await service.fetchStore()
            currentStore = store
            // A successful /api/store implies a valid session; the store carries the context.
            state = .signedIn(SessionUser(id: "me", storeId: store.id, role: .staff))
        } catch APIError.unauthorized {
            // 401 = 세션 없음, 또는 로그인은 됐으나 매장 미설정(온보딩 필요).
            // 후자(세션 쿠키는 있는데 storeId 없음) 분기는 온보딩 게이트(#9)에서 처리.
            state = .signedOut
        } catch {
            // Treat transport/unknown errors as signed-out so the UI stays usable offline.
            state = .signedOut
        }
    }

    /// Called after the web login flow completes and the session cookie is set.
    func didCompleteLogin() async {
        await bootstrap()
    }

    func signOut() {
        // Clear cookies so the next request is unauthenticated.
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach(HTTPCookieStorage.shared.deleteCookie)
        }
        currentStore = nil
        state = .signedOut
    }
}
