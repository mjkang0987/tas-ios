import SwiftUI

@main
struct TASApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(GuestStore.shared)
                .task { await session.bootstrap() }
        }
    }
}
