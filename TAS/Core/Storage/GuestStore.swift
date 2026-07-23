import Foundation
import Observation

/// 게스트 모드 상태 + 로컬 스냅샷 관리자(싱글턴).
///
/// 웹의 `shouldUseLocalDb()`(sessionStorage `takeaseat.authenticated` 부재) 개념을
/// `isActive`로 대응한다. `isActive`면 `TASService`가 API 대신 이 스냅샷을 읽고 쓴다.
/// 화면 코드는 `TASService`만 거치므로 게스트/로그인 분기를 몰라도 된다.
@Observable
final class GuestStore {
    static let shared = GuestStore()

    /// 현재 게스트(로컬) 모드인지 — 웹 `shouldUseLocalDb()`.
    var isActive = false

    /// 로컬 DB 스냅샷. 모든 게스트 CRUD가 이 값을 읽고/쓴다.
    private(set) var snapshot: GuestSnapshot

    private let local = LocalStore.shared

    private init() {
        snapshot = local.load(GuestSnapshot.self) ?? GuestSnapshot()
    }

    // MARK: - Mode

    /// 게스트 모드 진입: 디스크 스냅샷을 다시 읽고 활성화.
    func activate() {
        snapshot = local.load(GuestSnapshot.self) ?? GuestSnapshot()
        isActive = true
    }

    /// 게스트 모드 종료(로컬 데이터는 유지 — 다음에 다시 게스트로 복귀 가능).
    func deactivate() {
        isActive = false
    }

    /// 온보딩을 마친(또는 데이터가 있는) 게스트 스냅샷이 디스크에 있는지.
    var hasOnboardedData: Bool {
        (local.load(GuestSnapshot.self) ?? GuestSnapshot()).hasData
    }

    var isOnboarded: Bool { snapshot.onboarded }

    // MARK: - Terms consent (약관 동의)

    /// 현재 약관 버전 — 웹 `CURRENT_TERMS_VERSION`. 개정 시 이 값을 올려 재동의를 받는다.
    static let currentTermsVersion = "2026-06-16"

    /// 게스트가 현재 버전 약관에 동의했는지(웹 `getGuestTermsVersion() === CURRENT_TERMS_VERSION`).
    var hasConsented: Bool { snapshot.termsAgreedVersion == Self.currentTermsVersion }

    /// 약관 동의 기록 — 온보딩 이전 단계.
    func agreeToTerms() {
        mutate { $0.termsAgreedVersion = Self.currentTermsVersion }
    }

    // MARK: - Persistence

    /// 스냅샷을 수정하고 즉시 디스크에 저장.
    func mutate(_ block: (inout GuestSnapshot) -> Void) {
        block(&snapshot)
        local.save(snapshot)
    }

    /// 게스트 데이터 초기화(웹 "게스트 데이터 초기화") — 스냅샷·파일 제거.
    func reset() {
        snapshot = GuestSnapshot()
        local.clear()
    }

    // MARK: - Onboarding

    /// 게스트 온보딩 완료 — 매장명/업종/서비스/담당자를 저장하고 onboarded 표시.
    func completeOnboarding(storeName: String?, shopType: String?,
                            services: [ServiceItem] = [], assignees: [Assignee] = [],
                            categoryBaseColors: [String: String] = [:]) {
        mutate { s in
            s.storeName = storeName
            s.shopType = shopType
            s.services = services
            s.assignees = assignees
            s.categoryBaseColors = categoryBaseColors
            s.onboarded = true
        }
    }

    /// 온보딩 건너뛰기(웹 "건너뛰기") — 빈 상태로 onboarded만 표시.
    func skipOnboarding() {
        mutate { $0.onboarded = true }
    }

    // MARK: - Write (로컬 스냅샷 CRUD) — TASService가 게스트일 때 호출

    /// 새 예약 추가. (id는 폼에서 부여해 넘긴다.)
    @discardableResult
    func createReservation(_ reservation: Reservation) -> Reservation {
        mutate { $0.reservations.append(reservation) }
        return reservation
    }

