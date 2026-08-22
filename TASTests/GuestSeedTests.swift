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
    private static let seedPath = "TASTests/Fixtures/guest-seed.json"
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // TASTests/
        .deletingLastPathComponent()      // repo root
    private static let seedURL = GuestSeedTests.repoRoot.appendingPathComponent(GuestSeedTests.seedPath)

    private static let sampleDay = "2026-08-21"

    private func rawSeed() throws -> String {
        try String(contentsOf: Self.seedURL, encoding: .utf8)
    }

    private func loadSeed(date: String = GuestSeedTests.sampleDay) throws -> GuestSnapshot {
        let json = try rawSeed().replacingOccurrences(of: Self.todayToken, with: date)
        return try JSONDecoder().decode(GuestSnapshot.self, from: Data(json.utf8))
    }

    /// 워크플로가 치환하는 토큰이 실제로 파일에 있어야 한다(없으면 sed가 조용히 아무것도 안 한다).
    func testSeedCarriesTodayToken() throws {
        XCTAssertTrue(try rawSeed().contains(Self.todayToken))
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
        XCTAssertTrue(snapshot.hasData)   // SessionStore.bootstrap이 게스트로 복귀하는 조건
    }

    func testSeededReservationsAreOnTheGivenDay() throws {
        let snapshot = try loadSeed()
        XCTAssertEqual(Set(snapshot.reservations.map(\.date)), [Self.sampleDay])
    }

    /// 일 타임라인은 블록이 54pt를 넘어야 시술 칩을 그린다(56pt = 60분).
    /// 전부 60분 미만이면 칩이 하나도 안 보이는 스크린샷이 나온다.
    func testSeededReservationsAreLongEnoughToShowChips() throws {
        let snapshot = try loadSeed()
        for r in snapshot.reservations {
            guard let start = ReservationOverlap.minutes(r.startTime),
                  let end = ReservationOverlap.minutes(r.endTime) else {
                return XCTFail("시간 형식이 잘못됐다: \(r.startTime)~\(r.endTime)")
            }
            XCTAssertGreaterThanOrEqual(end - start, 60, r.service)
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

    /// 워크플로가 심는 파일명과 앱이 읽는 파일명이 같은지.
    ///
    /// 갈리면 앱은 로그인 화면으로 떨어지는데 `test -s`도, JSON 파싱도, 이 파일의 다른
    /// 테스트도 전부 통과한다 — 이 시드가 막으려던 바로 그 조용한 실패다.
    func testScreenshotWorkflowSeedsTheFileTheAppReads() throws {
        let workflow = Self.repoRoot.appendingPathComponent(".github/workflows/ios-screenshot.yml")
        let yaml = try String(contentsOf: workflow, encoding: .utf8)

        XCTAssertTrue(yaml.contains(LocalStore.fileName),
                      "워크플로가 \(LocalStore.fileName)이 아닌 이름으로 시드를 심고 있다")
        XCTAssertTrue(yaml.contains(Self.seedPath),
                      "워크플로가 이 테스트가 검증하는 시드 파일을 쓰고 있지 않다")
    }
}
