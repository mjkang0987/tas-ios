import SwiftUI

/// 적립금 수동 조정 — 웹 고객 상세의 수동 적립/차감(manual_add/manual_subtract) 이식.
///
/// 적립/차감 금액과 사유를 입력해 고객의 `points`를 갱신하고 이력(`pointHistories`)을
/// 앞에 추가한다. 저장은 `upsertCustomer`(게스트=로컬). 결제 연동 자동 적립은 별도.
struct PointAdjustView: View {
    let customer: Customer
    var service: TASService = TASService()
    /// 저장 후: 상위(고객 목록) 리로드 + 상세 닫기.
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isAdd = true
    @State private var amount = 0
    @State private var reason = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var currentPoints: Int { customer.points ?? 0 }
    /// 차감은 보유 적립금을 넘지 않도록 클램프.
    private var delta: Int { isAdd ? amount : -min(amount, currentPoints) }
    private var resultPoints: Int { currentPoints + delta }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("구분", selection: $isAdd) {
                        Text("적립").tag(true)
                        Text("차감").tag(false)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("P").foregroundStyle(.secondary)
                    }
                    TextField("사유 (선택)", text: $reason)
                } header: {
                    Text("적립금 조정")
                } footer: {
                    Text("현재 \(currentPoints.formatted())P → 조정 후 \(resultPoints.formatted())P")
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("적립금 조정")
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
        }
    }

    private func save() async {
        if amount <= 0 { errorMessage = "금액을 입력해주세요."; return }
        isSaving = true
        defer { isSaving = false }

        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        let entry = PointHistoryEntry(
            id: UUID().uuidString,
            type: isAdd ? .manualAdd : .manualSubtract,
            delta: delta,
            balance: resultPoints,
            description: trimmed.isEmpty ? (isAdd ? "수동 적립" : "수동 차감") : trimmed,
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
