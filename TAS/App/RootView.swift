import SwiftUI

/// Top-level router: login gate → main tabs.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(GuestStore.self) private var guest

    var body: some View {
        content
            // 로그인 직후 게스트 데이터가 있고 계정에 이미 매장이 있으면 이관 확인.
            .alert("게스트 데이터 이관", isPresented: migrationConfirmBinding) {
                Button("취소", role: .cancel) { session.cancelMigration() }
                Button("이관") { Task { await session.confirmMigration() } }
            } message: {
                Text("이미 설정된 매장이 있습니다. 이 기기의 게스트 데이터를 계정으로 이관할까요?")
            }
            .alert("알림", isPresented: migrationMessageBinding) {
                Button("확인", role: .cancel) { session.migrationMessage = nil }
            } message: {
                Text(session.migrationMessage ?? "")
            }
    }

    @ViewBuilder private var content: some View {
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

    private var migrationConfirmBinding: Binding<Bool> {
        Binding(get: { session.pendingMigration }, set: { if !$0 { session.pendingMigration = false } })
    }

    private var migrationMessageBinding: Binding<Bool> {
        Binding(get: { session.migrationMessage != nil }, set: { if !$0 { session.migrationMessage = nil } })
    }
}

/// Primary navigation, mirroring the web app's top-level pages
/// (캘린더 `/`, 주소록 `/address`, 설정 — 서비스는 설정 하위로).
struct MainTabView: View {
    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("캘린더", systemImage: "calendar") }

            CustomersView()
                .tabItem { Label("고객", systemImage: "person.2") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
}
