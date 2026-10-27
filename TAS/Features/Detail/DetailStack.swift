import SwiftUI

/// 상세 레이어가 쓰는 매장 데이터 — 캘린더·고객·매출 탭이 똑같이 불러오는 예약·고객·담당자·서비스.
/// 어느 탭에서 열든 같은 상세(변경·이력 포함)를 그리려고 한 모양으로 넘긴다.
struct DetailData {
    var reservations: [Reservation]
    var customersById: [Int: Customer]
    var assigneesById: [Int: Assignee]
    var services: [ServiceItem]
    var serviceColorMap: [String: String]
    var history: [ReservationHistoryEntry]

    func reservation(_ id: Int) -> Reservation? { reservations.first { $0.id == id } }
    func assignee(_ id: Int?) -> Assignee? { id.flatMap { assigneesById[$0] } }
    func reservations(ofCustomer id: Int) -> [Reservation] { reservations.filter { $0.customerId == id } }

    /// 해당 예약의 변경 이력(최신순).
    func history(forReservation id: Int) -> [ReservationHistoryEntry] {
        history.filter { $0.reservationId == id }.sorted { $0.timestamp > $1.timestamp }
    }

    /// 재직 중 담당자(휴직·퇴직 제외), 이름 순 — 예약 변경 폼의 선택지.
    var activeAssignees: [Assignee] {
        assigneesById.values
            .filter { $0.status != .leave && $0.status != .retired }
            .sorted { $0.name < $1.name }
    }

    /// 다음 예약/고객 정수 id(max+1) — 웹 getNextNumericId.
    var nextReservationId: Int { (reservations.map(\.id).max() ?? 0) + 1 }
    var nextCustomerId: Int { (customersById.keys.max() ?? 0) + 1 }
}

/// 상세 레이어 하나 — 무엇을 그릴지. 데이터 대신 id 를 들고 있어, 다시 불러오면 바뀐 값으로 그린다.
enum DetailRoute: Hashable, Identifiable {
    case reservation(Int)
    case customer(Int)
    case editReservation(Int)
    case editCustomer(Int)

    var id: Self { self }

    var isForm: Bool {
        switch self {
        case .editReservation: return true
        // 고객 수정은 칸이 몇 개 안 돼 상세처럼 내용 높이만큼(웹 레이어 안 편집)
        case .reservation, .customer, .editCustomer: return false
        }
    }

    /// 바로 아래 레이어와 같은 것을 열면 새로 쌓지 않고 그리로 돌아간다(안드로이드 `DetailStack` 과 같은 동선 —
    /// 고객 → 예약 → 같은 고객 이름을 누르면 고객 상세가 두 겹이 되지 않는다).
    static func shouldReturn(opening next: DetailRoute, parent: DetailRoute?) -> Bool { next == parent }
}

/// 상세를 끝없이 쌓는다 — 예약 상세 고객명 → 고객 상세, 고객 상세 예약 → 예약 상세 → …
/// 레이어마다 다음 레이어를 시트로 올린다. 데이터는 부모가 다시 그릴 때마다 새 값으로 내려온다.
struct DetailSheet: View {
    let route: DetailRoute
    let data: DetailData
    /// 상태·결제·변경 뒤 탭의 데이터를 다시 읽는다.
    let reload: () async -> Void
    /// 바로 아래 레이어(없으면 맨 아래).
    var parent: DetailRoute? = nil

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var next: DetailRoute?
    /// 상세가 알려준 내용 높이 — 웹 레이어처럼 내용만큼만 올라온다(아래가 비지 않게). 0 이면 아직 모름.
    @State private var fitHeight: CGFloat = 0

    private var store: Store? { session.currentStore }


    var body: some View {
        content
            // 웹 상세 레이어처럼 내용 높이만큼 올라와 뒤 화면이 보인다 — 끌어 올리면 전체. 수정 폼은 처음부터 전체.
            .environment(\.reportSheetHeight) { height in
                if !route.isForm, abs(height - fitHeight) > 1 { fitHeight = height }
            }
            .presentationDetents(route.isForm ? [.large] : [.fraction(0.6), .large])
            // SwiftUI 는 띄운 뒤 바뀐 높이를 시트에 반영하지 않는다(iOS 26 실측) — UIKit 시트에 직접 내용 높이 칸을 넣는다
            .background { if !route.isForm { SheetFitter(height: fitHeight) } }
            // iOS 26 은 낮은 높이 시트를 유리처럼 비춰 뒤 달력 글자가 겹친다 — 불투명 바탕으로 글자 대비를 지킨다
            .presentationBackground(Color(.systemBackground))
            .sheet(item: $next) { nextRoute in
                DetailSheet(route: nextRoute, data: data, reload: reload, parent: route)
            }
    }

