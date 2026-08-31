import SwiftUI

/// 예약 한 건을 목록에서 보여주는 공용 행 — 웹 `components/ui/ReservationInfoCard.tsx` 이식.
///
/// 웹처럼 **한 컴포넌트에 표시 옵션을 켜고 끄는** 방식이다. 캘린더 목록·고객 상세의 예약 이력·
/// 매출 드릴다운이 각자 비슷한 행을 따로 그리고 있었기 때문에(같은 마크업 두 벌 + 세 번째 예정)
/// 한 벌로 합쳤다. 옵션 이름은 웹 props와 1:1로 맞춘다.
///
/// 레이아웃: `[날짜·시간] [담당자 색 바] [고객명·시술·담당자] ... [상태 배지·금액]`
struct ReservationInfoCard: View {
    /// 좌측 시간 표기 — 웹 `timeMode`.
    enum TimeMode {
        /// 시작 시간만 한 줄.
        case start
        /// 시작·종료를 위아래로.
        case range
        /// 시간 숨김.
        case hidden
    }

    let reservation: Reservation
    /// 서비스명 → hex(`ServiceColor.buildServiceColorMap`).
    let serviceColorMap: [String: String]

    /// 고객명. nil이면 고객 줄 자체를 그리지 않는다(고객 상세처럼 이미 누구인지 아는 자리).
    var customerName: String? = nil
    var isNewCustomer: Bool = false
    /// 담당자 이름·색. 이름이 nil이면 담당자 표기를 생략한다.
    var assigneeName: String? = nil
    var assigneeColor: Color? = nil

    /// 웹 `showDate` — 좌측에 날짜를 함께 보여준다(기간을 넘나드는 목록).
    var showDate: Bool = false
    /// 웹 `showPrice` — 우측에 금액.
    var showPrice: Bool = false
    /// 웹 `showStatus` — 우측에 상태 배지.
    var showStatus: Bool = true
    var timeMode: TimeMode = .range
    /// 웹 `accentBar` — 담당자 색 세로 바.
    var accentBar: Bool = true

    /// 상태 배지를 부르는 쪽이 아는 **유효 상태**로 덮는다(지난 예약=완료 등).
    /// 웹 `getReservationState`는 날짜를 보지 않아 '완료' 그룹에서도 파란 '예약'을 그리는데,
    /// 앱은 `CustomerStats.effectiveStatus` 판정을 유지한다.
    var statusOverride: CustomerStats.EffectiveStatus? = nil

    var body: some View {
        HStack(spacing: 10) {
            if showDate || timeMode != .hidden {
                leading
            }
            if accentBar {
                ColorAccentBar(color: assigneeColor, height: 28)
            }
            main
            Spacer(minLength: 0)
            if showStatus || showPrice {
                trailing
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - 좌측(날짜·시간)

    private var leading: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showDate {
                Text(reservation.date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            switch timeMode {
            case .hidden:
                EmptyView()
            case .start:
                Text(reservation.startTime)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            case .range:
                Text(reservation.startTime)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(reservation.endTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        // 날짜("2026-08-31")가 붙으면 시간만 있을 때보다 넓어야 잘리지 않는다.
        .frame(width: showDate ? 76 : 44, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    // MARK: - 본문(고객·시술·담당자)

    private var main: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let customerName {
                HStack(spacing: 6) {
                    Text(customerName).font(.subheadline.weight(.semibold))
                    if isNewCustomer { NewCustomerBadge() }
                }
            }
            HStack(spacing: 5) {
                ServiceChipList(service: reservation.service, colorMap: serviceColorMap, wraps: false)
                if let assigneeName {
                    Text("· \(assigneeName)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 우측(상태·금액)

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if showStatus {
                if let statusOverride {
                    ToneBadge(tone: statusOverride.tone, text: statusOverride.label)
                } else {
                    StatusBadge(state: reservation.displayState)
                }
            }
            if showPrice {
                Text(formatWon(reservation.price ?? 0))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
