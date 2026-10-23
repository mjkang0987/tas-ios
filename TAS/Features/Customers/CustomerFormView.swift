import SwiftUI

/// 고객 등록/수정 폼 — 웹 `CustomerAddModal`(추가) + `CustomerDetail` 편집 규칙 이식.
///
/// 편집 가능한 필드는 웹과 동일하게 이름·연락처·메모 태그로 한정한다.
/// 적립금/이력/노트 등 폼이 다루지 않는 필드는 편집 시 기존 값을 보존한다.
/// 저장은 `upsertCustomer`로 게스트(로컬)·로그인(API)이 자동 분기된다.
struct CustomerFormView: View {
    let service: TASService
    /// 편집 대상. nil이면 신규 등록.
    var editing: Customer? = nil
    /// 신규 등록 시 부여할 id(max+1).
    var nextCustomerId: Int = 0
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var tel = ""
    @State private var memoTags: [CustomerMemoTag] = []
    @State private var newTagText = ""
    @State private var selectedColor = MemoTagEditor.colors[0].hex
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, tel }
    private static let telPattern = "^01[016789]\\d{7,8}$"

    var body: some View {
        NavigationStack {
            Form {
                Section("고객") {
                    TextField("이름", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .tel }
                    TextField("연락처 (01012345678)", text: $tel)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .tel)
                }

                memoTagSection

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(Color.dangerText) }
                }
            }
            .navigationTitle(editing == nil ? "고객 등록" : "고객 수정")
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

    // MARK: - 메모 태그

    private var memoTagSection: some View {
        Section("고객 메모") {
            MemoTagEditor(
                tags: memoTags,
                text: $newTagText,
                color: $selectedColor,
                onAdd: addTag,
                onRemove: { tag in memoTags.removeAll { $0.text == tag.text } }
            )
            .padding(.vertical, 4)
        }
    }

    private func addTag() {
        let result = MemoTagEditor.adding(newTagText, color: selectedColor, to: memoTags)
        errorMessage = result.error
        guard result.error == nil, result.tags.count != memoTags.count else { return }
        memoTags = result.tags
        newTagText = ""
    }

    // MARK: - 로직

    private func setup() {
        guard let editing else { return }
        name = editing.name
        tel = editing.tel
        memoTags = editing.memoTags ?? []
    }

    private func normalizeTel(_ s: String) -> String { s.filter(\.isNumber) }

    private func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "고객명을 입력해주세요." }
        let digits = normalizeTel(tel)
        // 편집 시 연락처 필수, 신규 시 있으면 형식 검증(웹 규칙).
        if editing != nil && digits.isEmpty { return "연락처를 입력해주세요." }
        if !digits.isEmpty && digits.range(of: Self.telPattern, options: .regularExpression) == nil {
            return "연락처 형식을 확인해주세요."
        }
        return nil
    }

    private func save() async {
        if let err = validate() { errorMessage = err; return }
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let digits = normalizeTel(tel)
            let tags = memoTags.isEmpty ? nil : memoTags
            let customer: Customer
            if var edited = editing {
                // 기존 값 보존 후 폼 필드만 덮어쓴다.
                edited.name = trimmedName
                edited.tel = digits
                edited.memoTags = tags
                customer = edited
            } else {
                customer = Customer(
                    id: nextCustomerId,
                    name: trimmedName,
                    tel: digits,
                    points: 0,
                    pointHistories: [],
                    memoTags: tags
                )
            }
            if editing != nil {
                try await service.updateCustomer(customer)
            } else {
                _ = try await service.createCustomer(customer)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
