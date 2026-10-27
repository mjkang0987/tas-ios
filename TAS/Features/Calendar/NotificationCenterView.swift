import SwiftUI
import Observation

/// 알림 종·알림 시트·예약 요청 — 웹 `NotificationCenter`(헤더 종) 이식.
///
/// 고객이 공개 예약 페이지에서 보낸 **신규 신청 / 변경 요청 / 취소 요청**은 즉시 반영되지 않고
/// `pendingAction`으로 대기한다. 오너가 수락해야 예약에 반영되므로, 앱에도 이 목록이 없으면
/// 앱만 쓰는 오너는 고객 요청을 영영 보지 못한다.
@MainActor
@Observable
final class BookingRequestsViewModel {
    var state: Loadable<[BookingRequest]> = .idle
    /// 처리 중인 항목 id — 연속 탭으로 같은 요청을 두 번 보내지 않게 막는다.
    var busyId: String?
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var requests: [BookingRequest] { state.value ?? [] }
    var pendingCount: Int { requests.count }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.fetchBookingRequests())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 수락/거절. 예약이 실제로 바뀌었으면 true(캘린더 새로고침이 필요하다는 뜻).
    ///
    /// 변경·취소 요청을 **거절**하면 요청만 폐기되고 예약은 그대로라 새로고침할 것이 없다.
    /// 신규 신청은 수락(→예약)·거절(→취소) 모두 예약 상태가 바뀐다.
    func decide(_ request: BookingRequest, _ decision: BookingDecision) async -> Bool {
        guard busyId == nil else { return false }
        busyId = request.id
        defer { busyId = nil }
        do {
            try await service.decideBookingRequest(id: request.id, decision: decision)
            actionError = nil
            await load()
            return decision == .approve || request.kind == .new
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

/// 캘린더 툴바의 알림 종 — 웹 헤더 `NotificationCenter` 버튼과 같은 자리·같은 표시.
/// 처리할 일(대기 중 예약 요청)은 빨간 숫자, 곧 시작하는 예약만 있으면 보라 점(`UpcomingReservations.bellIndicator`).
struct NotificationBellButton: View {
    let count: Int
    let dot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        CountBadge(count: count).offset(x: 9, y: -9)
                    } else if dot {
                        // '곧 시작' 태그와 같은 보라 — 어두운 화면에선 밝아져 바탕 위에서 보인다
                        Circle().fill(BadgeTone.paid.foreground).frame(width: 8, height: 8).offset(x: 2, y: -2)
                    }
                }
        }
        .accessibilityLabel(count > 0 ? "알림, 처리할 일 \(count)건" : dot ? "알림, 곧 시작하는 예약 있음" : "알림")
    }
}

/// 알림 시트 — 웹 `NotificationCenter` 레이어. 앱에서 쓸 수 있는 칸만: 고객 예약 요청(로그인·온라인예약) + 곧 시작하는 예약.
/// (쿠폰·회원권 만료 임박은 로그인 확인 뒤, 네이버 알림은 앱에 연동이 없어 아직 없다.)
struct NotificationCenterView: View {
    private enum Tab: Hashable { case all, request, upcoming }

    /// nil = 요청 칸 없음(게스트·온라인예약 끔) — 그때는 칸이 하나라 탭도 없다(웹 `tabs.length > 2`).
    let requests: BookingRequestsViewModel?
    let reservations: [Reservation]
    let customersById: [Int: Customer]
    let assigneesById: [Int: Assignee]
    /// 요청 수락으로 예약이 바뀌었을 때 캘린더를 다시 읽는다.
    let onApplied: () async -> Void
    /// 줄을 누르면 그 예약 상세 — 시트를 바꿔 띄우는 건 부르는 쪽이 한다.
    let onOpen: (Int) -> Void

