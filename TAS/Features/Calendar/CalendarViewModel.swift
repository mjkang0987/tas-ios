import Foundation
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    /// 캘린더가 필요로 하는 묶음: 예약 + 이름 해석용 고객/담당자 맵.
    struct Data {
        var reservations: [Reservation]
        var customersById: [Int: Customer]
        var assigneesById: [Int: Assignee]
    }

    var state: Loadable<Data> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 해당 날짜("YYYY-MM-DD") 예약을 시작시간 순으로.
    func reservations(on dateKey: String) -> [Reservation] {
        (state.value?.reservations ?? [])
            .filter { $0.date == dateKey }
            .sorted { $0.startTime < $1.startTime }
    }

    func customer(_ id: Int) -> Customer? { state.value?.customersById[id] }
    func assignee(_ id: Int?) -> Assignee? { id.flatMap { state.value?.assigneesById[$0] } }

    func customerName(_ id: Int) -> String {
        customer(id)?.name ?? "고객 #\(id)"
    }

    func load() async {
        state = .loading
        do {
            // 예약·고객·담당자를 병렬로. 이름 해석에 셋 다 필요.
            async let reservations = service.fetchReservations()
            async let customers = service.fetchCustomers()
            async let assignees = service.fetchAssignees()

            let (res, cus, asg) = try await (reservations, customers, assignees)

            let customersById = Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let assigneesById = Dictionary(asg.assignees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            state = .loaded(Data(
                reservations: res.reservations,
                customersById: customersById,
                assigneesById: assigneesById
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
