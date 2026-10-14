import SwiftUI

/// 일(day) 타임라인 — 시간축 위에 예약을 블록으로 배치.
/// 시작시간=세로 위치, 소요시간=블록 높이. 같은 시간대 겹치는 예약은
/// 그리디 컬럼 배치로 나란히 표시(웹 Timeline 클러스터링과 동일 개념).
struct DayTimelineView: View {
    let reservations: [Reservation]     // 해당 날짜(담당자 필터 반영)
    let startHour: Int
    let endHour: Int
    var customerName: (Int) -> String = { "고객 #\($0)" }
    var color: (Reservation) -> Color = { _ in .accentColor }
    /// 서비스명 → hex. 기본값 없음 — 빠뜨리면 칩이 조용히 폴백 회색이 된다.
    let serviceColorMap: [String: String]
    var onTap: (Reservation) -> Void = { _ in }

    private let hourHeight: CGFloat = 56
    private let gutterWidth: CGFloat = 40
    private let laneSpacing: CGFloat = 3
    private let minBlockHeight: CGFloat = 26
    private var ptPerMin: CGFloat { hourHeight / 60 }
    private var axisStartMin: Int { startHour * 60 }
    private var totalHeight: CGFloat { CGFloat(max(1, endHour - startHour)) * hourHeight }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 6) {
                gutter
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // 시간 구분선
                        ForEach(0...(endHour - startHour), id: \.self) { i in
                            Rectangle()
                                .fill(Color(.separator).opacity(0.5))
                                .frame(height: 0.5)
                                .offset(y: CGFloat(i) * hourHeight)
                        }
                        // 예약 블록
                        ForEach(positioned, id: \.reservation.id) { p in
                            block(p, totalWidth: geo.size.width)
                        }
                    }
                }
                .frame(height: totalHeight)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private var gutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { h in
                Text(String(format: "%02d", h))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: gutterWidth, alignment: .trailing)
    }

    private func block(_ p: Positioned, totalWidth: CGFloat) -> some View {
        let laneW = max(1, (totalWidth - laneSpacing * CGFloat(p.colCount - 1)) / CGFloat(p.colCount))
        let x = CGFloat(p.colIndex) * (laneW + laneSpacing)
        let c = color(p.reservation)
        return Button {
            onTap(p.reservation)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.reservation.startTime).font(.caption2.weight(.semibold)).monospacedDigit()
                Text(customerName(p.reservation.customerId)).font(.caption2).lineLimit(1)
                // 칩은 평문보다 위아래 패딩만큼 높다. 임계값을 그대로 두면 60분(56pt)보다
                // 짧은 블록에서 칩 줄이 잘린다.
                if p.height > 54 {
                    ServiceChipList(
                        service: p.reservation.service,
                        colorMap: serviceColorMap,
                        wraps: false
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .frame(width: laneW, height: p.height, alignment: .topLeading)
            .background(c.opacity(0.16))
            .overlay(alignment: .leading) { Rectangle().fill(c).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .offset(x: x, y: p.top)
    }

    // MARK: - 레이아웃 계산

    private struct Positioned {
        let reservation: Reservation
        let top: CGFloat
        let height: CGFloat
        let colIndex: Int
        let colCount: Int
    }

    /// 겹침 클러스터·레인 배치는 `TimelineLayout`이 한다(주 타임라인과 공용).
    /// 여기서는 분 단위를 이 뷰의 pt 좌표로 옮기기만 한다.
    private var positioned: [Positioned] {
        TimelineLayout.place(reservations).map { p in
            Positioned(
                reservation: p.reservation,
                top: CGFloat(p.startMin - axisStartMin) * ptPerMin,
                height: max(minBlockHeight, CGFloat(p.endMin - p.startMin) * ptPerMin),
                colIndex: p.laneIndex,
                colCount: p.laneCount
            )
        }
    }
}
