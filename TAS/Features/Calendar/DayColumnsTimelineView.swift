import SwiftUI

/// 날짜 칼럼 타임라인 — 시간축 하나에 날짜 칼럼 N개. 주(7일)·3일이 함께 쓴다.
/// 웹 `/week`·`/three` 와 같은 정보구조다.
///
/// **겹친 예약을 접지 않는다.** 웹은 칸 폭이 고정이라 `N건예약`으로 접지만, 여기선
/// 가로 스크롤이 폭을 흡수하므로 그 날 칼럼만 겹친 수만큼 넓혀 전부 보여준다.
/// 그래서 칼럼 폭이 날마다 다르다 — 바쁜 날이 넓다.
///
/// 블록은 고객명만 쓴다. 시술·담당자는 색이 말하고, 좁은 칸에서는 누가 오는지만 읽히면 된다.
struct DayColumnsTimelineView: View {
    let dayKeys: [String]                       // "YYYY-MM-DD" — 주는 7개(월~일), 3일은 기준일부터 3개
    let todayKey: String
    let startHour: Int
    let endHour: Int
    var reservations: (String) -> [Reservation] = { _ in [] }
    var header: (String, Int) -> String = { key, _ in key }
    var closedKind: (String) -> StoreClosedKind? = { _ in nil }
    var customerName: (Int) -> String = { "고객 #\($0)" }
    var color: (Reservation) -> Color = { _ in .accentColor }
    var onTap: (Reservation) -> Void = { _ in }

    private let hourHeight: CGFloat = 56
    private let gutterWidth: CGFloat = 40
    private let laneWidth: CGFloat = 64         // 한글 세 글자가 말줄임 없이 들어가는 폭
    private let laneSpacing: CGFloat = 2
    private let columnSpacing: CGFloat = 1
    private let minBlockHeight: CGFloat = 22
    private let headerHeight: CGFloat = 34

    private var ptPerMin: CGFloat { hourHeight / 60 }
    private var axisStartMin: Int { startHour * 60 }
    private var totalHeight: CGFloat { CGFloat(max(1, endHour - startHour)) * hourHeight }

    /// 날짜별 배치 결과를 한 번만 계산한다 — 칼럼 폭과 블록 위치가 같은 값을 쓴다.
    private var placedByDay: [String: [TimelineLayout.Placed]] {
        Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, TimelineLayout.place(reservations($0))) })
    }

    var body: some View {
        let placed = placedByDay
        // ponytail: 날짜 헤더가 세로 스크롤과 함께 밀려 올라간다. 영업시간 전체가 대체로
        // 한 화면에 들어와(12시간 x 56pt) 실제로 밀리는 일이 드물어 고정하지 않았다.
        // 영업시간이 길어 세로 스크롤이 길어지면 헤더를 고정하는 쪽으로 바꾼다.
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 6) {
                gutter
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            ForEach(Array(dayKeys.enumerated()), id: \.element) { index, key in
                                dayColumn(key, index: index, placed: placed[key] ?? [])
                                    .id(key)
                            }
                        }
                    }
                    // 열 때 오늘 칸을 가운데로. 안 하면 늘 월요일부터라 주 후반엔 매번 밀어야 한다.
                    .onAppear {
                        guard dayKeys.contains(todayKey) else { return }
                        Task { @MainActor in proxy.scrollTo(todayKey, anchor: .center) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private var gutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Color.clear.frame(height: headerHeight)   // 날짜 헤더와 눈금 높이를 맞춘다
            ForEach(startHour..<endHour, id: \.self) { h in
                Text(String(format: "%02d", h))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: gutterWidth, alignment: .trailing)
    }

    private func dayColumn(_ key: String, index: Int, placed: [TimelineLayout.Placed]) -> some View {
        let lanes = TimelineLayout.maxLanes(placed)
        let width = laneWidth * CGFloat(lanes) + laneSpacing * CGFloat(lanes - 1)
        return VStack(spacing: 0) {
            Text(header(key, index))
                .font(.caption2.weight(key == todayKey ? .bold : .regular))
                .foregroundStyle(key == todayKey ? Color.accentColor : .secondary)
                .lineLimit(1)
                .frame(width: width, height: headerHeight)

            ZStack(alignment: .topLeading) {
                ForEach(0...(endHour - startHour), id: \.self) { i in
                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(i) * hourHeight)
                }
                ForEach(placed, id: \.reservation.id) { p in
                    block(p, laneCount: lanes)
                }
            }
            .frame(width: width, height: totalHeight, alignment: .topLeading)
            .storeClosed(closedKind(key), cornerRadius: 0)
        }
    }

    private func block(_ p: TimelineLayout.Placed, laneCount: Int) -> some View {
        // 칼럼 폭은 그날 최대 겹침으로 잡혀 있다. 덜 겹친 묶음은 제 칸 수에 맞춰 넓게 쓴다.
        let span = CGFloat(laneCount) / CGFloat(p.laneCount)
        let w = laneWidth * span + laneSpacing * (span - 1)
        let x = CGFloat(p.laneIndex) * (w + laneSpacing)
        let top = CGFloat(p.startMin - axisStartMin) * ptPerMin
        let height = max(minBlockHeight, CGFloat(p.endMin - p.startMin) * ptPerMin)
        let c = color(p.reservation)

        return Button {
            onTap(p.reservation)
        } label: {
            Text(customerName(p.reservation.customerId))
                .font(.caption2)
                .lineLimit(1)
                .timelineBlockChrome(color: c, isInactive: p.reservation.isInactive,
                                     isNoshow: p.reservation.isNoshow,
                                     width: w, height: height)
        }
        .buttonStyle(.plain)
        .offset(x: x, y: top)
    }
}
