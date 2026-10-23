import SwiftUI

/// 적립금 충전 — 웹 `AddressCustomerRecharge` 이식.
///
/// 매장 설정의 **충전 규칙**(기준금액 + 보너스)을 골라 충전하거나 금액을 직접 입력한다.
/// 규칙을 고르면 `기준금액 + 보너스`가 통째로 적립되고 이력 유형은 `recharge`
/// (수동 적립/차감 `PointAdjustView`와 구분). 저장은 `upsertCustomer`(게스트=로컬).
struct PointRechargeView: View {
    let customer: Customer
    /// 매장 설정의 충전 규칙(기준금액 오름차순).
    let rules: [RechargeRule]
    var service: TASService = TASService()
    /// 저장 후: 상위(고객 목록) 리로드 + 상세 닫기.
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    /// 선택한 규칙 index. nil이면 직접 입력.
    @State private var selectedRule: Int?
    @State private var customAmount = 0
    /// 충전은 받은 돈이라 매출로 잡힌다 — 어떻게 받았는지(웹 `AddressCustomerRecharge` 와 같은 기본값 카드).
    @State private var paymentMethod: PaymentMethod = .card
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var currentPoints: Int { customer.points ?? 0 }

    private var rule: RechargeRule? { selectedRule.flatMap { rules.indices.contains($0) ? rules[$0] : nil } }
    private var amount: Int { PointRecharge.amount(rule: rule, custom: customAmount) }
    private var resultPoints: Int { currentPoints + amount }
    private var paidAmount: Int { PointRecharge.paid(rule: rule, custom: customAmount) }

    var body: some View {
        NavigationStack {
            Form {
                if !rules.isEmpty {
                    Section("충전 규칙") {
                        ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                            Button {
                                selectedRule = index
                            } label: {
                                HStack {
                                    Text(formatWon(rule.baseAmount))
                                    if rule.bonusAmount > 0 {
                                        Text("+ \(formatWon(rule.bonusAmount))")
                                            .font(.caption)
                                            .foregroundStyle(.tint)
                                    }
                                    Spacer()
                                    if selectedRule == index {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("0", value: $customAmount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: customAmount) { selectedRule = nil }
                        Text("원").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("직접 입력")
                } footer: {
                    Text("현재 \(formatWon(currentPoints)) → 충전 후 \(formatWon(resultPoints))")
                }

                Section {
                    Picker("결제수단", selection: $paymentMethod) {
                        ForEach(PaymentMethod.received, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    Text("받은 금액 \(formatWon(paidAmount))이 매출로 잡힙니다.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("적립금 충전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("충전") { Task { await save() } }
                        .disabled(isSaving || amount <= 0)
                }
            }
        }
    }

    private func save() async {
        guard let updated = PointRecharge.charged(customer, rule: rule, custom: customAmount, method: paymentMethod,
                                                  now: ISO8601DateFormatter().string(from: Date()), id: UUID().uuidString) else {
            errorMessage = "충전 금액을 입력해주세요."; return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updateCustomer(updated)
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
