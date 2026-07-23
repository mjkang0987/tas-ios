import SwiftUI

/// Top-level router: login gate → main tabs.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(GuestStore.self) private var guest

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView("불러오는 중…")
        case .signedOut:
            LoginView()
        case .guest:
            // 게스트 진입 순서: 약관 동의 → 온보딩 → 메인.
            if !guest.hasConsented {
                GuestConsentView()
            } else if guest.isOnboarded {
                MainTabView()
            } else {
                GuestOnboardingView()
            }
        case .signedIn:
            MainTabView()
        }
    }
}

/// Primary navigation, mirroring the web app's top-level pages
/// (캘린더 `/`, 주소록 `/address`, 서비스, 설정).
struct MainTabView: View {
    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("캘린더", systemImage: "calendar") }

            CustomersView()
                .tabItem { Label("고객", systemImage: "person.2") }

            ServicesView()
                .tabItem { Label("서비스", systemImage: "scissors") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
}