    private func open(_ nextRoute: DetailRoute) {
        if DetailRoute.shouldReturn(opening: nextRoute, parent: parent) {
            dismiss()
        } else {
            next = nextRoute
        }
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .reservation(let id):
            if let reservation = data.reservation(id) {
                let customer = data.customersById[reservation.customerId]
                ReservationDetailView(
                    reservation: reservation,
                    customer: customer,
                    assignee: data.assignee(reservation.assigneeId),
                    serviceColorMap: data.serviceColorMap,
                    isNewCustomer: customer?.isNewCustomerVisit(on: reservation.date) ?? false,
                    service: TASService(),
                    onChanged: reload,
                    onEdit: { open(.editReservation($0.id)) },
                    history: data.history(forReservation: id),
                    assigneeName: { data.assignee($0)?.name ?? "미지정" },
                    pointRate: store?.effectivePointRate ?? 0,
                    onCustomerTap: { open(.customer($0)) }
                )
            } else {
                gone("삭제된 예약입니다")
            }

        case .customer(let id):
            if let customer = data.customersById[id] {
                let today = KST.dayKey.string(from: Date())
                let reservations = data.reservations(ofCustomer: id)
                CustomerDetailView(
                    customer: customer,
                    stats: CustomerStats.summarize(reservations, today: today),
                    reservations: reservations,
                    serviceColorMap: data.serviceColorMap,
                    onEdit: { open(.editCustomer($0.id)) },
                    pointsEnabled: store?.usePointSystem ?? false,
                    pointSettings: store?.pointSettings,
                    service: TASService(),
                    onChanged: reload,
                    // 게스트는 합치기 없음 — 웹 게스트와 같다(웹 병합은 서버 API 라 로컬에선 숨김, 지시자 2026-10-21·10-27)
                    mergeCandidates: session.isGuest ? [] : data.customersById.values.filter { $0.id != id },
                    reservationCounts: Dictionary(grouping: data.reservations, by: \.customerId).mapValues(\.count),
                    assigneesById: data.assigneesById,
                    onReservationTap: { open(.reservation($0.id)) }
                )
            } else {
                gone("삭제된 고객입니다")
            }

        case .editReservation(let id):
            if let reservation = data.reservation(id) {
                ReservationCreateView(
                    service: TASService(),
                    customers: Array(data.customersById.values),
                    assignees: data.activeAssignees,
                    catalog: data.services,
                    serviceColorMap: data.serviceColorMap,
                    existingReservations: data.reservations,
                    pointRate: store?.effectivePointRate ?? 0,
                    initialDate: KST.dayKey.date(from: reservation.date) ?? Date(),
                    nextReservationId: data.nextReservationId,
                    nextCustomerId: data.nextCustomerId,
                    editing: reservation,
                    onSaved: { Task { await reload() } }
                )
            } else {
                gone("삭제된 예약입니다")
            }

        case .editCustomer(let id):
            if let customer = data.customersById[id] {
                CustomerFormView(service: TASService(), editing: customer, onSaved: reload)
            } else {
                gone("삭제된 고객입니다")
            }
        }
    }

    private func gone(_ message: String) -> some View {
        NavigationStack {
            ContentUnavailableView(message, systemImage: "tray")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
                }
        }
    }
}

/// 상세 시트가 내용만큼 올라오게 — 상세 화면이 (본문 + 아래 버튼 줄 + 머리) 높이를 시트에 알린다.
/// 프리퍼런스는 안쪽 NavigationStack 에서 끊겨 환경값(알림 함수)으로 내려준다.
extension EnvironmentValues {
    @Entry var reportSheetHeight: (CGFloat) -> Void = { _ in }
}

extension View {
    /// [content]·[bottomBar] 는 재어 둔 높이, 머리(끌기 손잡이 + 제목 줄)는 시트마다 같아 상수.
    /// 홈 표시줄 자리는 더하지 않는다 — UIKit 시트 높이 칸은 아래 안전 영역을 뺀 값이다.
    func reportsSheetHeight(content: CGFloat, bottomBar: CGFloat = 0) -> some View {
        modifier(SheetHeightReporter(total: content > 0 ? content + bottomBar + sheetHeaderHeight : 0))
    }
}

private struct SheetHeightReporter: ViewModifier {
    let total: CGFloat
    @Environment(\.reportSheetHeight) private var report
    func body(content: Content) -> some View {
        content.onChange(of: total, initial: true) { _, value in if value > 0 { report(value) } }
    }
}

/// 시트 머리 — 끌기 손잡이 자리 + 가운데 제목 줄(iOS 26 시트 실측 70).
private let sheetHeaderHeight: CGFloat = 70

/// 시트를 내용 높이 칸 + 전체 칸으로 — 사장님이 끌어 올려 전체로 본 뒤엔 그대로 둔다.
/// 키보드가 뜨면 전체로 올린다(낮은 칸이면 키보드가 아래 입력칸을 덮는다).
private struct SheetFitter: UIViewControllerRepresentable {
    let height: CGFloat

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.height = height
        DispatchQueue.main.async { controller.apply() }
    }

    final class Controller: UIViewController {
        var height: CGFloat = 0
        private let fit = UISheetPresentationController.Detent.Identifier("fit")

        override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
                                                   name: UIResponder.keyboardWillShowNotification, object: nil)
        }

        func apply() {
            guard height > 0, let sheet = sheetPresentationController else { return }
            let wasFull = sheet.selectedDetentIdentifier == .large
            let h = height
            sheet.animateChanges {
                sheet.detents = [.custom(identifier: fit) { context in min(h, context.maximumDetentValue) }, .large()]
                if !wasFull { sheet.selectedDetentIdentifier = fit }
            }
        }

        @objc private func keyboardWillShow() {
            // 이 시트가 맨 위에 떠 있을 때만(아래 깔린 시트는 그대로)
            guard let sheet = sheetPresentationController, sheet.presentedViewController.presentedViewController == nil else { return }
            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
        }
    }
}
