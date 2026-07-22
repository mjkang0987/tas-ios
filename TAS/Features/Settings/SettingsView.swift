import SwiftUI

/// 설정 — 매장 정보 및 로그아웃. 웹의 `/settings/*` 허브에 대응하는 스켈레톤.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("매장") {
                    LabeledContent("이름", value: session.currentStore?.name ?? "-")
                    if let type = session.currentStore?.shopType {
                        LabeledContent("업종", value: type)
                    }
                    if let slug = session.currentStore?.bookingSlug {
                        LabeledContent("예약 슬러그", value: slug)
                    }
                }

                Section("기능") {
                    Toggle("적립금", isOn: .constant(session.currentStore?.usePointSystem ?? false)).disabled(true)
                    Toggle("회원권", isOn: .constant(session.currentStore?.useMembershipSystem ?? false)).disabled(true)
                    Toggle("온라인예약", isOn: .constant(session.currentStore?.useOnlineBooking ?? false)).disabled(true)
                }

                Section("계정") {
                    if let user = session.user {
                        LabeledContent("권한", value: user.role.rawValue)
                    }
                    Button("로그아웃", role: .destructive) {
                        session.signOut()
                    }
                }

                Section {
                    LabeledContent("API", value: AppConfig.apiBaseURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
        }
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
