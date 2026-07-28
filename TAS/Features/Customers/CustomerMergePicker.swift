import SwiftUI

/// 고객 병합 대상 선택 — 웹 고객 병합 흐름 이식.
/// `source`(현재 고객)를 선택한 대상 고객으로 합친다. source의 예약·적립금·이력·메모는
/// 대상으로 이동하고 source는 삭제된다. 저장은 mergeCustomers(게스트=로컬).
struct CustomerMergePicker: View {
    let source: Customer
    let candidates: [Customer]          // source 제외 후보
    /// 고객 id → 예약 건수. 이름·연락처만으로는 동명이인이나 마스킹된 이름(네이버 유입 `*`)을
    /// 구분할 수 없어 판단 근거를 함께 보여준다(웹 병합 미리보기 이식).
    var reservationCounts: [Int: Int] = [:]
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
                                    Text(metaText(for: customer)).font(.caption2).foregroundStyle(.secondary)
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

    /// "예약 3건 · 적립 12,000P" — 기준 고객을 고를 판단 근거.
    private func metaText(for customer: Customer) -> String {
        let count = reservationCounts[customer.id] ?? 0
        return "예약 \(count)건 · 적립 \((customer.points ?? 0).formatted())P"
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private var confirmMessage: String {
        guard let target else { return "" }
        // 웹 병합 미리보기처럼 삭제될 쪽/남을 쪽의 규모를 나란히 보여준다.
        // 기준 고객의 이름·연락처가 남으므로 잘못 고르면 틀린 번호가 유지된다.
        return """
        삭제: \(source.name) (\(metaText(for: source)))
        기준: \(target.name) (\(metaText(for: target)))

        \(source.name)의 예약·적립금·메모가 \(target.name)(으)로 이동하고 \(source.name)은(는) 삭제됩니다. 되돌릴 수 없습니다.
        """
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
