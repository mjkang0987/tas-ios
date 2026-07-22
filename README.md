# TAS iOS

Native **SwiftUI** iOS client for **takeaseat (TAS)** — a hair-salon
reservation / customer / revenue management service. This repository is the
iOS counterpart to the web service in [`mjkang0987/tas`](https://github.com/mjkang0987/tas),
and its models and networking mirror that backend's `/api/*` surface.

> This is an app **skeleton**: the architecture, domain models, networking
> layer, and primary screens are in place and build in Xcode. Business logic
> such as the OAuth login flow and write/mutation forms are stubbed with clear
> `TODO`s to fill in.

## Requirements

- Xcode 16+
- iOS 17.0+ deployment target

## Getting started

```bash
open TAS.xcodeproj
```

Select the **TAS** scheme and run on a simulator. On launch the app calls
`GET /api/store` to detect an existing session; without one it shows the login
gate.

### Point at your backend

The API base URL resolves in this order (`Core/Config/AppConfig.swift`):

1. `TAS_API_BASE_URL` in Info.plist (set per build configuration), else
2. the default `https://takeaseat.co.kr` (production).

Environments:

| Env    | URL                            |
|--------|--------------------------------|
| prod   | `https://takeaseat.co.kr`      |
| dev    | `https://dev.takeaseat.co.kr`  |
| local  | `http://localhost:3000`        |

To target dev/local, set `TAS_API_BASE_URL` (e.g. a Debug-only
`INFOPLIST_KEY_TAS_API_BASE_URL` build setting) — no code change needed. For
local HTTP, add an ATS exception (or run the backend over HTTPS).

## Project layout

```
TAS/
  App/                 앱 진입점 · 루트 라우팅 (로그인 게이트 → 탭)
  Core/
    Config/            AppConfig — API base URL 등 설정
    Networking/        APIClient · TASService · Loadable · APIError
    Session/           SessionStore — 인증/매장 컨텍스트 (@Observable)
  Models/              Reservation · Service · Customer · Assignee · Store
                       (client/features/*/model.ts 미러링)
  Features/
    Login/             소셜 로그인 화면 (OAuth 흐름 TODO)
    Calendar/          예약 일 단위 뷰  (GET /api/reservations)
    Customers/         고객 주소록      (GET /api/customers)
    Services/          서비스 카탈로그   (GET /api/services)
    Settings/          매장 정보 · 로그아웃 (GET /api/store)
  Resources/           Assets.xcassets (AppIcon, AccentColor)
```

## Architecture

- **MVVM** with `@Observable` view models per feature.
- `APIClient` is a thin async/await HTTP layer; session auth rides on the
  shared `HTTPCookieStorage` (NextAuth cookie), matching the web app.
- `TASService` exposes typed endpoint methods documented against the `tas`
  repo's `index.md` (§백엔드 API).
- `Loadable<Value>` drives idle / loading / loaded / failed UI states.

## Backend endpoints used

| Screen    | Endpoint                | Method |
|-----------|-------------------------|--------|
| 캘린더    | `/api/reservations`     | GET    |
| 고객      | `/api/customers`        | GET    |
| 서비스    | `/api/services`         | GET    |
| 설정      | `/api/store`            | GET    |
| 담당자    | `/api/assignees`        | GET    |

## 로그인 (구현됨 — 모바일 인증 브리지)

clipnote-ios와 동일한 구조: `ASWebAuthenticationSession`(진짜 Safari)으로 웹
`/login`을 열어 소셜 로그인하고, `tasios://auth/callback?code=`를 받아
`/api/mobile-auth/exchange`에서 **Bearer 토큰**으로 교환해 Keychain에 보관한다.
이후 모든 `APIClient` 요청에 `Authorization: Bearer`가 붙는다.

- 흐름·계약: [`docs/auth-mobile-bridge.md`](docs/auth-mobile-bridge.md)
- 관련 파일: `Features/Login/{WebAuthSession,AuthDeepLink,LoginView}.swift`,
  `Core/Session/{SessionStore,KeychainTokenStore,MobileToken}.swift`
- 커스텀 스킴 `tasios`는 `TAS/Info.plist`(`CFBundleURLTypes`)에 등록.

> ✅ 진짜 Safari 컨텍스트라 **Google OAuth도 정상 동작**(임베디드 웹뷰 차단 문제 없음).
> Kakao/Naver 포함 3사 모두 지원.
>
> ⚠️ **백엔드 의존**: `tas` 저장소의 모바일 브리지 엔드포인트
> (`/api/mobile-auth/{complete,exchange}`)가 배포되어야 실제 로그인이 된다.

## Next steps (TODO)

- [ ] provider별 네이티브 버튼(현재는 웹 `/login`에서 선택) — 백엔드 `start?provider=` 추가 시
- [ ] 초대코드 / 약관 동의 / 온보딩 게이트 (issues #7 #8 #9)
- [ ] Reservation create/edit forms (POST/PUT `/api/reservations`).
- [ ] Customer detail + point history.
- [ ] Assignee (designer) filter on the calendar.
- [ ] Week / month calendar views.
- [ ] Unit tests for models and `APIClient`.

## Regenerating the project

`TAS.xcodeproj` is committed and uses Xcode 16 synchronized folder groups, so
new files under `TAS/` are picked up automatically. A `project.yml`
([XcodeGen](https://github.com/yonaskolb/XcodeGen)) is also provided for
reproducible regeneration:

```bash
brew install xcodegen && xcodegen generate
```
