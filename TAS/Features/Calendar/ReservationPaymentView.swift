import SwiftUI

/// 결제완료/결제수단 변경 시트 — 웹 `ReservationDetailPaymentLayer` 이식(핵심).
///
/// 결제 항목(수단+금액)을 1개 이상 입력해 `paymentEntries`로 저장하고 결제 완료로 표시한다.
/// 저장은 PUT `updateReservation`(게스트=로컬). 적립금 자동 적립은 다음 단계.
struct ReservationPaymentView: View {
    let reservation: Reservation
    /// 적립 대상 고객(적립 크레딧용). 없으면 적립 생략.
    var customer: Customer? = nil
    /// 매장 적립률(%) — 0이면 자동 적립 섹션 숨김.
    var pointRate: Int = 0
    var service: TASService = TASService()
    /// 저장 완료 후: 상위(캘린더) 리로드 + 상세 닫기.
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var entries: [PaymentEntry] = []
    @State private var pointAwardEnabled = false
    @State private var pointAward = 0
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// 선택 가능한 결제수단(웹 PAYMENT_METHOD 순서).
    private static let methods: [PaymentMethod] = [
        .cash, .cashReceipt, .card, .naverPay, .localCurrency,
        .localCurrencyReceipt, .giftCard, .points, .discount, .naverDeposit
    ]

    private var enteredTotal: Int { entries.map(\.amount).reduce(0, +) }
    /// 적립금 사용 결제분 제외 금액(적립 기준액).
    private var nonPointTotal: Int { entries.filter { $0.method != .points }.map(\.amount).reduce(0, +) }
    private var defaultAward: Int { pointRate > 0 ? (nonPointTotal * pointRate) / 100 : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(entries.indices, id: \.self) { i in
                        HStack {
                            Picker("결제종류", selection: $entries[i].method) {
                                ForEach(Self.methods, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            Spacer()
                            TextField("금액", value: $entries[i].amount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("원").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        // 최소 1개는 유지.
                        if entries.count > 1 { entries.remove(atOffsets: offsets) }
                    }
                    Button("결제수단 추가") {
                        entries.append(PaymentEntry(method: .card, amount: 0))
                    }
                } header: {
                    Text("결제 종류·금액")
                } footer: {
                    Text("합계 \(formatWon(enteredTotal)) · 예약가 \(formatWon(reservation.price ?? 0))")
                        .foregroundStyle(enteredTotal == (reservation.price ?? 0) ? Color.secondary : Color.orange)
                }

                if pointRate > 0 || (reservation.pointEarned ?? 0) > 0 {
                    Section {
                        Toggle("적립", isOn: $pointAwardEnabled)
                        if pointAwardEnabled {
                            HStack {
                                Text("적립금")
                                Spacer()
                                TextField("0", value: $pointAward, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                Text("P").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("적립")
                    } footer: {
                        if pointAwardEnabled, pointRate > 0 {
                            Text("적립률 \(pointRate)% 기준 \(formatWon(nonPointTotal))의 \(defaultAward.formatted())P")
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(reservation.hasCompletedPayment ? "결제수단 변경" : "결제완료")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setup)
        }
    }

    private func setup() {
        guard entries.isEmpty else { return }
        if let existing = reservation.paymentEntries, !existing.isEmpty {
            entries = existing
        } else {
            entries = [PaymentEntry(method: .card, amount: reservation.price ?? 0)]
        }
        // 적립 초기값: 기존 적립분이 있으면 그 값, 없으면 적립률 기준 자동 계산.
        if pointRate > 0 || (reservation.pointEarned ?? 0) > 0 {
            pointAwardEnabled = (reservation.pointEarned ?? 0) > 0 || pointRate > 0
            pointAward = reservation.pointEarned ?? defaultAward
        }
    }

    private func save() async {
        if entries.isEmpty || entries.allSatisfy({ $0.amount == 0 }) {
            errorMessage = "결제 금액을 입력해주세요."
            return
        }
        isSaving = true
        defer { isSaving = false }
        var updated = reservation
        updated.paymentEntries = entries
        updated.paymentCompleted = true
        // 단일 결제면 paymentMethod도 채워 목록/뱃지 호환.
        updated.paymentMethod = entries.count == 1 ? entries.first?.method : nil

        // 적립 반영: 신규 적립분과 기존 적립분의 차이만큼 고객 적립금 조정.
        let previousEarned = reservation.pointEarned ?? 0
        let newEarned = pointAwardEnabled ? max(0, pointAward) : 0
        updated.pointEarned = newEarned

        do {
            _ = try await service.updateReservation(prev: reservation, updated: updated)
            let delta = newEarned - previousEarned
            if delta != 0, var c = customer {
                let newBalance = max(0, (c.points ?? 0) + delta)
                let entry = PointHistoryEntry(
                    id: UUID().uuidString,
                    type: .paymentEarn,
                    delta: delta,
                    balance: newBalance,
                    description: delta > 0 ? "예약 결제 적립" : "예약 결제 적립 조정",
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    relatedReservationId: reservation.id
                )
                c.points = newBalance
                c.pointHistories = [entry] + (c.pointHistories ?? [])
                _ = try await service.upsertCustomer(c)
            }
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
