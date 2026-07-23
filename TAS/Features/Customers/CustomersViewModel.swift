import Foundation
import Observation

@MainActor
@Observable
final class CustomersViewModel {
    struct Data {
        var customers: [Customer]
        var reservationsByCustomer: [Int: [Reservation]]
    }

    struct VisitStats: Equatable {
        var visits: Int
        var cancels: Int
        var noshows: Int
    }

    var state: Loadable<Data> = .idle
    var searchText = ""

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var filtered: [Customer] {
        let all = (state.value?.customers ?? []).sorted { $0.name < $1.name }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        let digits = query.filter(\.isNumber)
        return all.filter { customer in
            customer.name.localizedCaseInsensitiveContains(query)
                || (!digits.isEmpty && customer.tel.contains(digits))
        }
    }

    /// 다음 고객 정수 id(현재 최대 +1) — 신규 등록 폼용(웹 getNextNumericId).
    var nextCustomerId: Int { ((state.value?.customers.map(\.id).max()) ?? 0) + 1 }

    /// 고객의 예약(최근 순).
    func reservations(for id: Int) -> [Reservation] {
        (state.value?.reservationsByCustomer[id] ?? []).sorted {
            ($0.date, $0.startTime) > ($1.date, $1.startTime)
        }
    }

    /// 방문/취소/노쇼 집계. 신청(requested)은 방문에 포함하지 않는다.
    func stats(for id: Int) -> VisitStats {
        var visits = 0, cancels = 0, noshows = 0
        for r in state.value?.reservationsByCustomer[id] ?? [] {
            switch r.status {
            case .cancelled: cancels += 1
            case .noshow: noshows += 1
            case .requested: break
            default: visits += 1
            }
        }
        return VisitStats(visits: visits, cancels: cancels, noshows: noshows)
    }

    func load() async {
        state = .loading
        do {
            async let customers = service.fetchCustomers()
            async let reservations = service.fetchReservations()
            let (cus, res) = try await (customers, reservations)

            var byCustomer: [Int: [Reservation]] = [:]
            for r in res.reservations { byCustomer[r.customerId, default: []].append(r) }

            state = .loaded(Data(customers: cus.customers, reservationsByCustomer: byCustomer))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
