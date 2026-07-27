import SwiftUI

/// 쿠폰 상품 추가/수정 폼 — 웹 CouponManageSection 이식.
/// 이름·할인유형(정액/정률)·할인값 + 최대할인(정률)·최소주문·유효일수·코드.
struct CouponFormView: View {
    var editing: CouponProduct? = nil
    let onSave: (CouponProduct) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var discountType: CouponDiscountType = .amount
    @State private var discountValue = 0
    @State private var maxDiscount = 0        // 0 = 없음
    @State private var minOrderAmount = 0     // 0 = 없음
    @State private var validDays = 0          // 0 = 무기한
    @State private var code = ""              // 빈값 = 직접발급
    @State private var oncePerCustomer = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("쿠폰") {
                    TextField("쿠폰명", text: $name)
                    Picker("할인 유형", selection: $discountType) {
                        ForEach(CouponDiscountType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("할인값")
                        Spacer()
                        TextField("0", value: $discountValue, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text(discountType == .amount ? "원" : "%").foregroundStyle(.secondary)
                    }
                    if discountType == .rate {
                        numberRow("최대 할인액", value: $maxDiscount, unit: "원", zeroHint: "없음")
                    }
                }

                Section {
                    numberRow("최소 주문금액", value: $minOrderAmount, unit: "원", zeroHint: "없음")
                    numberRow("유효기간", value: $validDays, unit: "일", zeroHint: "무기한")
                    TextField("코드 (비우면 직접발급 전용)", text: $code)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    Toggle("고객당 1장", isOn: $oncePerCustomer)
                } header: {
                    Text("조건")
                } footer: {
                    if oncePerCustomer {
                        Text("미사용 쿠폰을 보유한 고객에게는 재발급되지 않습니다. (사용·만료 후에는 다시 발급 가능)")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editing == nil ? "쿠폰 등록" : "쿠폰 수정")
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
        discountType = e.discountType
        discountValue = e.discountValue
        maxDiscount = e.maxDiscount ?? 0
        minOrderAmount = e.minOrderAmount ?? 0
        validDays = e.validDays ?? 0
        code = e.code ?? ""
        oncePerCustomer = e.oncePerCustomer
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { errorMessage = "쿠폰명을 입력해주세요."; return }
        if discountValue <= 0 { errorMessage = "할인값을 입력해주세요."; return }
        if discountType == .rate && !(1...100).contains(discountValue) {
            errorMessage = "정률 할인은 1~100% 사이여야 합니다."; return
        }
        isSaving = true
        defer { isSaving = false }
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        let product = CouponProduct(
            id: editing?.id ?? UUID().uuidString,
            name: trimmedName,
            discountType: discountType,
            discountValue: discountValue,
            maxDiscount: discountType == .rate && maxDiscount > 0 ? maxDiscount : nil,
            minOrderAmount: minOrderAmount > 0 ? minOrderAmount : nil,
            validDays: validDays > 0 ? validDays : nil,
            code: trimmedCode.isEmpty ? nil : trimmedCode,
            oncePerCustomer: oncePerCustomer,
            status: editing?.status ?? "active"
        )
        if await onSave(product) {
            dismiss()
        } else {
            errorMessage = "저장에 실패했습니다. 다시 시도해주세요."
        }
    }
}
