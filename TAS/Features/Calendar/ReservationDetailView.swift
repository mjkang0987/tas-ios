import SwiftUI

/// 예약 상세 (읽기 + 상태 변경). 탭한 예약의 전체 정보와 액션(변경/취소/노쇼/예약전환/삭제)을 시트로 보여준다.
/// 액션은 웹 `ReservationDetailFooterActions` 규칙을 이식:
/// - 활성 예약: 변경, (미결제 시)취소·노쇼, 삭제
/// - 취소·노쇼·완료 예약: 예약전환(복원), 삭제
struct ReservationDetailView: View {
    let reservation: Reservation
    let customer: Customer?
    let assignee: Assignee?
    var serviceColor: Color?
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

    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Confirm?
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showPayment = false

    /// 확인이 필요한 상태 전환 액션.
    private enum Confirm: Identifiable {
        case cancel, noshow, restore, delete, complete
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
            List {
                Section("고객") {
                    LabeledContent("이름") {
                        HStack(spacing: 6) {
                            Text(customer?.name ?? "고객 #\(reservation.customerId)")
                            if isNewCustomer { NewCustomerBadge() }
                        }
                    }
                    if let tel = customer?.formattedTel, !tel.isEmpty {
                        LabeledContent("연락처", value: tel)
                    }
                    if let points = customer?.points, points > 0 {
                        LabeledContent("적립금", value: "\(points.formatted())P")
                    }
                }

                Section("예약") {
                    LabeledContent("날짜", value: reservation.date)
                    LabeledContent("시간", value: "\(reservation.startTime) – \(reservation.endTime)")
                    LabeledContent("서비스") {
                        HStack(spacing: 6) {
                            if let serviceColor { ColorDot(color: serviceColor, size: 8) }
                            Text(reservation.service)
                        }
                    }
                    if let assignee {
                        LabeledContent("담당자") {
                            HStack(spacing: 6) {
                                ColorDot(color: Color(hex: assignee.color) ?? .gray)
                                Text(assignee.name)
                            }
                        }
                    }
                    LabeledContent("상태") { StatusBadge(state: reservation.displayState) }
                    if let channel = reservation.channel {
                        LabeledContent("경로", value: channel.rawValue)
                    }
                }

                Section("결제") {
                    if let price = reservation.price {
                        LabeledContent("금액", value: formatWon(price))
                    }
                    LabeledContent("결제 완료", value: reservation.hasCompletedPayment ? "예" : "아니오")
                    if let entries = reservation.paymentEntries, !entries.isEmpty {
                        ForEach(Array(entries.enumerated()), id: \.offset) { item in
                            LabeledContent(item.element.method.rawValue, value: formatWon(item.element.amount))
                        }
                    } else if let method = reservation.paymentMethod {
                        LabeledContent("수단", value: method.rawValue)
                    }
                    if let earned = reservation.pointEarned, earned != 0 {
                        LabeledContent("적립", value: "\(earned.formatted())P")
                    }
                }

                if let memo = reservation.memo, !memo.isEmpty {
                    Section("메모") { Text(memo) }
                }

                if !history.isEmpty {
                    Section {
                        NavigationLink {
                            ReservationHistoryView(entries: history, assigneeName: assigneeName)
                        } label: {
                            Label("변경 이력 (\(history.count))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }

                if let actionError {
                    Section { Text(actionError).font(.footnote).foregroundStyle(.red) }
                }

                actionSection
            }
            .navigationTitle("예약 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
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
                    service: service,
                    onCompleted: { await onChanged(); dismiss() }
                )
            }
        }
    }

    // MARK: - 액션

    @ViewBuilder private var actionSection: some View {
        // 온라인 예약 신청(requested)은 확정/거절 등 별도 흐름 — 앱에선 아직 미지원.
        if !isRequested {
            Section {
                if isInactive {
                    Button("예약전환") { confirming = .restore }
                    Button("삭제", role: .destructive) { confirming = .delete }
                } else {
                    // 결제 상태에 따라 웹 ReservationDetailFooterActions 규칙을 따른다.
                    if reservation.hasCompletedPayment {
                        Button("결제수단 변경") { showPayment = true }
                        Button("예약완료") { confirming = .complete }
                    } else {
                        Button("결제완료") { showPayment = true }
                    }
                    if let onEdit {
                        // dismiss()는 호출하지 않는다 — 상위 sheet(item:)의 값을 .edit로 바꾸면
                        // 시트가 교체되며, 여기서 dismiss까지 하면 교체가 취소된다.
                        Button("변경") { onEdit(reservation) }
                    }
                    // 결제 완료 예약은 취소·노쇼 대신 예약완료/변경/삭제만(웹 규칙).
                    if !reservation.hasCompletedPayment {
                        Button("취소", role: .destructive) { confirming = .cancel }
                        Button("노쇼") { confirming = .noshow }
                    }
                    Button("삭제", role: .destructive) { confirming = .delete }
                }
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
        }
    }

    private func confirmRole(_ c: Confirm) -> ButtonRole? {
        switch c {
        case .cancel, .delete: return .destructive
        case .noshow, .restore, .complete: return nil
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
            case .delete: try await service.deleteReservation(id: reservation.id)
            }
            await onChanged()
            dismiss()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}
