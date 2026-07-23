import Foundation
import Observation
import AuthenticationServices

/// 인증 + 현재 매장 컨텍스트.
///
/// clipnote-ios(Supabase Bearer + ASWebAuthenticationSession)와 동일한 앱 구조를
/// tas의 NextAuth 백엔드에 맞춘 모바일 브리지로 구현한다:
/// 웹 `/login`을 ASWebAuth로 열어 로그인 → `tasios://auth/callback?code=` 수신 →
/// `/api/mobile-auth/exchange`로 Bearer 토큰 교환 → Keychain 보관.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case guest
        case signedIn(SessionUser)
    }

    var state: State = .loading
    var currentStore: Store?
    /// 마지막 로그인 실패 메시지(유저 취소는 제외). LoginView가 표시.
    var lastError: String?

    private let service: TASService
    private let keychain = KeychainTokenStore.shared
    private let webAuth = WebAuthSession()

    init(service: TASService = TASService()) {
        self.service = service
    }

    var user: SessionUser? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// 앱 시작 시: 저장된 토큰이 있으면 검증(매장 조회)해 세션 복원.
    /// 토큰이 없어도 게스트 데이터(온보딩 완료)가 있으면 게스트 모드로 복귀.
    func bootstrap() async {
        state = .loading
        if keychain.token != nil {
            await loadSession()
            return
        }
        if GuestStore.shared.hasOnboardedData {
            enterGuest()
            return
        }
        state = .signedOut
    }

    // MARK: - Guest (게스트 · 오프라인 로컬)

    /// 게스트 모드 진입: 로컬 스냅샷 활성화. 온보딩 여부는 RootView가 분기.
    func enterGuest() {
        GuestStore.shared.activate()
        currentStore = GuestStore.shared.syntheticStore
        state = .guest
    }

    /// 게스트 모드 종료(로컬 데이터는 유지) → 로그인 화면으로.
    /// (온보딩의 "로그인으로 돌아가기"용 — 데이터 보존)
    func exitGuest() {
        GuestStore.shared.deactivate()
        currentStore = nil
        state = .signedOut
    }

    /// 현재 게스트 모드인지.
    var isGuest: Bool { state == .guest }

    /// 게스트 로그아웃 — 로컬 데이터를 전부 삭제하고 로그인 화면으로.
    /// (게스트는 계정이 없어 데이터가 기기에만 있으므로 로그아웃 = 삭제)
    func logoutGuest() {
        GuestStore.shared.reset()
        GuestStore.shared.deactivate()
        currentStore = nil
        state = .signedOut
    }

    /// 소셜 로그인: 웹 `/login`을 ASWebAuth로 열고 code 교환 → 토큰 저장 → 세션 로드.
    ///
    /// - Parameters:
    ///   - provider: 탭한 소셜 provider(`google`/`kakao`/`naver`). nil이면 웹에서 직접 선택.
    ///   - invite: 신규 등록용 초대코드(선택).
    func signIn(provider: String? = nil, invite: String? = nil) async {
        lastError = nil
        let nonce = Self.makeNonce()
        guard let startURL = AppConfig.mobileLoginURL(nonce: nonce, provider: provider, invite: invite) else {
            lastError = "로그인 주소 구성에 실패했습니다."
            return
        }

        do {
            let callback = try await webAuth.start(url: startURL, callbackScheme: AuthDeepLink.scheme)
            switch AuthDeepLink.parse(callback) {
            case let .code(code):
                let token = try await service.exchangeMobileCode(code: code, nonce: nonce)
                keychain.save(token)
                await loadSession()
            case let .error(reason):
                lastError = Self.message(for: reason)
            case nil:
                lastError = "로그인 응답을 해석하지 못했습니다."
            }
        } catch {
            if !Self.isUserCancellation(error) {
                lastError = error.localizedDescription
            }
        }
    }

    func signOut() {
        keychain.clear()
        currentStore = nil
        state = .signedOut
    }

    /// 토큰으로 매장을 조회해 세션 확정. 401이면 토큰 폐기·로그아웃.
    private func loadSession() async {
        do {
            let store = try await service.fetchStore()
            currentStore = store
            let claims = keychain.token.flatMap(MobileToken.decode)
            state = .signedIn(SessionUser(
                id: claims?.userId ?? "me",
                storeId: claims?.storeId ?? store.id,
                role: claims?.role ?? .staff
            ))
        } catch APIError.unauthorized {
            keychain.clear()
            currentStore = nil
            state = .signedOut
        } catch {
            // 네트워크 오류 등은 로그아웃까지 가지 않고 signedOut로만 처리.
            state = .signedOut
        }
    }

    // MARK: - Helpers

    static func isUserCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    static func makeNonce() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func message(for reason: String) -> String {
        switch reason {
        case "no_store": return "매장이 없습니다. 웹에서 온보딩을 먼저 완료해주세요."
        case "no_session": return "로그인에 실패했습니다. 다시 시도해주세요."
        default: return "로그인 오류: \(reason)"
        }
    }
}
