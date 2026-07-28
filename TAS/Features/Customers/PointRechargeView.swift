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
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var currentPoints: Int { customer.points ?? 0 }

    /// 충전액 — 규칙 선택 시 기준금액+보너스, 직접 입력 시 입력값.
    private var amount: Int {
        guard let selectedRule, rules.indices.contains(selectedRule) else { return max(0, customAmount) }
        let rule = rules[selectedRule]
        return rule.baseAmount + rule.bonusAmount
    }

    private var resultPoints: Int { currentPoints + amount }

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
                                        Text("+ \(rule.bonusAmount.formatted())P")
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
                        Text("P").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("직접 입력")
                } footer: {
                    Text("현재 \(currentPoints.formatted())P → 충전 후 \(resultPoints.formatted())P")
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
        guard amount > 0 else { errorMessage = "충전 금액을 입력해주세요."; return }
        isSaving = true
        defer { isSaving = false }

        let entry = PointHistoryEntry(
            id: UUID().uuidString,
            type: .recharge,
            delta: amount,
            balance: resultPoints,
            description: selectedRule == nil ? "적립금 직접 충전" : "적립금 기준 충전",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            relatedReservationId: nil
        )
        var updated = customer
        updated.points = resultPoints
        updated.pointHistories = [entry] + (customer.pointHistories ?? [])
        do {
            _ = try await service.upsertCustomer(updated)
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
