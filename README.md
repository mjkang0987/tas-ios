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
2. the default `https://takeaseat.app`.

For local web development, set it to `http://localhost:3000` (add an ATS
exception for HTTP, or run the backend over HTTPS).

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

## Next steps (TODO)

- [ ] Implement the OAuth login flow via `ASWebAuthenticationSession`
      (`/api/auth/signin/<google|kakao|naver>`) in `LoginView`.
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
