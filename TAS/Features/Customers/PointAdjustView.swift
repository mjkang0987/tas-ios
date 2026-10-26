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
    /// 비어 있으면 nil — 웹처럼 빈 칸에 "금액 입력"이 보이게.
    @State private var amountInput: Int?
    private var amount: Int { amountInput ?? 0 }
    @State private var reason = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var currentPoints: Int { customer.points ?? 0 }
    /// 차감은 보유 적립금을 넘지 않도록 클램프.
    private var delta: Int { isAdd ? amount : -min(amount, currentPoints) }
    private var resultPoints: Int { currentPoints + delta }

    var body: some View {
        NavigationStack {
            // 웹 적립금 조정 — 현재 잔액, 이름 붙은 입력칸, 조정 후 잔액
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("현재 잔액 \(formatWon(currentPoints))")
                        .font(.tasBody.weight(.semibold)).foregroundStyle(Color.blueText)
                    Picker("구분", selection: $isAdd) {
                        Text("적립").tag(true)
                        Text("차감").tag(false)
                    }
                    .pickerStyle(.segmented)
                    FormField(label: "금액") {
                        HStack(spacing: 4) {
                            TextField("금액", value: $amountInput, format: .number, prompt: Text("금액 입력"))
                                .keyboardType(.numberPad)
                            Text("원").foregroundStyle(Color.textSecondary)
                        }
                    }
                    FormField(label: "사유 (선택)") {
                        TextField("사유", text: $reason, prompt: Text("예: 이벤트 적립"))
                    }
                    Text("현재 \(formatWon(currentPoints)) → 조정 후 \(formatWon(resultPoints))")
                        .font(.tasSmall).foregroundStyle(Color.textSecondary)
                    if let errorMessage {
                        Text(errorMessage).font(.tasMedium).foregroundStyle(Color.dangerText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("적립금 조정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandFill)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        if amount <= 0 { errorMessage = "금액을 입력해주세요."; return }
        guard let updated = PointAdjust.adjusted(customer, amount: amount, add: isAdd, reason: reason,
                                                 now: ISO8601DateFormatter().string(from: Date()), id: UUID().uuidString) else {
            errorMessage = "차감할 적립금이 없습니다."; return
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
