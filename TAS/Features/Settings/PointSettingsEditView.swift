import SwiftUI

/// 적립금 설정 — 웹 PointSettingsTab 이식(적립률·충전 규칙).
///
/// 결제 시 적립률(%) 적립 사용 여부·비율, 선불 충전 규칙(충전액→보너스)을 편집한다.
/// 저장은 PUT /api/store(게스트=로컬). 매장 적립금 기능(usePointSystem) 켜졌을 때 노출.
struct PointSettingsEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var service = TASService()

    @State private var enableServiceRate = false
    @State private var serviceRate = 0
    @State private var enableRecharge = false
    @State private var rules: [RechargeRule] = []
    @State private var newBase = 0
    @State private var newBonus = 0
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("결제 시 적립 사용", isOn: $enableServiceRate)
                    if enableServiceRate {
                        HStack {
                            Text("적립률")
                            Spacer()
                            TextField("0", value: $serviceRate, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("적립률")
                } footer: {
                    if enableServiceRate {
                        Text("결제 금액의 \(serviceRate)%가 적립금으로 쌓입니다. (적립금 사용 결제분 제외)")
                    }
                }

                Section {
                    Toggle("선불 충전 사용", isOn: $enableRecharge)
                    if enableRecharge {
                        ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                            HStack {
                                Text(formatWon(rule.baseAmount))
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text("+\(rule.bonusAmount.formatted())P").foregroundStyle(.tint)
                                Spacer()
                            }
                        }
                        .onDelete { rules.remove(atOffsets: $0) }
                        HStack {
                            TextField("충전액", value: $newBase, format: .number).keyboardType(.numberPad)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            TextField("보너스", value: $newBonus, format: .number).keyboardType(.numberPad)
                            Button("추가", action: addRule).buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("충전 규칙")
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("적립금 설정")
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

    private func addRule() {
        guard newBase > 0 else { return }
        rules.append(RechargeRule(baseAmount: newBase, bonusAmount: max(0, newBonus)))
        rules.sort { $0.baseAmount < $1.baseAmount }
        newBase = 0
        newBonus = 0
    }

    private func setup() {
        let p = session.currentStore?.pointSettings ?? PointSettings()
        enableServiceRate = p.enableServiceRate
        serviceRate = p.serviceRate
        enableRecharge = p.enableRecharge
        rules = p.rechargeRules
    }

    private func save() async {
        if enableServiceRate && !(0...100).contains(serviceRate) {
            errorMessage = "적립률은 0~100% 사이여야 합니다."
            return
        }
        guard let current = session.currentStore else { errorMessage = "매장 정보를 불러오지 못했습니다."; return }
        isSaving = true
        defer { isSaving = false }
        let settings = PointSettings(
            enableServiceRate: enableServiceRate,
            enableRecharge: enableRecharge,
            serviceRate: max(0, serviceRate),
            rechargeRules: rules
        )
        do {
            let updated = try await service.updatePointSettings(current: current, pointSettings: settings)
            session.currentStore = updated
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
