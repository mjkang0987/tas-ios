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

    /// 담당자 목록(이름 순) — 필터 바용.
    var assignees: [Assignee] {
        guard let map = state.value?.assigneesById else { return [] }
        return map.values.sorted { $0.name < $1.name }
    }

    func customer(_ id: Int) -> Customer? { state.value?.customersById[id] }
    func assignee(_ id: Int?) -> Assignee? { id.flatMap { state.value?.assigneesById[$0] } }
    func serviceColor(_ name: String) -> Color? { state.value?.serviceColorByName[name] }

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
                serviceColorByName: serviceColorByName
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
