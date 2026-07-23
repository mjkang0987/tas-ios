import SwiftUI
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    /// 캘린더가 필요로 하는 묶음: 예약 + 이름/색 해석용 맵.
    struct Data {
        var reservations: [Reservation]
        var customersById: [Int: Customer]
        var assigneesById: [Int: Assignee]
        var serviceColorByName: [String: Color]
        var services: [ServiceItem]
    }

    var state: Loadable<Data> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 해당 날짜("YYYY-MM-DD") 예약을 시작시간 순으로. assigneeId 지정 시 담당자 필터.
    func reservations(on dateKey: String, assigneeId: Int? = nil) -> [Reservation] {
        (state.value?.reservations ?? [])
            .filter { $0.date == dateKey }
            .filter { assigneeId == nil || $0.assigneeId == assigneeId }
            .sorted { $0.startTime < $1.startTime }
    }

    /// 해당 월("YYYY-MM") 예약을 날짜·시작시간 순으로. 연 뷰의 월별 리스트용.
    func reservations(inMonthPrefix prefix: String, assigneeId: Int? = nil) -> [Reservation] {
        (state.value?.reservations ?? [])
            .filter { $0.date.hasPrefix(prefix) && (assigneeId == nil || $0.assigneeId == assigneeId) }
            .sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
    }

    /// 담당자 목록(이름 순) — 필터 바용.
    var assignees: [Assignee] {
        guard let map = state.value?.assigneesById else { return [] }
        return map.values.sorted { $0.name < $1.name }
    }

    // MARK: - 예약 생성 폼용 데이터

    /// 고객 목록.
    var customers: [Customer] { Array((state.value?.customersById ?? [:]).values) }

    /// 재직 중 담당자(휴직·퇴직 제외), 이름 순 — 웹 splitAssigneesByStatus(active).
    var activeAssignees: [Assignee] {
        assignees.filter { $0.status != .leave && $0.status != .retired }
    }

    /// 서비스 카탈로그(선택용).
    var serviceCatalog: [ServiceItem] { state.value?.services ?? [] }

    /// 다음 예약/고객 정수 id(max+1) — 웹 getNextNumericId.
    var nextReservationId: Int { ((state.value?.reservations.map(\.id).max()) ?? 0) + 1 }
    var nextCustomerId: Int { ((state.value?.customersById.keys.max()) ?? 0) + 1 }

    func reload() async { await load() }

    /// 기간 요약 — 건수(전체) + 매출(취소·노쇼 제외). 월/년 뷰 집계용.
    struct PeriodSummary: Equatable { var count: Int; var total: Int }

    /// 월 그리드용: "YYYY-MM" 프리픽스의 일자별 요약("YYYY-MM-DD" → 요약).
    func dailySummaries(monthPrefix: String, assigneeId: Int? = nil) -> [String: PeriodSummary] {
        aggregate(prefix: monthPrefix, keyLength: 10, assigneeId: assigneeId)
    }

    /// 연 리스트용: "YYYY" 프리픽스의 월별 요약("YYYY-MM" → 요약).
    func monthlySummaries(yearPrefix: String, assigneeId: Int? = nil) -> [String: PeriodSummary] {
        aggregate(prefix: yearPrefix, keyLength: 7, assigneeId: assigneeId)
    }

    /// 예약을 한 번 훑어 prefix로 필터하고, date의 앞 keyLength 글자를 키로 집계.
    private func aggregate(prefix: String, keyLength: Int, assigneeId: Int?) -> [String: PeriodSummary] {
        var out: [String: PeriodSummary] = [:]
        for r in state.value?.reservations ?? [] where r.date.hasPrefix(prefix) {
            guard assigneeId == nil || r.assigneeId == assigneeId else { continue }
            let key = String(r.date.prefix(keyLength))
            var s = out[key] ?? PeriodSummary(count: 0, total: 0)
            s.count += 1
            if r.status != .cancelled && r.status != .noshow { s.total += r.price ?? 0 }
            out[key] = s
        }
        return out
    }

    /// 당일 요약: 건수 + 매출 합계(취소·노쇼 제외).
    func daySummary(on dateKey: String, assigneeId: Int? = nil) -> (count: Int, total: Int) {
        let items = reservations(on: dateKey, assigneeId: assigneeId)
        let total = items
            .filter { $0.status != .cancelled && $0.status != .noshow }
            .compactMap(\.price)
            .reduce(0, +)
        return (items.count, total)
    }

    func customer(_ id: Int) -> Customer? { state.value?.customersById[id] }
    func assignee(_ id: Int?) -> Assignee? { id.flatMap { state.value?.assigneesById[$0] } }
    /// 서비스명 → 색. "커트+일반펌"처럼 조합된 문자열이면 첫 서비스 색으로 폴백.
    func serviceColor(_ name: String) -> Color? {
        guard let map = state.value?.serviceColorByName else { return nil }
        if let color = map[name] { return color }
        let first = name.split(separator: "+").first.map(String.init) ?? name
        return map[first]
    }

    func customerName(_ id: Int) -> String {
        customer(id)?.name ?? "고객 #\(id)"
    }

    /// 예약 날짜가 고객의 첫 방문일과 같으면 신규(웹 isNewCustomerVisit).
    func isNewCustomer(_ reservation: Reservation) -> Bool {
        customer(reservation.customerId)?.isNewCustomerVisit(on: reservation.date) ?? false
    }

    func load() async {
        state = .loading
        do {
            // 예약·고객·담당자·서비스를 병렬로. 이름/색 해석에 모두 필요.
            async let reservations = service.fetchReservations()
            async let customers = service.fetchCustomers()
            async let assignees = service.fetchAssignees()
            async let services = service.fetchServices()

            let (res, cus, asg, svc) = try await (reservations, customers, assignees, services)

            let customersById = Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let assigneesById = Dictionary(asg.assignees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            // 서비스명 → 카테고리 색(매장 커스텀 우선).
            var serviceColorByName: [String: Color] = [:]
            for item in svc.services {
                serviceColorByName[item.name] = ServiceColor.categoryColor(item.category, storeMap: svc.categoryBaseColors)
            }

            state = .loaded(Data(
                reservations: res.reservations,
                customersById: customersById,
                assigneesById: assigneesById,
                serviceColorByName: serviceColorByName,
                services: svc.services
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
