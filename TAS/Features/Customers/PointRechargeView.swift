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

    init(customer: Customer, rules: [RechargeRule], service: TASService = TASService(),
         onCompleted: @escaping () async -> Void) {
        self.customer = customer
        self.rules = rules
        self.service = service
        self.onCompleted = onCompleted
        // 웹처럼 첫 충전 규칙이 골라진 채로 연다(규칙이 없으면 직접 입력)
        _selectedRule = State(initialValue: rules.isEmpty ? nil : 0)
    }

    @Environment(\.dismiss) private var dismiss

    /// 선택한 규칙 index. nil이면 직접 입력.
    @State private var selectedRule: Int?
    /// 비어 있으면 nil — 웹처럼 빈 칸에 "충전금액"이 보이게.
    @State private var customInput: Int?
    private var customAmount: Int { customInput ?? 0 }
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
            // 웹 AddressCustomerRecharge — 현재 잔액, 충전 금액 고르기(규칙 + 직접입력), 결제수단
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("현재 잔액 \(formatWon(currentPoints))")
                        .font(.tasBody.weight(.semibold)).foregroundStyle(Color.blueText)
                    if !rules.isEmpty {
                        FormField(label: "충전 금액") {
                            SelectMenu(title: "충전 금액 선택", value: rule.map(Self.label) ?? "직접입력") {
                                Picker("충전 금액", selection: $selectedRule) {
                                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                                        Text(Self.label(rule)).tag(Optional(index))
                                    }
                                    Text("직접입력").tag(Int?.none)
                                }
                            }
                        }
                    }
                    if selectedRule == nil {
                        FormField(label: rules.isEmpty ? "충전 금액" : "직접 입력") {
                            HStack(spacing: 4) {
                                TextField("충전 금액", value: $customInput, format: .number, prompt: Text("충전금액"))
                                    .keyboardType(.numberPad)
                                Text("원").foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    FormField(label: "결제수단") {
                        SelectMenu(title: "충전 결제수단", value: paymentMethod.rawValue) {
                            Picker("결제수단", selection: $paymentMethod) {
                                ForEach(PaymentMethod.received, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("현재 \(formatWon(currentPoints)) → 충전 후 \(formatWon(resultPoints))")
                        Text("받은 금액 \(formatWon(paidAmount))이 매출로 잡힙니다.")
                    }
                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
                    if let errorMessage {
                        Text(errorMessage).font(.tasMedium).foregroundStyle(Color.dangerText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("적립금 충전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 웹 충전 버튼처럼 보라 채움
                    Button("충전") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandFill)
                        .disabled(isSaving || amount <= 0)
                }
            }
        }
    }

    /// 웹 충전 옵션 이름 — "기준금액 + 보너스".
    private static func label(_ rule: RechargeRule) -> String {
        "\(formatWon(rule.baseAmount)) + \(formatWon(rule.bonusAmount))"
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
