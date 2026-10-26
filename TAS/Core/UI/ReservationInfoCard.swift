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
    /// 웹 `onCustomerClick` — 있으면 고객명을 눌러 고객 상세(카드의 나머지는 그대로 예약 상세).
    var onCustomerTap: (() -> Void)? = nil
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

    // 좌측 칸 폭은 글자 크기를 따라간다 — 고정폭이면 손쉬운 사용의 큰 글자에서
    // "2026-08-31"이 칸에 안 들어가 말줄임된다. (기본값 있는 private 저장 프로퍼티라
    //  memberwise init 에는 나타나지 않는다 — 호출부는 그대로다.)
    @ScaledMetric(relativeTo: .caption2) private var dateColumnWidth: CGFloat = 68
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth: CGFloat = 38

    /// 취소·노쇼는 담당자 색을 버리고 무채색 + 빗금으로 간다(웹 `.inactive` 와 같다).
    private var isInactive: Bool { reservation.isInactive }

    private var accent: Color { assigneeColor ?? .secondary }

    var body: some View {
        HStack(spacing: 10) {
            if showDate || timeMode != .hidden {
                leading
            }
            main
            Spacer(minLength: 0)
            if showStatus || showPrice {
                trailing
            }
        }
        .padding(6)
        .padding(.leading, accentBar ? 4 : 0)   // 왼쪽 띠가 먹는 만큼
        .background(cardBackground)
        .overlay(alignment: .leading) {
            // 웹은 border-left 를 4px 로 굵혀 카드 가장자리에 색을 둔다 — 안쪽 막대가 아니다.
            if accentBar {
                Rectangle()
                    .fill(isInactive ? Color(.separator) : accent)
                    .frame(width: 4)
            }
        }
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        // 카드는 통째로 눌리는 한 덩어리다. 묶지 않으면 VoiceOver 가 시간·배지·이름·
        // 시술칩·담당자·상태·금액을 따로 세워, 예약 하나를 지나는 데 여덟 번 넘긴다.
        .accessibilityElement(children: .combine)
        // 묶인 카드에서 고객명만 따로 누를 수 없으니 VoiceOver 에는 동작으로 준다
        .accessibilityActions {
            if let onCustomerTap {
                Button("고객 상세 열기", action: onCustomerTap)
            }
        }
    }

    /// 웹처럼 색은 그대로(굵은 검정), 취소·노쇼는 취소선. 누를 수 있으면 손가락 크기만큼 위아래로 넓혀 받는다.
    @ViewBuilder private func customerNameText(_ name: String) -> some View {
        let text = Text(name)
            .font(.tasSmall.weight(.bold)) // 웹 StyledCustomerName 12 굵게
            .strikethrough(isInactive, color: .textTertiary)
            .foregroundStyle(isInactive ? Color.textTertiary : Color.textPrimary)
        if let onCustomerTap {
            // 카드(예약 상세 버튼) 안이라 Button 을 겹치면 안쪽이 눌리지 않는다 — 안쪽 제스처가 먼저 받는다
            text
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCustomerTap)
                .padding(.vertical, -12)
        } else {
            text
        }
    }

    // MARK: - 카드 표면 (웹 StyledCard 이식)

    /// 위는 거의 흰색, 아래로 갈수록 담당자 색이 비친다 — 웹과 같은 세로 그라데이션.
    /// 색은 담당자 색에서 뽑으므로 다크 모드에서도 배경 대비가 유지된다.
    @ViewBuilder private var cardBackground: some View {
        if isInactive {
            // 빗금 + 무채색. 끝난 예약은 색을 잃는다.
            ZStack {
                Color(.secondarySystemBackground)
                HatchPattern(noshow: reservation.isNoshow)
            }
        } else {
            LinearGradient(
                colors: [Color(.systemBackground), accent.opacity(0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isInactive ? Color(.separator) : accent.opacity(0.27), lineWidth: 1)
    }

    // MARK: - 좌측(날짜·시간)

    private var leading: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showDate {
                Text(reservation.date)
                    .font(.tasXSmall) // 웹 StyledCompactDateLabel 11
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }
            switch timeMode {
            case .hidden:
                EmptyView()
            case .start:
                Text(reservation.startTime)
                    .font(.tasSmall.weight(.bold))
                    .monospacedDigit()
            case .range:
                // 웹은 시작·종료를 같은 굵기·색으로 쌓는다 — 줄바꿈 자체가 범위를 뜻한다.
                // 종료만 흐리면 "언제 끝나는지"가 부가정보처럼 읽힌다.
                // 웹 StyledLeft — 12 굵게
                Text(reservation.startTime)
                    .font(.tasSmall.weight(.bold))
                    .monospacedDigit()
                Text(reservation.endTime)
                    .font(.tasSmall.weight(.bold))
                    .monospacedDigit()
            }
        }
        // 날짜("2026-08-31")가 붙으면 시간만 있을 때보다 넓어야 잘리지 않는다.
        .frame(width: showDate ? dateColumnWidth : timeColumnWidth, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    // MARK: - 본문(고객·시술·담당자)

    private var main: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let customerName {
                HStack(spacing: 6) {
                    // 웹과 같은 차례 — 배지가 이름 앞에 선다.
                    if isNewCustomer { NewCustomerBadge() }
                    customerNameText(customerName)
                }
            }
            ServiceChipList(service: reservation.service, colorMap: serviceColorMap, wraps: false, inactive: isInactive)
            // 담당자는 다음 줄 — 좁은 칸에서 시술과 같은 줄에 두면 둘이 서로를 민다(웹과 같다).
            if let assigneeName {
                AssigneeBadge(name: assigneeName, color: assigneeColor)
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
                    .font(.tasMedium.weight(.bold)) // 웹 StyledPrice 13 굵게
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
