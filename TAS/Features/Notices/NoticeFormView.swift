import SwiftUI

/// 공지 추가/수정 폼 — 웹 NoticeManageSection 이식.
/// 분류·제목·내용 + '노출'(최대 3개). 저장은 create/update(게스트=로컬).
struct NoticeFormView: View {
    var editing: StoreNotice? = nil
    /// 이 공지를 뺀 노출 공지 수(노출 한도 검사).
    var otherVisibleCount: Int = 0
    let onSave: (StoreNotice) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var category: NoticeCategory = .notice
    @State private var title = ""
    @State private var bodyText = ""
    @State private var visible = true
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("공지") {
                    Picker("분류", selection: $category) {
                        ForEach(NoticeCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("제목", text: $title)
                    TextField("내용", text: $bodyText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Toggle("노출", isOn: $visible)
                        .disabled(!visible && !canShow)
                } footer: {
                    Text("노출을 켠 공지만 고객 예약 페이지에 보입니다 (최대 \(StoreNotice.maxVisible)개).")
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editing == nil ? "공지 추가" : "공지 수정")
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

    private var canShow: Bool {
        StoreNotice.canShow(wasVisible: editing?.visible ?? false, otherVisibleCount: otherVisibleCount)
    }

    private func setup() {
        guard let editing else {
            // 이미 한도만큼 노출 중이면 새 공지는 꺼진 채로 시작(토글도 비활성).
            visible = canShow
            return
        }
        category = editing.category
        title = editing.title
        bodyText = editing.body
        visible = editing.visible
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespaces)
        if trimmedTitle.isEmpty { errorMessage = "제목을 입력해주세요."; return }
        if trimmedBody.isEmpty { errorMessage = "내용을 입력해주세요."; return }
        if visible && !canShow {
            errorMessage = "노출은 최대 \(StoreNotice.maxVisible)개까지 가능합니다."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let notice = StoreNotice(
            id: editing?.id ?? UUID().uuidString,
            category: category,
            title: trimmedTitle,
            body: trimmedBody,
            visible: visible,
            pinned: editing?.pinned ?? false,
            createdAt: editing?.createdAt ?? ISO8601DateFormatter().string(from: Date())
        )
        if await onSave(notice) {
            dismiss()
        } else {
            errorMessage = "저장에 실패했습니다. 다시 시도해주세요."
        }
    }
}
