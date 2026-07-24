import Foundation

/// 예약 시간 겹침 판정 — 담당자 중복 예약(가용성) 체크·타임라인 클러스터 공용.
///
/// 색·라벨·포맷처럼 화면마다 복붙하지 않고 한 곳에 둔다(CLAUDE.md UI 컨벤션).
/// 예약폼의 겹침 경고와 `DayTimelineView`의 시간 파싱이 이 유틸을 공유한다.
enum ReservationOverlap {
    /// "HH:mm" → 자정 기준 분. 형식 오류 시 nil.
    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// 두 [start, end) 분 구간이 실제로 겹치는가(경계만 맞닿는 건 겹침 아님).
    static func intervalsOverlap(_ aStart: Int, _ aEnd: Int, _ bStart: Int, _ bEnd: Int) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    /// 후보 시간대가 같은 담당자의 기존 예약들과 겹치는 건들(시작시간 순).
    ///
    /// 규칙: 같은 날짜 + 같은 담당자 + 취소·노쇼 제외 + 자기 자신(`excludingId`) 제외.
    /// 담당자가 없으면(nil) 중복의 의미가 없으므로 빈 배열.
    static func conflicts(
        date: String,
        startTime: String,
        endTime: String,
        assigneeId: Int?,
        among reservations: [Reservation],
        excludingId: Int? = nil
    ) -> [Reservation] {
        guard let assigneeId,
              let start = minutes(startTime),
              let end = minutes(endTime),
              end > start else { return [] }

        return reservations.filter { r in
            guard r.id != excludingId,
                  r.assigneeId == assigneeId,
                  r.date == date,
                  r.status != .cancelled, r.status != .noshow,
                  let rStart = minutes(r.startTime),
                  let rEnd = minutes(r.endTime),
                  rEnd > rStart else { return false }
            return intervalsOverlap(start, end, rStart, rEnd)
        }
        .sorted { $0.startTime < $1.startTime }
    }
}
