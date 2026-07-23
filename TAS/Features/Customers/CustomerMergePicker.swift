import SwiftUI

/// 고객 병합 대상 선택 — 웹 고객 병합 흐름 이식.
/// `source`(현재 고객)를 선택한 대상 고객으로 합친다. source의 예약·적립금·이력·메모는
/// 대상으로 이동하고 source는 삭제된다. 저장은 mergeCustomers(게스트=로컬).
struct CustomerMergePicker: View {
    let source: Customer
    let candidates: [Customer]          // source 제외 후보
    var service: TASService = TASService()
    /// 병합 완료 후: 상위 리로드 + 상세 닫기.
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var target: Customer?
    @State private var isMerging = false
    @State private var errorMessage: String?

    private var filtered: [Customer] {
        let all = candidates.sorted { $0.name < $1.name }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let digits = q.filter(\.isNumber)
        return all.filter { $0.name.localizedCaseInsensitiveContains(q) || (!digits.isEmpty && $0.tel.contains(digits)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView("합칠 고객 없음", systemImage: "person.2.slash")
                } else {
                    List(filtered) { customer in
                        Button {
                            target = customer
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(customer.name).font(.subheadline.weight(.medium))
                                    Text(customer.formattedTel).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .searchable(text: $searchText, prompt: "합칠 대상 고객")
                }
            }
            .navigationTitle("\(source.name) 합치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .disabled(isMerging)
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding()
                }
            }
            .confirmationDialog(confirmMessage, isPresented: confirmBinding, titleVisibility: .visible) {
                if let target {
                    Button("\(target.name)(으)로 합치기", role: .destructive) {
                        Task { await merge(into: target) }
                    }
                }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private var confirmMessage: String {
        guard let target else { return "" }
        return "\(source.name)의 예약·적립금·메모가 \(target.name)(으)로 이동하고 \(source.name)은(는) 삭제됩니다. 되돌릴 수 없습니다."
    }

    private func merge(into target: Customer) async {
        isMerging = true
        errorMessage = nil
        do {
            _ = try await service.mergeCustomers(sourceId: source.id, targetId: target.id)
            await onCompleted()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isMerging = false
    }
}
