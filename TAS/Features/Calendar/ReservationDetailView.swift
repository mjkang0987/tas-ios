import SwiftUI

/// 예약 상세 (읽기 + 상태 변경). 탭한 예약의 전체 정보와 액션(변경/취소/노쇼/예약전환/삭제)을 시트로 보여준다.
/// 액션은 웹 `ReservationDetailFooterActions` 규칙을 이식:
/// - 활성 예약: 변경, (미결제 시)취소·노쇼, 삭제
/// - 취소·노쇼·완료 예약: 예약전환(복원), 삭제
struct ReservationDetailView: View {
    @Environment(SessionStore.self) private var session
    private var labels: StoreLabels { session.labels }
    let reservation: Reservation
    let customer: Customer?
    let assignee: Assignee?
    let serviceColorMap: [String: String]
    var isNewCustomer: Bool = false
    /// 쓰기 경로(게스트/API 자동 분기). 기본값은 상세 표시만 하던 기존 호출부 호환용.
    var service: TASService = TASService()
    /// 상태 변경/삭제 후 캘린더를 다시 로드하기 위한 콜백.
    var onChanged: () async -> Void = {}
    /// "변경" 탭 시 편집 폼을 여는 콜백(제공되지 않으면 변경 버튼 숨김).
    var onEdit: ((Reservation) -> Void)? = nil
    /// 이 예약의 변경 이력(최신순) + 담당자 이름 해석기.
    var history: [ReservationHistoryEntry] = []
    var assigneeName: (Int?) -> String = { _ in "미지정" }
    /// 매장 적립률(%) — 결제 시 자동 적립용. 0이면 적립 없음.
    var pointRate: Int = 0
    /// 고객명을 누르면 그 고객 상세(웹·안드로이드와 같은 링크). 없으면 글자만.
    var onCustomerTap: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Confirm?
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showPayment = false

    /// 확인이 필요한 상태 전환 액션.
    private enum Confirm: Identifiable {
        case cancel, noshow, restore, delete, complete, approve, reject
        var id: Int { hashValue }
    }

