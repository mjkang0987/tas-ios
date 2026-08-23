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

    /// 매장 기준(KST) 오늘 — 지난 예약을 '완료'로 판정하는 기준선.
    private var today: String { KST.dayKey.string(from: Date()) }

    /// 고객별 집계(최근 시술 + 예약/취소/완료/노쇼) — 웹 `customerStats` 이식.
    /// 목록이 행마다 다시 훑지 않도록 한 번에 만들어 둔다.
    var statsByCustomer: [Int: CustomerStats.Summary] {
        CustomerStats.byCustomer(state.value?.reservationsByCustomer ?? [:], today: today)
    }

    func stats(for id: Int) -> CustomerStats.Summary {
        CustomerStats.summarize(state.value?.reservationsByCustomer[id] ?? [], today: today)
    }

    /// 상세의 '최근 예약'을 웹처럼 예약/완료/취소/노쇼로 묶는다(비어 있는 그룹은 뺀다).
    func reservationGroups(for id: Int) -> [CustomerStats.Group] {
        CustomerStats.groups(state.value?.reservationsByCustomer[id] ?? [], today: today)
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
