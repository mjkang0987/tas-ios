import Foundation

/// 예약 필드 변경(이전 → 이후) — 웹 `getChangedFields`. 변경 이력과 예약 변경 확인이 같이 쓴다.
enum ReservationDiff {
    struct Item: Equatable {
        var label: String
        var before: String
        var after: String
    }

    static func fields(before b: Reservation, after a: Reservation, labels: StoreLabels,
                       assigneeName: (Int?) -> String) -> [Item] {
        var out: [Item] = []
        if b.date != a.date { out.append(Item(label: "날짜", before: b.date, after: a.date)) }
        if b.startTime != a.startTime { out.append(Item(label: "시작시간", before: b.startTime, after: a.startTime)) }
        if b.endTime != a.endTime { out.append(Item(label: "종료시간", before: b.endTime, after: a.endTime)) }
        if b.service != a.service { out.append(Item(label: labels.service, before: b.service, after: a.service)) }
        if (b.assigneeId ?? 0) != (a.assigneeId ?? 0) {
            out.append(Item(label: labels.assignee, before: assigneeName(b.assigneeId), after: assigneeName(a.assigneeId)))
        }
        if (b.price ?? 0) != (a.price ?? 0) {
            out.append(Item(label: "가격", before: formatWon(b.price ?? 0), after: formatWon(a.price ?? 0)))
        }
        // 웹 reservationDetailUtils 와 같은 두 칸 — 빠져 있어 바꿔도 이력에 안 남았다
        if (b.memo ?? "") != (a.memo ?? "") {
            out.append(Item(label: "요청사항", before: b.memo ?? "", after: a.memo ?? ""))
        }
        // 경로가 없던 옛 예약은 전화예약으로 본다(폼 기본값과 같게) — 안 그러면 안 바꿔도 '→ 전화예약'이 잡힌다
        let bc = (b.channel ?? .phone).rawValue, ac = (a.channel ?? .phone).rawValue
        if bc != ac { out.append(Item(label: "예약경로", before: bc, after: ac)) }
        return out
    }

    /// 시작이 지금(KST)보다 앞인가 — 웹 `isPastTime`, 변경 확인 문구를 고른다.
    static func isPast(date: String, startTime: String, now: Date) -> Bool {
        let f = DateFormatter()
        f.timeZone = KST.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(date) \(startTime)" < f.string(from: now)
    }
}
