import Foundation
import Observation

@MainActor
@Observable
final class CustomersViewModel {
    struct Data {
        var customers: [Customer]
        var reservationsByCustomer: [Int: [Reservation]]
        /// 서비스명 → hex(웹 `SERVICE_COLOR_MAP`). 예약 이력의 시술 칩 색.
        var serviceColorMap: [String: String]
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
        let all = (state.value?.customers ?? []).sortedByName()
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

    /// 전체 고객(병합 후보 등).
    var allCustomers: [Customer] { state.value?.customers ?? [] }

    /// 고객 id → 예약 건수(병합 대상 판단 근거 등).
    var reservationCounts: [Int: Int] {
        (state.value?.reservationsByCustomer ?? [:]).mapValues(\.count)
    }

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

    var serviceColorMap: [String: String] { state.value?.serviceColorMap ?? [:] }

    func load() async {
        state = .loading
        do {
            async let customers = service.fetchCustomers()
            async let reservations = service.fetchReservations()
            // 서비스 카탈로그는 시술 칩 **색**에만 쓴다. /api/services가 실패했다고
            // 고객 목록까지 못 보여줄 이유는 없으므로 실패를 삼키고 색만 폴백시킨다.
            async let services = try? await service.fetchServices()
            let (cus, res) = try await (customers, reservations)
            let svc = await services

            var byCustomer: [Int: [Reservation]] = [:]
            for r in res.reservations { byCustomer[r.customerId, default: []].append(r) }

            state = .loaded(Data(
                customers: cus.customers,
                reservationsByCustomer: byCustomer,
                serviceColorMap: svc.map {
                    ServiceColor.buildServiceColorMap(catalog: $0.services, storeMap: $0.categoryBaseColors)
                } ?? [:]
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
