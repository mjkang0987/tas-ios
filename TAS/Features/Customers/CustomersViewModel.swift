import Foundation
import Observation

@MainActor
@Observable
final class CustomersViewModel {
    struct Data {
        var customers: [Customer]
        var reservationsByCustomer: [Int: [Reservation]]
        /// 담당자 id → 담당자. 예약 이력 행의 이름·색과 예약 상세에 쓴다.
        var assigneesById: [Int: Assignee]
        /// 서비스명 → hex(웹 `SERVICE_COLOR_MAP`). 예약 이력의 시술 칩 색.
        var serviceColorMap: [String: String]
        /// 고객별 집계 — 로드 시점에 한 번 만든다. 목록 body는 검색 타이핑마다 재평가되므로
        /// 여기서 계산하면 매 글자마다 전체 예약을 다시 훑게 된다.
        var statsByCustomer: [Int: CustomerStats.Summary]
        /// 집계 기준이 된 매장 기준(KST) 날짜.
        var today: String
    }


    var state: Loadable<Data> = .idle
    var searchText = ""

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    struct FilterResult {
        var customers: [Customer]
        /// 검색어로 걸린 메모 태그(고객 id별) — 이름·전화가 아니라 메모 때문에 뜬 결과를
        /// 행에서 근거로 보여줄 때 쓴다(웹 `address.tsx`의 memoTags 매칭과 동일 규칙 — 초성 대상 아님).
        var matchedMemoTags: [Int: [CustomerMemoTag]]
    }

    /// 트림된 검색어 — 필터와 화면(하이라이트 등)이 같은 트림 규칙을 보게 한다. 각자 트림하면
    /// 규칙이 갈릴 때 "필터엔 걸리는데 하이라이트만 안 뜨는" 어긋남이 생긴다.
    var trimmedSearchQuery: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// 필터링과 메모 매치 산출을 한 번에 한다 — 행마다 같은 매칭 규칙을 다시 구현하지 않는다
    /// (웹 코드리뷰에서 지적된 중복 계산과 같은 클래스, 여기서도 필터 계산 지점 한 곳으로 모은다).
    var filterResult: FilterResult {
        let all = (state.value?.customers ?? []).sortedByName()
        let query = trimmedSearchQuery
        guard !query.isEmpty else { return FilterResult(customers: all, matchedMemoTags: [:]) }

        let digits = query.filter(\.isNumber)
        var tagsByCustomer: [Int: [CustomerMemoTag]] = [:]
        let filtered = all.filter { customer in
            let matchedTags = (customer.memoTags ?? []).filter { $0.text.localizedCaseInsensitiveContains(query) }
            if !matchedTags.isEmpty { tagsByCustomer[customer.id] = matchedTags }

            return customer.name.localizedCaseInsensitiveContains(query)
                || Chosung.matches(customer.name, query)
                || (!digits.isEmpty && customer.tel.contains(digits))
                || !matchedTags.isEmpty
        }

        return FilterResult(customers: filtered, matchedMemoTags: tagsByCustomer)
    }

    /// 다음 고객 정수 id(현재 최대 +1) — 신규 등록 폼용(웹 getNextNumericId).
    var nextCustomerId: Int { ((state.value?.customers.map(\.id).max()) ?? 0) + 1 }

    /// 고객별 집계(최근 시술 + 예약/취소/완료/노쇼) — 웹 `customerStats` 이식.
    var statsByCustomer: [Int: CustomerStats.Summary] { state.value?.statsByCustomer ?? [:] }

    var serviceColorMap: [String: String] { state.value?.serviceColorMap ?? [:] }

    /// 상세 레이어(`DetailSheet`)에 넘길 데이터 — 마지막으로 불러온 값(다시 불러오는 동안에도 남긴다).
    private(set) var detailData: DetailData?

    func load() async {
        state = .loading
        do {
            async let customers = service.fetchCustomers()
            async let reservations = service.fetchReservations()
            // 담당자도 색·이름 표시용이라 실패해도 고객 목록은 보여준다(색만 폴백).
            async let assignees = try? await service.fetchAssignees()
            // 서비스 카탈로그는 시술 칩 **색**에만 쓴다. /api/services가 실패했다고
            // 고객 목록까지 못 보여줄 이유는 없으므로 실패를 삼키고 색만 폴백시킨다.
            async let services = try? await service.fetchServices()
            let (cus, res) = try await (customers, reservations)
            let svc = await services
            let asg = await assignees

            var byCustomer: [Int: [Reservation]] = [:]
            for r in res.reservations { byCustomer[r.customerId, default: []].append(r) }

            let today = KST.dayKey.string(from: Date())
            let assigneesById = Dictionary(
                (asg?.assignees ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let serviceColorMap = svc.map {
                ServiceColor.buildServiceColorMap(catalog: $0.services, storeMap: $0.categoryBaseColors)
            } ?? [:]
            detailData = DetailData(
                reservations: res.reservations,
                customersById: Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                assigneesById: assigneesById,
                services: svc?.services ?? [],
                serviceColorMap: serviceColorMap,
                history: res.history ?? []
            )
            state = .loaded(Data(
                customers: cus.customers,
                reservationsByCustomer: byCustomer,
                assigneesById: assigneesById,
                serviceColorMap: serviceColorMap,
                statsByCustomer: CustomerStats.byCustomer(byCustomer, today: today),
                today: today
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
