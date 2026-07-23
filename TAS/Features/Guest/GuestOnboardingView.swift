import SwiftUI

/// 게스트 온보딩(미니) — 웹 `/onboarding/guest`의 인트로 단계 이식.
///
/// 로그인 없이 매장 이름만 받아 로컬 스냅샷을 온보딩 완료 상태로 만든다.
/// (서비스·담당자 상세 편집 단계는 이후 확장. 지금은 "30초 설정으로 바로 시작".)
/// 게스트 데이터는 이 기기에만 저장되며, 로그인 시 서버로 이관할 수 있다.
struct GuestOnboardingView: View {
    @Environment(GuestStore.self) private var guest
    @Environment(SessionStore.self) private var session
    @State private var storeName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("게스트로 시작하기")
                        .font(.system(.title, design: .rounded).bold())
                    Text("⚡ 30초 설정으로 바로 시작")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                guestNotice

                VStack(alignment: .leading, spacing: 8) {
                    Text("매장 이름")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("예: 테이크어시트 헤어", text: $storeName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(spacing: 12) {
                    Button {
                        start()
                    } label: {
                        Text("시작하기")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("설정 없이 둘러보기") { skip() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("로그인으로 돌아가기") { session.exitGuest() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { nameFocused = false }
            }
        }
    }

    /// 게스트 모드 안내(웹 `GuestNotice`) — 로컬 저장·기기 한정 안내.
    private var guestNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("게스트 모드 안내", systemImage: "info.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text("데이터는 이 기기에만 저장돼요. 다른 기기에서는 보이지 않고, 앱·브라우저 데이터를 지우면 사라져요. 로그인하면 지금까지 입력한 데이터를 계정으로 옮길 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func start() {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guest.completeOnboarding(storeName: name.isEmpty ? nil : name, shopType: nil)
        session.currentStore = guest.syntheticStore
    }

    private func skip() {
        guest.skipOnboarding()
        session.currentStore = guest.syntheticStore
    }
}

#Preview {
    GuestOnboardingView()
        .environment(GuestStore.shared)
        .environment(SessionStore())
}
