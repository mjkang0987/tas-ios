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
            categoryBaseColors: snapshot.categoryBaseColors
        )
    }
}
