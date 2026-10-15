import Foundation

/// 겹친 예약을 레인(세로 칸)으로 나누는 공용 배치 계산.
///
/// 일 타임라인과 주 타임라인이 같은 규칙을 쓰도록 한 곳에 둔다(CLAUDE.md UI 컨벤션).
/// 좌표(pt)는 계산하지 않는다 — 분 단위와 레인 번호만 내고, 높이·폭 환산은 각 뷰가 한다.
/// 일 뷰는 폭을 화면에 맞춰 나누고, 주 뷰는 레인 수만큼 칼럼을 넓히기 때문이다.
enum TimelineLayout {
    /// 이 높이(pt) 이하의 블록은 내용을 세로 가운데에 놓는다.
    /// 그보다 길면 위에 붙인다 — 가운데로 내리면 시작시간 글자가 제 눈금에서 멀어져,
    /// 2시간짜리 블록에서는 "14:30" 이 15시 선 옆에 가 있는 것처럼 읽힌다.
    /// 일·주·3일 뷰가 같은 기준을 써야 화면마다 다르게 보이지 않는다.
    static let centerContentMaxHeight: CGFloat = 60

    struct Placed {
        let reservation: Reservation
        /// 자정 기준 분.
        let startMin: Int
        let endMin: Int
        /// `laneCount`칸 중 `laneIndex`번째.
        let laneIndex: Int
        let laneCount: Int
    }

    /// 시작시각 순으로 겹침 클러스터를 묶고, 클러스터 안에서 **끝난 레인을 재사용**하는 그리디 배치.
    ///
    /// 겹침은 전이적으로 이어붙인다 — A와 B가 겹치고 B와 C가 겹치면 A가 C와 안 겹쳐도 한 묶음이다.
    /// 그래야 한 묶음 안에서 레인 번호가 유일해진다.
    /// 시간 형식이 깨졌거나 끝이 시작보다 빠른 예약은 배치할 자리가 없어 제외한다.
    static func place(_ reservations: [Reservation]) -> [Placed] {
        let events = reservations.compactMap { r -> (r: Reservation, s: Int, e: Int)? in
            guard let s = ReservationOverlap.minutes(r.startTime),
                  let e = ReservationOverlap.minutes(r.endTime), e > s else { return nil }
            return (r, s, e)
        }.sorted { $0.s < $1.s }

        var result: [Placed] = []
        var i = 0
        while i < events.count {
            var clusterEnd = events[i].e
            var j = i + 1
            while j < events.count && events[j].s < clusterEnd {
                clusterEnd = max(clusterEnd, events[j].e)
                j += 1
            }
            let cluster = Array(events[i..<j])

            var laneEnds: [Int] = []
            var lanes: [Int] = []
            for ev in cluster {
                if let lane = laneEnds.firstIndex(where: { $0 <= ev.s }) {
                    laneEnds[lane] = ev.e
                    lanes.append(lane)
                } else {
                    laneEnds.append(ev.e)
                    lanes.append(laneEnds.count - 1)
                }
            }
            let laneCount = max(1, laneEnds.count)
            for (idx, ev) in cluster.enumerated() {
                result.append(Placed(
                    reservation: ev.r,
                    startMin: ev.s,
                    endMin: ev.e,
                    laneIndex: lanes[idx],
                    laneCount: laneCount
                ))
            }
            i = j
        }
        return result
    }

    /// 그날 가장 많이 겹친 수. 주 뷰가 칼럼 폭을 정하는 데 쓴다(겹치지 않으면 1).
    static func maxLanes(_ placed: [Placed]) -> Int {
        placed.map(\.laneCount).max() ?? 1
    }
}
