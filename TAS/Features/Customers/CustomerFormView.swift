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
    @State private var selectedColor = CustomerFormView.MEMO_TAG_COLORS[0]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, tel, tag }

    /// 웹 MEMO_TAG_COLORS.
    static let MEMO_TAG_COLORS = ["#4285F4", "#34A853", "#EA4335", "#FBBC04", "#FF6D01", "#46BDC6", "#9334E6", "#E91E8C"]
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
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
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
            if !memoTags.isEmpty {
                // 등록된 태그: 색 점 + 텍스트 + 삭제.
                ForEach(Array(memoTags.enumerated()), id: \.offset) { item in
                    HStack(spacing: 8) {
                        ColorDot(color: Color(hex: item.element.color) ?? .gray)
                        Text(item.element.text)
                        Spacer()
                        Button {
                            memoTags.remove(at: item.offset)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 색 선택 팔레트.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.MEMO_TAG_COLORS, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if hex == selectedColor {
                                    Circle().strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                            .onTapGesture { selectedColor = hex }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                TextField("메모 태그 입력", text: $newTagText)
                    .focused($focusedField, equals: .tag)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                Button("추가", action: addTag)
                    .buttonStyle(.borderless)
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        let text = newTagText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if memoTags.contains(where: { $0.text == text }) {
            errorMessage = "같은 메모 태그가 이미 있습니다."
            return
        }
        memoTags.append(CustomerMemoTag(text: text, color: selectedColor))
        newTagText = ""
        errorMessage = nil
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
            _ = try await service.upsertCustomer(customer)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