    /// 취소·노쇼·완료 = 비활성(웹 isInactive).
    private var isInactive: Bool {
        switch reservation.status {
        case .cancelled, .noshow, .completed: return true
        default: return false
        }
    }
    private var isRequested: Bool { reservation.status == .requested }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailRows
                    if !history.isEmpty {
                        Divider()
                        NavigationLink {
                            ReservationHistoryView(entries: history, assigneeName: assigneeName)
                        } label: {
                            Text("변경 이력 (\(history.count))")
                                .font(.tasBody.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                    }
                    if isRequested {
                        Text("온라인으로 접수된 예약 신청입니다. 확정하면 예약으로 전환됩니다.")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    if let actionError {
                        Text(actionError).font(.footnote).foregroundStyle(Color.dangerText)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 웹 레이어처럼 아래에 붙는 버튼 줄 — 채운 색은 주 동작 하나만
            .safeAreaInset(edge: .bottom) { actionBar }
            // 웹 레이어 머리처럼 제목은 고객 이름
            .navigationTitle(customer?.name ?? "예약 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 웹 하단 버튼 줄에 없는 삭제는 "…" 메뉴로(지시자 2026-10-23)
                    Menu {
                        Button("삭제", systemImage: "trash", role: .destructive) { confirming = .delete }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("더보기")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("닫기")
                }
            }
            .disabled(isWorking)
            .confirmationDialog(confirmTitle, isPresented: confirmBinding, titleVisibility: .visible) {
                if let confirming {
                    Button(confirmButtonLabel(confirming), role: confirmRole(confirming)) {
                        Task { await perform(confirming) }
                    }
                }
                Button("닫기", role: .cancel) {}
            }
            .sheet(isPresented: $showPayment) {
                ReservationPaymentView(
                    reservation: reservation,
                    customer: customer,
                    pointRate: pointRate,
                    service: service,
                    // 상세는 닫지 않는다 — 상세 쌓기가 다시 읽은 값으로 다시 그린다(안드로이드처럼 결제 뒤에도 그 자리)
                    onCompleted: { await onChanged() }
                )
            }
        }
    }

    // MARK: - 본문 — 웹 `ReservationViewSection` 순서(상태 · 날짜 · 시간 · 서비스 · 가격 · 결제 · 고객명 · 연락처 ·
    // 고객 메모 · 요청사항 · 적립금 · 담당자 · 예약경로)

    private var detailRows: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            if reservation.status == .cancelled { row("상태") { ToneBadge(tone: .cancelled, text: "취소") } }
            if reservation.status == .noshow { row("상태") { ToneBadge(tone: .noshow, text: "노쇼") } }
            if reservation.status == .completed { row("상태") { ToneBadge(tone: .completed, text: "완료") } }
            if isRequested { row("상태") { ToneBadge(tone: .requested, text: "확정대기") } }
            row("날짜") { Text(reservation.date) }
            row("시간") { Text("\(reservation.startTime) ~ \(reservation.endTime)") }
            row("\(labels.service)") { ServiceChipList(service: reservation.service, colorMap: serviceColorMap, font: .footnote) }
            row("가격") { Text(formatWon(reservation.price ?? 0)) }
            row("결제") { paymentValue }
            row("고객명") { customerName }
            row("연락처") {
                if let customer, !customer.formattedTel.isEmpty { TelLink(customer: customer) } else { Text("-") }
            }
            if let tags = customer?.memoTags, !tags.isEmpty {
                row("고객 메모") {
                    WrapLayout(spacing: 6) { ForEach(Array(tags.enumerated()), id: \.offset) { MemoTagPill(tag: $0.element) } }
                }
            }
            if let memo = reservation.memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                row("요청사항") { Text(memo) }
            }
            row("적립금") { Text(formatWon(customer?.points ?? 0)) }
            row("\(labels.assignee)") { AssigneeBadge(name: assignee?.name ?? "미지정", color: Color(hex: assignee?.color)) }
            row("예약경로") { channelValue }
        }
        .font(.tasBody)
    }

    /// 라벨 | 값 한 줄 — 웹 `dt`/`dd` 2열 그리드.
    private func row<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.textSecondary).gridColumnAlignment(.leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 결제 — 결제완료/미결제 배지 + 결제 줄(수단 왼쪽 · 금액 오른쪽). 결제완료인데 줄이 없는 옛 데이터만 '미입력'.
    private var paymentValue: some View {
        let entries = reservation.paymentEntries ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ToneBadge(tone: reservation.hasCompletedPayment ? .paid : .unpaid,
                      text: reservation.hasCompletedPayment ? "결제완료" : "미결제")
            if reservation.hasCompletedPayment && entries.isEmpty {
                Text("미입력").foregroundStyle(Color.textSecondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { item in
                HStack {
                    Text(item.element.method.rawValue)
                    Spacer()
                    Text(formatWon(item.element.amount)).monospacedDigit()
                }
            }
            // 결제 줄의 '네이버 예약금'과 금액이 같으면 두 번 보이지 않는다(웹과 같다).
            if reservation.naverBookingId != nil, let deposit = reservation.naverDeposit, deposit > 0,
               entries.filter({ $0.method == .naverDeposit }).map(\.amount).reduce(0, +) != deposit {
                HStack(spacing: 6) {
                    NaverMark()
                    Text("네이버 예약 확정 예약금")
                    Spacer()
                    Text(formatWon(deposit)).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder private var customerName: some View {
        HStack(spacing: 4) {
            if isNewCustomer { NewCustomerBadge() }
            let name = customer?.name ?? "고객 #\(reservation.customerId)"
            if let onCustomerTap, customer != nil {
                // 웹 고객명 링크 색(#1967D2) — 어두운 모드는 밝힌 파랑
                Button(name) { onCustomerTap(reservation.customerId) }
                    .foregroundStyle(Color.linkText)
                    .accessibilityHint("고객 상세 열기")
            } else {
                Text(name)
            }
        }
    }

    /// 예약경로 — 네이버 예약이면 배지·예약번호·바로가기 + 스마트플레이스 안내(웹 `NaverBookingInfo`), 아니면 경로 태그.
    @ViewBuilder private var channelValue: some View {
        if let bookingId = reservation.naverBookingId {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("네이버예약")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        // 네이버 초록(#03C75A) 위 흰 글자는 2.2:1 — 같은 색을 진하게 깐다(담당자 뱃지와 같은 규칙)
                        .background((Color(hex: "#03C75A") ?? .green).forWhiteText, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                    Text(bookingId).font(.caption).foregroundStyle(Color.textSecondary)
                    if let urlString = reservation.naverBookingUrl, let url = URL(string: urlString) {
                        Link("바로가기 ↗", destination: url).font(.caption.weight(.semibold))
                    }
                }
                Text("네이버예약의 실제 변경/취소는 스마트플레이스 통해서 가능합니다.")
                    .font(.caption)
                    // 웹은 진한 초록 글자 — 다크 모드에서 안 읽혀 글자는 시스템 색, 바탕만 초록으로
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((Color(hex: "#03C75A") ?? .green).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            ToneBadge(tone: .booked, text: reservation.channel?.rawValue ?? ReservationChannel.phone.rawValue)
        }
    }

    // MARK: - 액션 — 웹 `ReservationDetailFooterActions` 보기 모드 규칙(삭제만 "…" 메뉴)

    private var actionBar: some View {
        // 웹처럼 오른쪽 정렬, 버튼이 많아 안 들어가면(큰 글씨 설정 등) 가로로 민다
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { Spacer(minLength: 0); actionButtons }
                .padding(.horizontal, 16).padding(.vertical, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actionButtons }
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    @ViewBuilder private var actionButtons: some View {
        if isRequested {
            Button("예약확정") { confirming = .approve }.buttonStyle(.action(.primary))
            Button("거절") { confirming = .reject }.buttonStyle(.action(.dangerOutline))
        } else if isInactive {
            Button("예약전환") { confirming = .restore }.buttonStyle(.action(.primary))
        } else {
            let paid = reservation.hasCompletedPayment
            Button(paid ? "결제수단 변경" : "결제완료") { showPayment = true }
                .buttonStyle(.action(paid ? .plain : .primary))
            if paid {
                Button("예약완료") { confirming = .complete }.buttonStyle(.action(.primary))
            } else {
                Button("취소") { confirming = .cancel }.buttonStyle(.action(.dangerOutline))
                Button("노쇼") { confirming = .noshow }.buttonStyle(.action(.dangerOutline))
            }
            if let onEdit {
                Button("변경") { onEdit(reservation) }.buttonStyle(.action(.plain))
            }
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var confirmTitle: String {
        switch confirming {
        case .cancel: return "이 예약을 취소할까요?"
        case .noshow: return "노쇼로 처리할까요?"
        case .restore: return "예약으로 되돌릴까요?"
        case .delete: return "이 예약을 삭제할까요? 되돌릴 수 없습니다."
        case .complete: return "예약을 완료 처리할까요?"
        case .approve: return "이 예약 신청을 확정할까요?"
        case .reject: return "이 예약 신청을 거절할까요?"
        case nil: return ""
        }
    }

    private func confirmButtonLabel(_ c: Confirm) -> String {
        switch c {
        case .cancel: return "예약 취소"
        case .noshow: return "노쇼 처리"
        case .restore: return "예약전환"
        case .delete: return "삭제"
        case .complete: return "예약완료"
        case .approve: return "예약 확정"
        case .reject: return "거절"
        }
    }

    private func confirmRole(_ c: Confirm) -> ButtonRole? {
        switch c {
        case .cancel, .delete, .reject: return .destructive
        case .noshow, .restore, .complete, .approve: return nil
        }
    }

    private func perform(_ action: Confirm) async {
        isWorking = true
        actionError = nil
        do {
            switch action {
            case .cancel: try await service.setReservationStatus(id: reservation.id, status: .cancelled)
            case .noshow: try await service.setReservationStatus(id: reservation.id, status: .noshow)
            case .restore: try await service.setReservationStatus(id: reservation.id, status: .active)
            case .complete: try await service.setReservationStatus(id: reservation.id, status: .completed)
            case .approve: try await service.setReservationStatus(id: reservation.id, status: .active)
            case .reject: try await service.setReservationStatus(id: reservation.id, status: .cancelled)
            case .delete: try await service.deleteReservation(id: reservation.id)
            }
            // 먼저 닫고 다시 읽는다 — 다시 읽은 뒤 닫으면 지운·바뀐 예약이 빠진 데이터로 한 번 그려져
            // 닫히는 동안 '삭제된 예약입니다'가 비친다(상세 쌓기는 id 로 그린다).
            dismiss()
            await onChanged()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}

/// 네이버 로고(초록 바탕 N) — 웹 `StyledNaverLogo` 대응. 예약금 줄 앞에만 쓴다.
private struct NaverMark: View {
    var body: some View {
        Text("N")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background((Color(hex: "#03C75A") ?? .green).forWhiteText, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
    }
}