    @State private var tab: Tab = .all
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // 열어 둔 채 시간이 지나도 '곧 시작'이 맞게 1분마다 다시 센다(웹과 같다)
            TimelineView(.everyMinute) { context in
                List {
                    if let requests, tab != .upcoming { requestSection(requests) }
                    if tab != .request { upcomingSection(UpcomingReservations.compute(reservations, now: context.date)) }
                }
                .listStyle(.insetGrouped)
                .refreshable { await requests?.load() }
            }
            .safeAreaInset(edge: .top) {
                if let requests {
                    Picker("알림 종류", selection: $tab) {
                        Text("전체").tag(Tab.all)
                        Text(requests.pendingCount > 0 ? "요청 \(requests.pendingCount)" : "요청").tag(Tab.request)
                        Text("곧 시작").tag(Tab.upcoming)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
            .alert("처리하지 못했습니다", isPresented: errorBinding) {
                Button("확인", role: .cancel) { requests?.actionError = nil }
            } message: {
                Text(requests?.actionError ?? "")
            }
            // 열 때마다 새로 — 다른 직원이 처리했거나 새로 들어온 것(웹 openLayer). 읽어 둔 목록이 있으면 로딩 표시 없이 갱신만.
            .task { await requests?.load() }
        }
        // 예약 상세와 같은 높이로 올라온다(웹 휴대폰 아래 시트)
        .presentationDetents([.fraction(0.6), .large])
    }

    private func requestSection(_ requests: BookingRequestsViewModel) -> some View {
        Section {
            switch requests.state {
            case .failed(let message):
                Text(message).font(.tasMedium).foregroundStyle(Color.dangerText)
            case .loaded(let list) where !list.isEmpty:
                ForEach(list) { request in
                    BookingRequestRow(
                        request: request,
                        isBusy: requests.busyId != nil,
                        onOpen: request.legacyId.map { id in { onOpen(id) } },
                        onDecide: { decision in
                            Task {
                                if await requests.decide(request, decision) { await onApplied() }
                            }
                        }
                    )
                }
            case .loaded:
                emptyText("대기 중인 요청이 없습니다")
            default:
                emptyText("불러오는 중…")
            }
        } header: {
            Text(requests.pendingCount > 0 ? "고객 예약 요청 \(requests.pendingCount)" : "고객 예약 요청")
        }
    }

    private func upcomingSection(_ upcoming: (soon: [UpcomingReservations.Item], next: UpcomingReservations.Item?)) -> some View {
        let shown = upcoming.soon.isEmpty ? (upcoming.next.map { [$0] } ?? []) : Array(upcoming.soon.prefix(UpcomingReservations.maxShown))
        return Section {
            if shown.isEmpty {
                emptyText("오늘 남은 예약이 없습니다")
            } else {
                ForEach(shown, id: \.reservation.id) { upcomingRow($0) }
            }
        } header: {
            Text(upcoming.soon.isEmpty && upcoming.next != nil ? "다음 예약" : "곧 시작하는 예약")
        }
    }

    private func upcomingRow(_ item: UpcomingReservations.Item) -> some View {
        let r = item.reservation
        let name = customersById[r.customerId].flatMap { $0.name.isEmpty ? nil : $0.name } ?? "고객 #\(r.customerId)"
        let assignee = r.assigneeId.flatMap { assigneesById[$0] }
        return Button { onOpen(r.id) } label: {
            HStack(spacing: 6) {
                // 웹 StyledUntilTag(보라 옅은 바탕) — 같은 색인 결제 배지 톤을 쓴다
                ToneBadge(tone: .paid, text: UpcomingReservations.untilLabel(item.minutesUntil))
                Text(r.startTime).monospacedDigit()
                Text(name).fontWeight(.semibold).lineLimit(1)
                if !r.service.isEmpty {
                    Text(r.service).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let assignee { AssigneeBadge(name: assignee.name, color: Color(hex: assignee.color)) }
            }
            .font(.tasBody)
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
        }
        .accessibilityHint("예약 상세 열기")
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.tasMedium).foregroundStyle(Color.textSecondary)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { requests?.actionError != nil }, set: { if !$0 { requests?.actionError = nil } })
    }
}

private struct BookingRequestRow: View {
    let request: BookingRequest
    let isBusy: Bool
    /// nil 이면(예약 번호가 아직 없는 요청) 내용은 글자만.
    let onOpen: (() -> Void)?
    let onDecide: (BookingDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onOpen {
                Button(action: onOpen) { summary.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("예약 상세 열기")
            } else {
                summary
            }

            HStack(spacing: 8) {
                Spacer()
                Button("거절") { onDecide(.reject) }
                    .buttonStyle(.bordered)
                    .tint(Color.dangerText)
                Button("수락") { onDecide(.approve) }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandFill) // 흰 글자 채움 — 어두운 모드의 밝은 accent 위 흰 글자는 대비가 모자란다
            }
            .font(.tasBody)
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(request.customerName.isEmpty ? "고객" : request.customerName)
                    .font(.tasBody.weight(.semibold))
                BookingRequestKindBadge(kind: request.kind)
                Spacer()
                if let assigneeName = request.assigneeName, !assigneeName.isEmpty {
                    Text(assigneeName).font(.caption2).foregroundStyle(Color.textSecondary)
                }
            }

            // 신규 신청은 그 자체가 신청 내용이고, 변경/취소는 '현재 예약'이 무엇인지가 판단 근거다.
            slotLine(label: request.kind == .new ? "신청" : "현재", slot: request.current, isAccent: false)
            if request.kind == .change, let requestedChange = request.requestedChange {
                slotLine(label: "변경", slot: requestedChange, isAccent: true)
            }
        }
    }

    private func slotLine(label: String, slot: BookingRequestSlot, isAccent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isAccent ? Color.accentColor : Color.textSecondary)
            Text("\(monthDay(slot.date)) \(slot.startTime)~\(slot.endTime)")
                .font(.caption)
            Text(slot.serviceSummary)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }

    /// "2026-08-10" → "8/10" (웹 `formatMd`).
    private func monthDay(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }
}

/// 요청 종류 배지 — 웹 `LabelBadge`의 tone(warning/purple/danger)에 대응.
private struct BookingRequestKindBadge: View {
    let kind: BookingRequestKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch kind {
        // 연한 같은 색 바탕 위 글자 — 상태 배지와 같은 진한 값(대비 4.5 이상)
        case .new: return Color(hex: "806600") ?? .orange
        case .change: return Color(hex: "6526D9") ?? .purple
        case .cancel: return Color(hex: "C5221F") ?? .red
        }
    }
}

/// 대기 건수 배지(툴바 아이콘 위). 9건을 넘으면 웹과 같이 "9+".
private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(Color.dangerFill, in: Capsule())
    }
}
