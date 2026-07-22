# plan.md — tas-ios

> takeaseat(TAS) iOS 클라이언트의 태스크 소스오브트루스.
> 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas). 구조·현황은 `README.md`, 버전 규약은 `CLAUDE.md` 참고.
>
> _기준: `main` · 상태 표기_ ⬜ 예정 · 🟡 진행 · ✅ 완료

---

## 0. 현재 상태 (완료됨)

- ✅ 앱 뼈대: SwiftUI · MVVM(`@Observable`) · Xcode 16 프로젝트
- ✅ 도메인 모델: Reservation / Service / Customer / Assignee / Store (+ enum) — 웹 `client/features/*/model.ts` 미러링
- ✅ 네트워킹: `APIClient`(async/await, 쿠키 세션) · `TASService`(타입드 엔드포인트) · `Loadable` · `APIError`
- ✅ 세션: `SessionStore`(부트스트랩 + 로그아웃)
- ✅ 화면(읽기): 로그인 게이트 → 탭(캘린더 일단위 · 고객 · 서비스 · 설정)
- ✅ 버전 규약: `MARKETING_VERSION` 0.0.0 시작 / `CURRENT_PROJECT_VERSION` 1부터(+1 per TestFlight)

**한계**: 로그인은 자리표시자(OAuth 미연결) → 실데이터 미로드. 쓰기(생성/수정) 전무. 테스트 없음.

---

## Phase 0 — 인증 & 세션  🔴 P0 (블로커)

> 이게 뚫려야 캘린더·고객이 실제 서버 데이터를 로드한다.

- ⬜ **OAuth 로그인** — `ASWebAuthenticationSession`으로 `/api/auth/signin/<google|kakao|naver>` 인증 → 세션 쿠키 수신 → `SessionStore.didCompleteLogin()`
  - 관련 파일: `Features/Login/LoginView.swift`, `Core/Session/SessionStore.swift`
  - `WKWebView`/`ASWebAuthenticationSession` 콜백에서 `HTTPCookieStorage`로 쿠키 이전
- ⬜ **초대코드 처리** — `tas-invite-code` 쿠키 세팅(초대 링크/코드 입력) — GUIDE §1-1
- ⬜ **약관 동의 게이트** — 미동의 시 `/consent` 흐름, `POST /api/consent`
- ⬜ **온보딩 게이트** — 매장 미설정 시 안내(웹 `/onboarding`로 유도 또는 네이티브 최소 폼)
- ⬜ 로그인 오류 처리 — `no-account` / `OAuthAccountNotLinked` / `sync-error` / 초대코드 오류

## Phase 1 — 핵심 기능 (읽기→쓰기)  🟠 P1

### 예약
- ⬜ 예약 생성 폼 — `POST /api/reservations` (고객·담당자·서비스·시간·결제)
- ⬜ 예약 수정/취소/복구 — `PUT/PATCH /api/reservations`
- ⬜ 결제 입력 — `paymentEntries`(다건), `paymentMethod`
- ⬜ 시간 겹침 감지 — `findOverlap` 로직 포팅(모델 유틸)
- ⬜ 담당자 필터 · 서비스 색상 범례
- ⬜ 주 / 월 / 년 뷰 (현재 일단위만)

### 고객
- ⬜ 고객 상세 화면 (방문/취소/노쇼 통계)
- ⬜ 적립금 충전 · 이력 (`pointHistories`)
- ⬜ 메모 태그(색상) 부여/편집
- ⬜ 고객 병합 / 병합해제 — `/api/customers/merge`·`/unmerge`

### 담당자(디자이너)
- ⬜ 담당자 CRUD + 근무 스케줄 + 색상 — `GET/PUT/DELETE /api/assignees`

## Phase 2 — 운영 & 설정  🟡 P2

- ⬜ 매출 분석(디자이너별·기간별 KPI)
- ⬜ 서비스 카탈로그 편집(오너) — `PUT /api/services`
- ⬜ 회원권 / 쿠폰 — `/api/memberships`·`/api/coupons`
- ⬜ 온라인예약 토글·슬러그·노출 서비스 — `PUT /api/store`
- ⬜ 영업시간 · 휴무일 설정
- ⬜ 멤버 / 초대 관리 — `/api/members`·`/api/invites`
- ⬜ SNS 계정 연결 — `/api/account/*`

## Phase 3 — 인프라 & 품질  ⚪ P3

- ⬜ 유닛 테스트(모델·`APIClient`) + UI 테스트
- ⬜ CI: Xcode 빌드/테스트 워크플로 (`.github/workflows`)
- ⬜ ATS 설정(로컬 HTTP 개발) · 앱 아이콘 에셋
- ⬜ fastlane / TestFlight 업로드 자동화(빌드 번호 +1)
- ⬜ 게스트 모드(로컬 저장) — 웹 localStorage 대응(선택)

---

## 작업 규약 (tas 컨벤션 준용)

- 이슈당 브랜치(`claude/issue-<번호>-<슬러그>`) · 이슈당 PR, 본문에 `Closes #<이슈>`
- 라벨: `feature`/`fix`/`chore`/`refactor`/`docs` + `phase-0`~`phase-3`
- 하위 작업 3개 이상이면 상위(에픽) 이슈 + 서브이슈
- 머지 시 버전 범프(`CLAUDE.md` 규약): `MARKETING_VERSION` semver / TestFlight 업로드마다 빌드 번호 +1
- 검증: 항상 빌드/타입체크, 런타임 변경은 시뮬레이터 구동 확인
