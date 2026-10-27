import SwiftUI

/// 예약 변경 이력 — 웹 `ReservationHistoryLayer` 이식.
/// 각 이력 항목을 시간·전환 태그와 함께 필드 diff(이전 → 이후)로 보여준다.
struct ReservationHistoryView: View {
    @Environment(SessionStore.self) private var session
    private var labels: StoreLabels { session.labels }
    let entries: [ReservationHistoryEntry]     // 최신순
    var assigneeName: (Int?) -> String = { _ in "미지정" }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("변경 이력 없음", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Section {
                        let diffs = diffs(entry)
                        if diffs.isEmpty {
                            Text("세부 변경").font(.tasBody).foregroundStyle(Color.textSecondary)
                        } else {
                            ForEach(Array(diffs.enumerated()), id: \.offset) { _, d in
                                diffRow(d)
                            }
                        }
                    } header: {
                        HStack {
                            Text(tag(entry))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                            Spacer()
                            Text(KST.timestampLabel(entry.timestamp))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("변경 이력")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diffRow(_ d: (label: String, before: String, after: String)) -> some View {
        HStack(spacing: 8) {
            Text(d.label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 56, alignment: .leading)
            Text(d.before)
                .strikethrough()
                .foregroundStyle(Color.textSecondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Color.textTertiary)
            Text(d.after)
            Spacer()
        }
        .font(.tasBody)
    }

    // MARK: - 전환 태그 / diff

    private func tag(_ e: ReservationHistoryEntry) -> String {
        let b = e.before.status, a = e.after.status
        if a == .cancelled && b != .cancelled { return "취소" }
        if a == .noshow && b != .noshow { return "노쇼" }
        if a == .completed && b != .completed { return "예약완료" }
        if a == .active && (b == .cancelled || b == .noshow) { return "예약전환" }
        return "변경"
    }

    private func diffs(_ e: ReservationHistoryEntry) -> [(label: String, before: String, after: String)] {
        var out: [(label: String, before: String, after: String)] = []
        let b = e.before, a = e.after
        // 상태 전환
        if a.status == .cancelled && b.status != .cancelled {
            out.append((label: "상태", before: "예약", after: "취소"))
        } else if a.status == .noshow && b.status != .noshow {
            out.append((label: "상태", before: "예약", after: "노쇼"))
        } else if a.status == .completed && b.status != .completed {
            out.append((label: "상태", before: "예약", after: "완료"))
        } else if a.status == .active && (b.status == .cancelled || b.status == .noshow) {
            out.append((label: "상태", before: b.status == .cancelled ? "취소" : "노쇼", after: "예약"))
        }
        // 필드 변경
        if b.date != a.date { out.append((label: "날짜", before: b.date, after: a.date)) }
        if b.startTime != a.startTime { out.append((label: "시작시간", before: b.startTime, after: a.startTime)) }
        if b.endTime != a.endTime { out.append((label: "종료시간", before: b.endTime, after: a.endTime)) }
        if b.service != a.service { out.append((label: "\(labels.service)", before: b.service, after: a.service)) }
        if (b.assigneeId ?? 0) != (a.assigneeId ?? 0) {
            out.append((label: "\(labels.assignee)", before: assigneeName(b.assigneeId), after: assigneeName(a.assigneeId)))
        }
        if (b.price ?? 0) != (a.price ?? 0) {
            out.append((label: "가격", before: formatWon(b.price ?? 0), after: formatWon(a.price ?? 0)))
        }
        // 웹 reservationDetailUtils 와 같은 두 칸 — 빠져 있어 바꿔도 이력에 안 남았다
        if (b.memo ?? "") != (a.memo ?? "") {
            out.append((label: "요청사항", before: b.memo ?? "", after: a.memo ?? ""))
        }
        // 경로가 없던 옛 예약은 전화예약으로 본다(폼 기본값과 같게) — 안 그러면 안 바꿔도 '→ 전화예약'이 잡힌다
        let bc = (b.channel ?? .phone).rawValue, ac = (a.channel ?? .phone).rawValue
        if bc != ac { out.append((label: "예약경로", before: bc, after: ac)) }
        return out
    }
}
