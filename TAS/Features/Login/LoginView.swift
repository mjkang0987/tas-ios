import SwiftUI

/// 앱 최초 진입화면 — 소셜 로그인. 웹 `/login` 카드 디자인을 iOS 네이티브로 이식.
///
/// clipnote-ios처럼 `ASWebAuthenticationSession`(진짜 Safari)으로 웹 `/login`을 열어
/// 로그인하고, `tasios://auth/callback?code=`를 받아 Bearer 토큰으로 교환한다
/// (`SessionStore.signIn`). Safari 컨텍스트라 Google OAuth도 정상 동작한다.
///
/// 디자인 이식(웹 login.tsx 기준):
/// 브랜드 헤더 → "SNS 계정으로 로그인" 서브타이틀 → 초대코드(선택) → provider 버튼
/// (Google 흰색 / 카카오 #FEE500 / 네이버 #03C75A). 버튼 색·라벨은 웹과 동일.
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var inviteCode = ""
    @State private var showInvite = false
    @State private var authenticatingProvider: String?
    @FocusState private var inviteFocused: Bool

    /// 웹 `ALL_PROVIDERS`와 동일 — id / 라벨 / 배경 / 글자 / 테두리 색.
    private struct Provider: Identifiable {
        let id: String
        let label: String
        let background: Color
        let foreground: Color
        let border: Color
    }

    private let providers: [Provider] = [
        Provider(id: "google", label: "Google 로그인",
                 background: .white, foreground: Color(hex: "333333") ?? .black, border: Color(hex: "DDDDDD") ?? .gray),
        Provider(id: "kakao", label: "카카오 로그인",
                 background: Color(hex: "FEE500") ?? .yellow, foreground: Color(hex: "191919") ?? .black, border: Color(hex: "FEE500") ?? .yellow),
        Provider(id: "naver", label: "네이버 로그인",
                 background: Color(hex: "03C75A") ?? .green, foreground: .white, border: Color(hex: "03C75A") ?? .green),
    ]

    private var isAuthenticating: Bool { authenticatingProvider != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 48)
                brandHeader
                Spacer(minLength: 40)
                card
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { inviteFocused = false }
            }
        }
        .alert("로그인 오류", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("확인", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    // MARK: - Brand header

    private var brandHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "chair.lounge.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            Text("take a seat")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text("미용실 예약·고객·매출 관리")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Login card

    private var card: some View {
        VStack(spacing: 16) {
            Text("SNS 계정으로 로그인")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            inviteSection

            VStack(spacing: 12) {
                ForEach(providers) { provider in
                    providerButton(provider)
                }
            }

            guestButton
        }
        .frame(maxWidth: 380)
    }

    /// 웹 `게스트로 사용하기` — 로그인 없이 로컬(오프라인) 모드로 시작.
    private var guestButton: some View {
        Button {
            session.enterGuest()
        } label: {
            Text("게스트로 사용하기")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
        .padding(.top, 4)
    }

    private func providerButton(_ provider: Provider) -> some View {
        Button {
            startLogin(provider.id)
        } label: {
            ZStack {
                if authenticatingProvider == provider.id {
                    ProgressView()
                        .tint(provider.foreground)
                } else {
                    Text(provider.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(provider.foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(provider.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(provider.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
        .opacity(isAuthenticating && authenticatingProvider != provider.id ? 0.5 : 1)
    }

    // MARK: - Invite code (신규 등록 시)

    private var inviteSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showInvite.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("초대코드가 있으신가요?")
                        .font(.footnote)
                    Image(systemName: showInvite ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showInvite {
                TextField("6자리 코드", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16, weight: .semibold))
                    .kerning(4)
                    .focused($inviteFocused)
                    .submitLabel(.done)
                    .onSubmit { inviteFocused = false }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: inviteCode) { _, newValue in
                        inviteCode = String(newValue.uppercased().prefix(6))
                    }
            }
        }
    }

    // MARK: - Actions

    private func startLogin(_ provider: String) {
        guard !isAuthenticating else { return }
        let invite = inviteCode.trimmingCharacters(in: .whitespaces)
        Task {
            authenticatingProvider = provider
            await session.signIn(provider: provider, invite: invite.isEmpty ? nil : invite)
            authenticatingProvider = nil
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
