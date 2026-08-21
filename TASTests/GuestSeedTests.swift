import XCTest
@testable import TAS

/// `TASTests/Fixtures/guest-seed.json` 검증 — 스크린샷 CI가 심는 게스트 스냅샷.
///
/// **왜 테스트가 필요한가:** `LocalStore.load`는 디코딩에 실패하면 조용히 `nil`을 돌려주고
/// 앱은 로그인 화면으로 떨어진다(`LocalStore.swift:38`). 시드가 스키마와 어긋나도 스크린샷
/// 워크플로는 성공한 채 **엉뚱한 화면**을 올린다. 그래서 어긋남을 여기서 먼저 깨뜨린다.
/// (실제로 이 테스트를 쓰다가 `paymentMethod`를 `"card"`로 적은 걸 잡았다 — raw value는 "카드".)
///
/// 번들 리소스가 아니라 `#filePath` 기준으로 원본 파일을 읽는다 — 워크플로가 쓰는 파일과
/// 테스트가 읽는 파일이 **같은 하나**여야 검증이 의미가 있기 때문.
final class GuestSeedTests: XCTestCase {

    private static let todayToken = "__TODAY__"

    private func loadSeed(date: String = "2026-08-21") throws -> GuestSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/guest-seed.json")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let json = raw.replacingOccurrences(of: Self.todayToken, with: date)
        return try JSONDecoder().decode(GuestSnapshot.self, from: Data(json.utf8))
    }

    /// 워크플로가 치환하는 토큰이 실제로 파일에 있어야 한다(없으면 sed가 조용히 아무것도 안 한다).
    func testSeedCarriesTodayToken() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/guest-seed.json")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains(Self.todayToken))
    }

    func testSeedDecodesIntoSnapshot() throws {
        let snapshot = try loadSeed()
        XCTAssertFalse(snapshot.services.isEmpty)
        XCTAssertFalse(snapshot.reservations.isEmpty)
        XCTAssertFalse(snapshot.customers.isEmpty)
        XCTAssertFalse(snapshot.assignees.isEmpty)
    }

    /// 이 둘이 아니면 앱이 캘린더가 아니라 약관 동의/온보딩 화면을 띄운다(`RootView`).
    func testSeedLandsOnCalendarNotOnboarding() throws {
        let snapshot = try loadSeed()
        XCTAssertTrue(snapshot.onboarded)
        XCTAssertEqual(snapshot.termsAgreedVersion, GuestStore.currentTermsVersion)
        XCTAssertTrue(snapshot.hasData)   // SessionStore.restore가 게스트로 복귀하는 조건
    }

    func testSeededReservationsAreOnTheGivenDay() throws {
        let snapshot = try loadSeed(date: "2026-08-21")
        XCTAssertEqual(Set(snapshot.reservations.map(\.date)), ["2026-08-21"])
    }

    /// 일 타임라인은 블록이 54pt를 넘어야 시술 칩을 그린다(56pt = 60분).
    /// 전부 60분 미만이면 칩이 하나도 안 보이는 스크린샷이 나온다.
    func testSeededReservationsAreLongEnoughToShowChips() throws {
        let snapshot = try loadSeed()
        for r in snapshot.reservations {
            XCTAssertGreaterThanOrEqual(minutes(r.endTime) - minutes(r.startTime), 60, r.service)
        }
    }

    /// 시드가 칩을 실제로 보여주는지: 같은 카테고리 안에서 색이 갈리고, '+' 조합이 쪼개진다.
    func testSeedExercisesServiceChips() throws {
        let snapshot = try loadSeed()
        let map = ServiceColor.buildServiceColorMap(
            catalog: snapshot.services,
            storeMap: snapshot.categoryBaseColors
        )
        XCTAssertNotEqual(map["남성커트"], map["여성커트"])

        let combined = snapshot.reservations.filter { $0.service.contains("+") }
        XCTAssertFalse(combined.isEmpty, "조합 시술이 없으면 칩 분리를 확인할 수 없다")

        for r in snapshot.reservations {
            let names = ServiceColor.parseServiceString(r.service, knownNames: Set(map.keys))
            for name in names {
                XCTAssertNotEqual(ServiceColor.serviceHex(name, in: map), ServiceColor.fallbackHex,
                                  "\(name)이 카탈로그에 없어 폴백 회색으로 그려진다")
            }
        }
    }

    private func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
}
