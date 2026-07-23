import SwiftUI

/// 게스트 약관 동의 — 웹 `/consent` 페이지 이식(게스트 진입 필수 단계).
///
/// 게스트(오프라인)는 서버 처리위탁(DPA) 없이 **이용약관 + 개인정보 수집·이용**만
/// 필수로 받는다(처리위탁 동의는 로그인·SNS 연동 시 별도). 동의하면 온보딩으로 진행,
/// 동의하지 않으면 로그인 화면으로 돌아간다.
struct GuestConsentView: View {
    @Environment(GuestStore.self) private var guest
    @Environment(SessionStore.self) private var session

    @State private var agreeTerms = false
    @State private var agreePrivacy = false
    @State private var showDecline = false

    private var allAgreed: Bool { agreeTerms && agreePrivacy }
    private var allBinding: Binding<Bool> {
        Binding(get: { allAgreed }, set: { on in agreeTerms = on; agreePrivacy = on })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    consentCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }

            footer
        }
        .confirmationDialog("약관에 동의하지 않으면 서비스를 이용할 수 없습니다.",
                            isPresented: $showDecline, titleVisibility: .visible) {
            Button("로그인으로 돌아가기", role: .destructive) { session.exitGuest() }
            Button("계속 보기", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "chair.lounge.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("약관 동의").font(.title2.weight(.bold))
            Text("TAS 이용을 위해 아래 약관에 동의해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var consentCard: some View {
        VStack(spacing: 0) {
            ConsentRow(isOn: allBinding, text: "전체 동의", emphasized: true)
            Divider().padding(.leading, 44)
            ConsentRow(isOn: $agreeTerms, text: "이용약관 동의", required: true)
            Divider().padding(.leading, 44)
            ConsentRow(isOn: $agreePrivacy, text: "개인정보 수집·이용 동의", required: true)
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                guest.agreeToTerms()
            } label: {
                Text("동의하고 시작하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allAgreed)

            Button("동의 안 함") { showDecline = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(.bar)
    }
}

/// 약관 동의 체크 행 — 좌측 체크 아이콘 + 텍스트((필수) 배지 옵션).
private struct ConsentRow: View {
    @Binding var isOn: Bool
    let text: String
    var required: Bool = false
    var emphasized: Bool = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                if required {
                    Text("(필수) ").font(.subheadline.weight(.semibold)).foregroundColor(.accentColor)
                        + Text(text).font(.subheadline)
                } else {
                    Text(text).font(emphasized ? .body.weight(.bold) : .subheadline)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
