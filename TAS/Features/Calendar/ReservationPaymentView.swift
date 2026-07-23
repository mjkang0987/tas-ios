import SwiftUI

/// 결제완료/결제수단 변경 시트 — 웹 `ReservationDetailPaymentLayer` 이식(핵심).
///
/// 결제 항목(수단+금액)을 1개 이상 입력해 `paymentEntries`로 저장하고 결제 완료로 표시한다.
/// 저장은 PUT `updateReservation`(게스트=로컬). 적립금 자동 적립은 다음 단계.
struct ReservationPaymentView: View {
    let reservation: Reservation
    var service: TASService = TASService()
    /// 저장 완료 후: 상위(캘린더) 리로드 + 상세 닫기.
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var entries: [PaymentEntry] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// 선택 가능한 결제수단(웹 PAYMENT_METHOD 순서).
    private static let methods: [PaymentMethod] = [
        .cash, .cashReceipt, .card, .naverPay, .localCurrency,
        .localCurrencyReceipt, .giftCard, .points, .discount, .naverDeposit
    ]

    private var enteredTotal: Int { entries.map(\.amount).reduce(0, +) }

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
        do {
            _ = try await service.updateReservation(prev: reservation, updated: updated)
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
