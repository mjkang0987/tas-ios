import SwiftUI

/// 결제완료/결제수단 변경 시트 — 웹 `ReservationDetailPaymentLayer` 이식(핵심).
///
/// 결제 항목(수단+금액)을 1개 이상 입력해 `paymentEntries`로 저장하고 결제 완료로 표시한다.
/// 저장은 PUT `updateReservation`(게스트=로컬). 결제 시 적립률 자동 적립과, 적립금(`.points`)
/// 결제분의 고객 잔액 차감(사용 이력)을 함께 반영한다.
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
    private var nonPointTotal: Int { PointMath.nonPointTotal(in: entries) }
    private var defaultAward: Int { PointMath.earnedAmount(base: nonPointTotal, rate: pointRate) }

    /// 이번 결제에서 적립금(포인트)으로 결제한 금액.
    private var pointsUsedNow: Int { PointMath.pointsUsed(in: entries) }
    /// 저장 전 이 예약이 이미 사용한 적립금(수정 시 차액만 반영하기 위함).
    private var previouslyUsed: Int { PointMath.pointsUsed(in: reservation.paymentEntries ?? []) }
    /// 이 예약에 사용 가능한 적립금 = 고객 보유분 + 기존에 이 예약이 사용한 분(재편집 허용).
    private var availablePoints: Int { (customer?.points ?? 0) + previouslyUsed }

    var body: some View {
        NavigationStack {
            // 웹 결제 레이어 — 안내·보유 적립금, 서비스 금액, [결제종류 | 금액 | 삭제] 줄, 결제수단 추가, 적립 적용
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("결제 종류와 금액을 입력해 주세요.")
                            .font(.tasMedium).foregroundStyle(Color.textSecondary)
                        Spacer(minLength: 0)
                        if let customer {
                            Text("보유 적립금 \(formatWon(customer.points ?? 0))")
                                .font(.tasSmall.weight(.semibold))
                                .foregroundStyle(Color.warningText)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 28)
                                .background(Color.warningText.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("서비스 금액 \(formatWon(reservation.price ?? 0))")
                        .font(.tasBody.weight(.semibold))

                    // 큰 글자에서는 세 칸을 나란히 두면 잘린다 — 위아래로
                    let row = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(spacing: 8))
                    ForEach(entries.indices, id: \.self) { i in
                        row {
                            FormField(label: nil) {
                                SelectMenu(title: "결제종류 \(i + 1)", value: entries[i].method.rawValue) {
                                    Picker("결제종류", selection: entryBinding(i, \.method, fallback: .card)) {
                                        ForEach(Self.methods, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                }
                            }
                            FormField(label: nil) {
                                HStack(spacing: 4) {
                                    TextField("금액", value: entryBinding(i, \.amount, fallback: 0), format: .number)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .accessibilityLabel("결제 금액 \(i + 1)")
                                    Text("원").foregroundStyle(Color.textSecondary)
                                }
                            }
                            // 최소 1개는 유지. 빠르게 두 번 누르면 다시 그리기 전 같은 i 가 또 올 수 있어 범위도 본다.
                            Button("삭제") {
                                if entries.indices.contains(i), entries.count > 1 { entries.remove(at: i) }
                            }
                                .buttonStyle(.action())
                                .disabled(entries.count <= 1)
                                .accessibilityLabel("결제 \(i + 1) 삭제")
                        }
                    }
                    Button("결제수단 추가") {
                        entries.append(PaymentEntry(method: .card, amount: 0))
                    }
                    .buttonStyle(.action())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("합계 \(formatWon(enteredTotal))")
                            .foregroundStyle(enteredTotal == (reservation.price ?? 0) ? Color.textSecondary : Color.warningText)
                        if pointsUsedNow > 0 || (customer?.points ?? 0) > 0 {
                            // 위 알약은 고객 잔액, 여기는 이 예약에 쓸 수 있는 몫(잔액 + 이 예약이 이미 쓴 적립금)
                            Text("적립금 사용 \(formatWon(pointsUsedNow)) · 사용 가능 \(formatWon(availablePoints))")
                                .foregroundStyle(pointsUsedNow > availablePoints ? Color.dangerText : Color.textSecondary)
                        }
                    }
                    .font(.tasSmall)

                    if pointRate > 0 || (reservation.pointEarned ?? 0) > 0 {
                        // 웹: 체크 + 적립 금액 칸(끄면 칸이 잠긴다)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("적립 적용", isOn: $pointAwardEnabled)
                                .font(.tasBody)
                                .tint(.brandFill)
                            FormField(label: nil) {
                                HStack(spacing: 4) {
                                    TextField("적립 금액", value: $pointAward, format: .number)
                                        .keyboardType(.numberPad)
                                        .accessibilityLabel("적립 금액")
                                    Text("원").foregroundStyle(Color.textSecondary)
                                }
                            }
                            .disabled(!pointAwardEnabled)
                            .opacity(pointAwardEnabled ? 1 : 0.5)
                            if pointAwardEnabled, pointRate > 0 {
                                Text("적립률 \(pointRate)% 기준 \(formatWon(nonPointTotal))의 \(formatWon(defaultAward))")
                                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.tasMedium).foregroundStyle(Color.dangerText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(reservation.hasCompletedPayment ? "결제수단 변경" : "결제완료")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 웹 저장 버튼처럼 보라 채움
                    Button("저장") { Task { await save() } }
                        .primaryToolbarButton()
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setup)
        }
    }

    /// 줄을 지운 뒤에도 포커스가 풀리며 그 줄 칸이 값을 다시 쓸 수 있다 — 범위 밖이면 버린다(안 그러면 Index out of range).
    private func entryBinding<T>(_ i: Int, _ key: WritableKeyPath<PaymentEntry, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { entries.indices.contains(i) ? entries[i][keyPath: key] : fallback },
            set: { if entries.indices.contains(i) { entries[i][keyPath: key] = $0 } }
        )
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
        // 적립금 사용 검증: 고객 정보가 있어야 하고, 보유 잔액을 넘길 수 없다.
        let newUsed = pointsUsedNow
        if newUsed > 0 && customer == nil {
            errorMessage = "적립금 사용은 고객 정보가 필요합니다."
            return
        }
        if newUsed > availablePoints {
            errorMessage = "적립금 잔액이 부족합니다. (사용 \(formatWon(newUsed)) / 사용 가능 \(formatWon(availablePoints)))"
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

            // 고객 적립금 반영: 사용(차감)·적립을 기존분 대비 차액만큼만 조정(PointLedger).
            if let c = customer,
               let updated = PointLedger.apply(
                to: c, previousEarned: previousEarned, newEarned: newEarned,
                previousUsed: previouslyUsed, newUsed: newUsed,
                reservationId: reservation.id,
                now: ISO8601DateFormatter().string(from: Date()), makeId: { UUID().uuidString }) {
                try await service.updateCustomer(updated)
            }
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