    /// 예약 수정(prev.id 기준으로 교체) + 변경 이력 기록(웹과 동일).
    @discardableResult
    func updateReservation(prev: Reservation, updated: Reservation) -> Reservation {
        mutate { s in
            if let i = s.reservations.firstIndex(where: { $0.id == prev.id }) {
                s.reservations[i] = updated
            }
            s.history.append(ReservationHistoryEntry(reservationId: prev.id, before: prev, after: updated, timestamp: Self.nowISO()))
        }
        return updated
    }

    /// 상태 변경(취소/노쇼/복원 등) + 변경 이력 기록. 없으면 nil.
    func setReservationStatus(id: Int, status: ReservationStatus) -> Reservation? {
        var result: Reservation?
        mutate { s in
            if let i = s.reservations.firstIndex(where: { $0.id == id }) {
                let before = s.reservations[i]
                s.reservations[i].status = status
                result = s.reservations[i]
                s.history.append(ReservationHistoryEntry(reservationId: id, before: before, after: s.reservations[i], timestamp: Self.nowISO()))
            }
        }
        return result
    }

    /// 현재 시각 ISO8601 문자열(이력 timestamp용).
    private static func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }

    /// 예약 영구 삭제.
    func deleteReservation(id: Int) {
        mutate { $0.reservations.removeAll { $0.id == id } }
    }

    /// 고객 등록/수정(id 기준 upsert).
    @discardableResult
    func upsertCustomer(_ customer: Customer) -> Customer {
        mutate { s in
            if let i = s.customers.firstIndex(where: { $0.id == customer.id }) {
                s.customers[i] = customer
            } else {
                s.customers.append(customer)
            }
        }
        return customer
    }

    /// 고객 병합 — source를 target으로 합친다(웹 /api/customers/merge와 동일 규칙).
    /// 예약 이전 + 적립금 합산 + 적립 이력 병합 + 첫방문일 최소 + 메모태그 병합(중복 제외) + source 삭제.
    @discardableResult
    func mergeCustomers(sourceId: Int, targetId: Int) -> Bool {
        guard sourceId != targetId else { return false }
        var ok = false
        mutate { s in
            guard let si = s.customers.firstIndex(where: { $0.id == sourceId }),
                  let ti = s.customers.firstIndex(where: { $0.id == targetId }) else { return }
            let source = s.customers[si]
            var target = s.customers[ti]
            // 예약 이전
            for i in s.reservations.indices where s.reservations[i].customerId == sourceId {
                s.reservations[i].customerId = targetId
            }
            // 적립금 합산 + 이력 병합
            target.points = (target.points ?? 0) + (source.points ?? 0)
            target.pointHistories = (target.pointHistories ?? []) + (source.pointHistories ?? [])
            // 첫 방문일 = 더 이른 날짜
            target.firstVisitDate = Self.earliest(target.firstVisitDate, source.firstVisitDate)
            // 메모태그 병합(text 중복 제외)
            let existing = Set((target.memoTags ?? []).map(\.text))
            let merged = (target.memoTags ?? []) + (source.memoTags ?? []).filter { !existing.contains($0.text) }
            target.memoTags = merged.isEmpty ? nil : merged
            s.customers[ti] = target
            s.customers.removeAll { $0.id == sourceId }
            ok = true
        }
        return ok
    }

    /// 두 날짜 문자열("YYYY-MM-DD") 중 이른 것. 한쪽이 nil이면 다른 쪽.
    private static func earliest(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case let (x?, y?): return x < y ? x : y
        default: return a ?? b
        }
    }

    /// 담당자 목록 전체 저장(웹 PUT /api/assignees와 동일한 일괄 교체 모델).
    @discardableResult
    func saveAssignees(_ assignees: [Assignee]) -> [Assignee] {
        mutate { $0.assignees = assignees }
        return assignees
    }

    /// 담당자 병합 — source의 예약을 target으로 옮기고 source 삭제(웹 /api/assignees/merge).
    @discardableResult
    func mergeAssignees(sourceId: Int, targetId: Int) -> Bool {
        guard sourceId != targetId else { return false }
        var ok = false
        mutate { s in
            guard s.assignees.contains(where: { $0.id == sourceId }),
                  s.assignees.contains(where: { $0.id == targetId }) else { return }
            for i in s.reservations.indices where s.reservations[i].assigneeId == sourceId {
                s.reservations[i].assigneeId = targetId
            }
            s.assignees.removeAll { $0.id == sourceId }
            ok = true
        }
        return ok
    }

    /// 담당자 삭제 — 스케줄은 함께 사라지고, 예약은 보존하되 assigneeId를 분리(nil)한다(웹과 동일).
    func deleteAssignee(id: Int) {
        mutate { s in
            s.assignees.removeAll { $0.id == id }
            for i in s.reservations.indices where s.reservations[i].assigneeId == id {
                s.reservations[i].assigneeId = nil
            }
        }
    }

    /// 서비스 카탈로그 + 카테고리 색 전체 저장(웹 PUT /api/services).
    @discardableResult
    func saveServices(_ services: [ServiceItem], categoryBaseColors: [String: String]) -> ServicesResponse {
        mutate { s in
            s.services = services
            s.categoryBaseColors = categoryBaseColors
        }
        return ServicesResponse(services: services, categoryBaseColors: categoryBaseColors)
    }

    /// 매장 기본 정보 저장(이름·기능 토글) — 웹 PATCH /api/store에 대응하는 로컬 버전.
    @discardableResult
    func updateStoreSettings(name: String, shopType: String?, usePointSystem: Bool, useMembershipSystem: Bool, useOnlineBooking: Bool) -> Store {
        mutate { s in
            s.storeName = name
            s.shopType = shopType
            s.usePointSystem = usePointSystem
            s.useMembershipSystem = useMembershipSystem
            s.useOnlineBooking = useOnlineBooking
        }
        return syntheticStore
    }

    /// 다음 예약/고객/담당자 정수 id(현재 최대 +1) — 폼에서 신규 레코드 id 부여용.
    var nextReservationId: Int { (snapshot.reservations.map(\.id).max() ?? 0) + 1 }
    var nextCustomerId: Int { (snapshot.customers.map(\.id).max() ?? 0) + 1 }
    var nextAssigneeId: Int { (snapshot.assignees.map(\.id).max() ?? 0) + 1 }

    // MARK: - Read envelopes (TASService가 API 응답 대신 반환)

    var reservationsResponse: ReservationsResponse {
        ReservationsResponse(reservations: snapshot.reservations, history: snapshot.history)
    }

    var customersResponse: CustomersResponse {
        CustomersResponse(customers: snapshot.customers)
    }

    var servicesResponse: ServicesResponse {
        ServicesResponse(services: snapshot.services, categoryBaseColors: snapshot.categoryBaseColors)
    }

    var assigneesResponse: AssigneesResponse {
        AssigneesResponse(assignees: snapshot.assignees)
    }

    /// 게스트용 합성 매장 — 로그인 매장 대신 스냅샷 정보로 구성.
    var syntheticStore: Store {
        Store(
            id: "guest",
            name: snapshot.storeName ?? "게스트 매장",
            shopType: snapshot.shopType,
            onboarded: snapshot.onboarded,
            usePointSystem: snapshot.usePointSystem,
            useMembershipSystem: snapshot.useMembershipSystem,
            useCouponSystem: snapshot.useCouponSystem,
            useOnlineBooking: snapshot.useOnlineBooking,
            bookingSlug: nil,
            categoryBaseColors: snapshot.categoryBaseColors,
            businessHours: snapshot.businessHours,
            closedDates: snapshot.closedDates,
            closedWeekdays: snapshot.closedWeekdays,
            pointSettings: snapshot.pointSettings
        )
    }

    /// 영업시간·휴무 저장(웹 PUT /api/store storeSettings에 대응).
    @discardableResult
    func updateSchedule(businessHours: BusinessHours, closedDates: [String], closedWeekdays: [Int]) -> Store {
        mutate { s in
            s.businessHours = businessHours
            s.closedDates = closedDates
            s.closedWeekdays = closedWeekdays
        }
        return syntheticStore
    }

    /// 적립금 설정 저장.
    @discardableResult
    func updatePointSettings(_ settings: PointSettings) -> Store {
        mutate { $0.pointSettings = settings }
        return syntheticStore
    }
}
