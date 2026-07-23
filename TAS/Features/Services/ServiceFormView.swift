import SwiftUI

/// 서비스(시술) 추가/수정 폼 — 웹 `ServiceManageSection` 이식.
///
/// 필드: 이름 · 카테고리(기존 선택 또는 새로 추가) · 소요시간(분) · 가격(원).
/// 이름은 예약이 참조하는 식별자라 **수정 시 고정**(변경이 필요하면 삭제 후 재등록).
/// 저장은 상위 목록에 name 기준 upsert 후 전체 PUT(웹 일괄 저장 모델).
struct ServiceFormView: View {
    var editing: ServiceItem? = nil
    let existingCategories: [String]
    /// 편집한 서비스를 넘기고 저장 성공 여부(Bool)를 돌려받는다.
    let onSave: (ServiceItem) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = ""
    @State private var newCategory = ""
    @State private var useNewCategory = false
    @State private var duration = 30
    @State private var price = 0
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("서비스") {
                    if isEditing {
                        LabeledContent("이름", value: name)
                    } else {
                        TextField("서비스명", text: $name)
                    }
                }

                Section("카테고리") {
                    if !existingCategories.isEmpty {
                        Picker("카테고리", selection: categorySelection) {
                            ForEach(existingCategories, id: \.self) { Text($0).tag($0) }
                            Text("+ 새 카테고리").tag(Self.newCategoryTag)
                        }
                    }
                    if useNewCategory || existingCategories.isEmpty {
                        TextField("새 카테고리명", text: $newCategory)
                    }
                }

                Section("가격·시간") {
                    HStack {
                        Text("가격")
                        Spacer()
                        TextField("0", value: $price, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("원").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("소요시간")
                        Spacer()
                        TextField("30", value: $duration, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("분").foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "서비스 수정" : "서비스 추가")
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

    /// "+ 새 카테고리" 선택을 sentinel 태그로 표현하는 Picker 바인딩.
    private static let newCategoryTag = "\u{0}__new__"
    private var categorySelection: Binding<String> {
        Binding(
            get: { useNewCategory ? Self.newCategoryTag : category },
            set: { value in
                if value == Self.newCategoryTag {
                    useNewCategory = true
                } else {
                    useNewCategory = false
                    category = value
                }
            }
        )
    }

    private func setup() {
        if let editing {
            name = editing.name
            category = editing.category
            duration = editing.durationMinutes
            price = editing.price
        } else {
            category = existingCategories.first ?? ""
            useNewCategory = existingCategories.isEmpty
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { errorMessage = "서비스명을 입력해주세요."; return }
        let resolvedCategory = (useNewCategory || existingCategories.isEmpty)
            ? newCategory.trimmingCharacters(in: .whitespaces)
            : category.trimmingCharacters(in: .whitespaces)
        if resolvedCategory.isEmpty { errorMessage = "카테고리를 선택하거나 새로 입력해주세요."; return }

        isSaving = true
        defer { isSaving = false }
        let item = ServiceItem(
            name: trimmedName,
            durationMinutes: max(0, duration),
            category: resolvedCategory,
            price: max(0, price),
            nameI18n: editing?.nameI18n
        )
        if await onSave(item) {
            dismiss()
        } else {
            errorMessage = "저장에 실패했습니다. 다시 시도해주세요."
        }
    }
}
