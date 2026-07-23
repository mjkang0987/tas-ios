import SwiftUI

/// 고객 상세 (읽기) — 웹 `/address` 상세에 대응하는 스켈레톤.
struct CustomerDetailView: View {
    let customer: Customer
    var stats: CustomersViewModel.VisitStats? = nil
    var reservations: [Reservation] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("기본 정보") {
                    LabeledContent("이름", value: customer.name)
                    LabeledContent("연락처", value: customer.formattedTel)
                    if let points = customer.points {
                        LabeledContent("적립금", value: "\(points.formatted())P")
                    }
                    if let first = customer.firstVisitDate, !first.isEmpty {
                        LabeledContent("첫 방문", value: first)
                    }
                }

                if let stats {
                    Section("방문 통계") {
                        HStack {
                            statCell("방문", stats.visits, .green)
                            Divider()
                            statCell("취소", stats.cancels, .gray)
                            Divider()
                            statCell("노쇼", stats.noshows, .red)
                        }
                    }
                }

                if let tags = customer.memoTags, !tags.isEmpty {
                    Section("메모 태그") {
                        FlowTags(tags: tags)
                    }
                }

                if hasNotes {
                    Section("노트") {
                        if let note = customer.allergyNote, !note.isEmpty {
                            noteRow("알레르기", note)
                        }
                        if let note = customer.preferenceNote, !note.isEmpty {
                            noteRow("선호", note)
                        }
                        if let note = customer.claimNote, !note.isEmpty {
                            noteRow("클레임", note)
                        }
                    }
                }

                if let histories = customer.pointHistories, !histories.isEmpty {
                    Section("적립금 이력") {
                        ForEach(histories) { PointHistoryRow(entry: $0) }
                    }
                }

                if !reservations.isEmpty {
                    Section("최근 예약") {
                        ForEach(reservations.prefix(10)) { CustomerReservationRow(reservation: $0) }
                    }
                }
            }
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var hasNotes: Bool {
        [customer.allergyNote, customer.preferenceNote, customer.claimNote]
            .contains { ($0?.isEmpty == false) }
    }

    private func noteRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(body)
        }
    }

    private func statCell(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CustomerReservationRow: View {
    let reservation: Reservation

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.service).font(.subheadline)
                Text("\(reservation.date) \(reservation.startTime)")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            StatusBadge(state: reservation.displayState)
        }
    }
}

private struct FlowTags: View {
    let tags: [CustomerMemoTag]

    var body: some View {
        // 단순 래핑 없이 세로 나열(간단 스켈레톤). 필요 시 Layout으로 개선.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { item in
                let tag = item.element
                HStack(spacing: 6) {
                    ColorDot(color: Color(hex: tag.color) ?? .gray, size: 10)
                    Text(tag.text)
                }
            }
        }
    }
}

private struct PointHistoryRow: View {
    let entry: PointHistoryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.label).font(.subheadline)
                Text(entry.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signed(entry.delta))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.delta >= 0 ? Color.blue : Color.red)
                Text("잔액 \(entry.balance.formatted())P").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func signed(_ value: Int) -> String {
        (value >= 0 ? "+" : "") + "\(value.formatted())P"
    }
}
