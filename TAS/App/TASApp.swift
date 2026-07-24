import SwiftUI
import GoogleSignIn

@main
struct TASApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(GuestStore.shared)
                .task { await session.bootstrap() }
                // 네이티브 Google 로그인 OAuth 콜백 URL 처리(리버스 클라이언트 ID 스킴).
                // Google URL이 아니면 handle이 false를 반환해 무해하다.
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
