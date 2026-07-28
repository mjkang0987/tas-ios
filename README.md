# TAS iOS

Native **SwiftUI** iOS client for **takeaseat (TAS)** — a salon
reservation / customer / revenue management service. This repository is the
iOS counterpart to the web service in [`mjkang0987/tas`](https://github.com/mjkang0987/tas);
its models and networking mirror that backend's `/api/*` surface
(`client/features/*/model.ts`).

The app runs in two modes behind one UI:

- **게스트(오프라인) 모드** — 로그인 없이 로컬 스냅샷(`GuestStore`)에 데이터를 저장하며 전 기능 사용.
- **로그인 모드** — 소셜 로그인으로 받은 Bearer 토큰으로 백엔드 `/api/*`를 사용.

`TASService`가 이 둘을 자동 분기하므로 화면 코드는 모드를 몰라도 된다.

## Requirements

- Xcode 16+
- iOS 17.0+ deployment target

## Getting started

```bash
open TAS.xcodeproj
```

**TAS** 스킴을 선택해 시뮬레이터에서 실행. 시작 시 저장된 토큰이 있으면 세션을 복원하고,
없으면 로그인 화면(게스트로 시작 가능)을 보여준다.

### Point at your backend

The API base URL resolves in this order (`Core/Config/AppConfig.swift`):

1. `TAS_API_BASE_URL` in Info.plist (set per build configuration), else
2. the default `https://takeaseat.co.kr` (production).

| Env    | URL                            |
|--------|--------------------------------|
| prod   | `https://takeaseat.co.kr`      |
| dev    | `https://dev.takeaseat.co.kr`  |
| local  | `http://localhost:3000`        |

To target dev/local set `TAS_API_BASE_URL` (e.g. a Debug-only
`INFOPLIST_KEY_TAS_API_BASE_URL` build setting) — no code change needed. For
local HTTP, add an ATS exception (or run the backend over HTTPS).

## Project layout

```
TAS/
  App/                 앱 진입점 · 루트 라우팅 (로그인/게스트 → 온보딩 → 탭)
  Core/
    Config/            AppConfig — API base URL · Google 클라이언트 ID
    Networking/        APIClient · TASService · Loadable · APIError
    Session/           SessionStore · KeychainTokenStore · MobileToken
    Storage/           GuestStore · GuestSnapshot · LocalStore (오프라인 로컬 DB)
    UI/                LoadableView · Badges · FilterChip · ColorAccents · ServiceColor · Formatting
    KST.swift          매장 기준(Asia/Seoul) 날짜 유틸
    ReservationOverlap 담당자 중복 예약(겹침) 판정 공용 유틸
    PointMath          적립금 산식(적립/사용) 공용 유틸
  Models/              Reservation · Customer · Assignee · Service · Store · Notice ·
                       Coupon · Membership · Common (웹 model.ts 미러링)
  Features/
    Login/             소셜 로그인(웹 위임 + 네이티브 Google) · 게스트 시작
    Guest/             약관 동의 · 온보딩
    Calendar/          일(타임라인)/주/월/년 · 예약 생성·수정·결제·이력
    Customers/         고객 CRUD · 병합 · 적립금 조정
    Assignees/         담당자 CRUD · 병합 · 근무시간
    Services/          서비스 카탈로그
    Notices/ Coupons/ Memberships/   설정 하위 관리 화면
    Revenue/           매출(월/년 · 추세 차트 · 담당자별)
    Settings/          매장 정보(기능 토글) · 영업시간 · 적립금 설정 · 온라인예약 설정 · 로그아웃
  Resources/           Assets.xcassets (AppIcon, AccentColor)
TASTests/              유닛 테스트 (XCTest, @testable import TAS)
```

## Architecture

- **MVVM** with `@Observable` view models / stores.
- `APIClient` — thin async/await HTTP layer. 로그인 시 Keychain의 **Bearer 토큰**을
  `Authorization` 헤더로 붙인다(서버 `getApiSession`이 쿠키 대신 인식). 401 시 토큰 폐기.
- `TASService` — 타입 지정 엔드포인트. 게스트 모드면 `GuestStore` 로컬 스냅샷을,
  로그인 모드면 API를 읽고 쓴다(웹 `shouldUseLocalDb()`와 동일 분기).
- `Loadable<Value>` drives idle / loading / loaded / failed UI states.
- 색·라벨·판정·산식은 하드코딩하지 않고 웹 정의를 이식(`ReservationOverlap`,
  `PointMath`, `ServiceColor` 등 공용화). 자세한 컨벤션은 `CLAUDE.md`.

## Authentication

로그인은 **모바일 인증 브리지**로 동작한다(웹 NextAuth 쿠키 세션에 앱을 붙이지 않고 Bearer 토큰 사용):

- **웹 위임(기본)** — `ASWebAuthenticationSession`(진짜 Safari)으로 웹 `/login`을 열어
  소셜 로그인 → `tasios://auth/callback?code=` → `/api/mobile-auth/exchange`로 Bearer 교환.
  Google/Kakao/Naver 3사 지원. 계약: [`docs/auth-mobile-bridge.md`](docs/auth-mobile-bridge.md).
- **네이티브 Google(선택)** — `GoogleSignIn` SDK로 직접 로그인해 id_token을 받아
  `/api/mobile-auth/google`에서 Bearer 교환. `Info.plist`의 `GIDClientID`가 설정되면 활성화,
  없으면 자동으로 웹 위임으로 폴백. 셋업·백엔드 계약: [`docs/GOOGLE_SIGNIN.md`](docs/GOOGLE_SIGNIN.md).
- **게스트 데이터 이관** — 로그인 직후 로컬 게스트 데이터가 있으면 `/api/migrate-local`로
  계정에 이관(이미 매장이 있으면 확인 후 진행).

> ⚠️ **백엔드/키 의존**: 웹 위임은 `tas`의 `/api/mobile-auth/*`가, 네이티브 Google은
> iOS OAuth 클라이언트 ID + `/api/mobile-auth/google`가 준비되어야 실제 로그인이 된다.
> 커스텀 스킴 `tasios`(+ Google 리버스 클라이언트 ID)는 `TAS/Info.plist`에 등록.

## Backend endpoints used

| 도메인 | 엔드포인트 | 메서드 |
|--------|-----------|--------|
| 예약   | `/api/reservations` | GET · POST · PUT · PATCH · DELETE |
| 고객   | `/api/customers`, `/api/customers/merge` | GET · POST |
| 담당자 | `/api/assignees`, `/api/assignees/merge` | GET · PUT · POST · DELETE |
| 서비스 | `/api/services` | GET · PUT |
| 공지·쿠폰·회원권 | `/api/{notices,coupons,memberships}` | GET · POST · PUT · DELETE |
| 쿠폰·회원권 발급 | `/api/{coupon-issue,membership-issue}`, `/api/membership-use` | POST · DELETE (로그인 전용) |
| 매장   | `/api/store`(`?checkSlug=`·`bookingSettings` 포함), `/api/user/stores` | GET · PATCH · PUT |
| 인증   | `/api/mobile-auth/{exchange,google}`, `/api/migrate-local` | POST |

## Testing

유닛 테스트는 `TASTests`(호스티드, `@testable import TAS`)에 있고, 순수 로직 위주로 커버한다:
겹침 판정(`ReservationOverlap`) · Store 디코딩 · 고객/예약 헬퍼 · 매출 집계·추세 ·
게스트 스냅샷 CRUD/병합(`GuestStore`) · 적립 산식(`PointMath`) · 이관 인코딩(`MigrateLocalBody`) ·
업종 카탈로그(`ShopCatalog` — 목록에서 내린 업종의 라벨 해석·Picker 노출) ·
예약 설정 검증·디코딩(`BookingSettings` — 슬러그·연락처 형식, 기본 안내문구, 부분 응답 폴백).

```bash
xcodebuild test -project TAS.xcodeproj -scheme TAS \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI

- `ios-build.yml` — 시뮬레이터 대상 빌드 검증(서명 불필요).
- `ios-test.yml` — 시뮬레이터에서 유닛 테스트 실행.
- `testflight.yml` — 커밋 메시지에 `[tf]`가 있으면 TestFlight 업로드(설정: `docs/TESTFLIGHT.md`).

## Roadmap

진행 상황·다음 작업의 소스오브트루스는 [`plan.md`](plan.md). 요약:

- 🔒 로그인 활성화: iOS OAuth 클라이언트 ID + 백엔드 `/api/mobile-auth/*` 배포
- 🔒 로그인 전용: SNS 연동 · 멤버/초대 · 네이버 예약 동기화
- 🔒 백엔드 신설: 쿠폰·회원권 발급/차감, 온라인 예약 유입
- 출시 준비(App Store Connect), 접근성/다크모드 재점검

## Regenerating the project

`TAS.xcodeproj` is committed and uses Xcode 16 synchronized folder groups, so
new files under `TAS/`·`TASTests/` are picked up automatically. A `project.yml`
([XcodeGen](https://github.com/yonaskolb/XcodeGen)) is also provided for
reproducible regeneration:

```bash
brew install xcodegen && xcodegen generate
```
