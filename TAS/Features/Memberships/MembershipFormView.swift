import SwiftUI

/// 회원권 상품 추가/수정 폼 — 웹 MembershipManageSection 이식.
/// 이름·횟수(0=무제한)·유효일수(0=무기한)·가격.
struct MembershipFormView: View {
    var editing: MembershipProduct? = nil
    let onSave: (MembershipProduct) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var totalCount = 0    // 0 = 무제한
    @State private var validDays = 0     // 0 = 무기한
    @State private var price = 0
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("회원권") {
                    TextField("회원권명", text: $name)
                    numberRow("횟수", value: $totalCount, unit: "회", zeroHint: "무제한")
                    numberRow("유효기간", value: $validDays, unit: "일", zeroHint: "무기한")
                    HStack {
                        Text("가격")
                        Spacer()
                        TextField("0", value: $price, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("원").foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editing == nil ? "회원권 등록" : "회원권 수정")
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

    private func numberRow(_ title: String, value: Binding<Int>, unit: String, zeroHint: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(zeroHint, value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func setup() {
        guard let e = editing else { return }
        name = e.name
        totalCount = e.totalCount ?? 0
        validDays = e.validDays ?? 0
        price = e.price
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { errorMessage = "회원권명을 입력해주세요."; return }
        isSaving = true
        defer { isSaving = false }
        let product = MembershipProduct(
            id: editing?.id ?? UUID().uuidString,
            name: trimmedName,
            totalCount: totalCount > 0 ? totalCount : nil,
            validDays: validDays > 0 ? validDays : nil,
            price: max(0, price),
            status: editing?.status ?? "active"
        )
        if await onSave(product) {
            dismiss()
        } else {
            errorMessage = "저장에 실패했습니다. 다시 시도해주세요."
        }
    }
}
