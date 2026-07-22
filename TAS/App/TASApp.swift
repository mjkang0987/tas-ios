import SwiftUI

@main
struct TASApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.bootstrap() }
        }
    }
}
