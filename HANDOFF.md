# tas-ios 앞으로 할 작업 (핸드오프)

> 다른 세션에서 이어서 작업하기 위한 문서. 최우선은 **로그인(구글 먼저)**.
> 게스트 기반 운영 기능은 사실상 완성 상태이고, 남은 건 대부분 **로그인/외부 연동**이라
> provider 키·환경변수 준비가 선행돼야 실제 동작·검증이 됩니다.

---

## 0. 프로젝트 컨텍스트 (빠른 시작)

| 항목 | 값 |
|------|-----|
| iOS 저장소 | `mjkang0987/tas-ios` |
| 작업 브랜치 | `claude/tas-service-ios-stlzh4` (작업 브랜치이자 default) |
| 백엔드/웹 | `mjkang0987/tas` (Next.js + **NextAuth v5(Auth.js)**), `/workspace/tas` |
| 앱 스킴 | `tasios://auth/callback?code=…` (콜백), `AuthDeepLink.scheme = "tasios"` |
| 번들 ID | `kr.co.takeaseat.app` |
| API 주소 | `https://takeaseat.co.kr` (dev: `https://dev.takeaseat.co.kr`) — `AppConfig.apiBaseURL` |

**빌드/CI**
- Xcode 프로젝트는 **커밋된 `TAS.xcodeproj`** + **synchronized filesystem groups**(Xcode 16).
  → `TAS/` 아래 새 파일은 pbxproj 수정 없이 자동 포함됨. (예외: `Info.plist`)
- CI: `.github/workflows/ios-build.yml`(macOS, 시뮬레이터 빌드 검증) — 푸시마다 실행.
- TestFlight: 커밋 메시지에 `[tf]` 포함하면 `testflight.yml`이 아카이브→서명→업로드.
- 로컬에서 xcodebuild 불가 → **푸시 후 CI green으로 검증**. 푸시 전 심볼 참조/괄호 균형은 수동 점검(아래 §6).

**게스트 vs 로그인 아키텍처 (핵심)**
- `GuestStore.shared.isActive`면 게스트(오프라인 로컬 스냅샷), 아니면 로그인(API Bearer).
- 모든 화면은 `TASService`만 거치고, `TASService`가 `if guest.isActive { 로컬 } else { API }`로 분기.
- 게스트 스냅샷: `GuestSnapshot`(Documents JSON), CRUD는 `GuestStore`.

---

## 1. 완료 현황 (green)

**게스트 기반 운영 기능 — 웹과 정합**
- 진입: 로그인 화면 → **약관 동의** → 온보딩 → 메인
- 캘린더: 일(**시간축 타임라인**)/주/월/년, 담당자 필터, 월·년 하단 예약 리스트
- 예약: 생성·수정·취소·노쇼·예약전환·삭제·**결제(결제완료/예약완료)**·**변경 이력**
- 고객: 등록·수정·**적립금 조정**·**병합**
- 담당자: 추가·수정·삭제·근무시간·**병합**
- 서비스: 카탈로그 CRUD (설정 하위)
- 매장: 이름·업종·기능토글·**영업시간/휴무**·**적립률/충전 설정**
- 결제 시 **적립률 기반 자동 적립**(고객 크레딧 + 이력)
- 설정 > 관리: **공지 / 쿠폰(상품) / 회원권(상품)** (쿠폰·회원권은 웹도 상품 등록까지)
- **Store 디코딩 버그 수정 완료**(로그인 대비): `storeName→name` 매핑 + `id` 누락 허용

---

## 2. ★ 로그인 구현 (구글 먼저) — 최우선

### 2-1. 현재 아키텍처 (이미 앱에 코드 있음)
**웹 위임(ASWebAuthenticationSession) 방식**이 이미 구현돼 있음:
```
LoginView 버튼 → SessionStore.signIn(provider:invite:)
  → WebAuthSession(ASWebAuth)로 웹 /login?nonce&provider 열기
  → 소셜 OAuth는 웹의 NextAuth가 처리
  → 콜백 tasios://auth/callback?code=…
  → TASService.exchangeMobileCode → POST /api/mobile-auth/exchange
  → access 토큰(Bearer) → Keychain 저장 → 세션 로드
```
즉 **iOS에 소셜 SDK가 없어도** 웹 NextAuth에 provider만 켜지면 로그인이 됩니다.

### 2-2. 왜 지금 안 되나 (블록 원인)
웹 `client/auth.ts`에서 provider는 환경변수가 있고 값이 `REPLACE…`가 아닐 때만 켜짐:
```ts
if (process.env.AUTH_GOOGLE_ID && !process.env.AUTH_GOOGLE_ID.startsWith('REPLACE'))
    providers.push(Google({ clientId: AUTH_GOOGLE_ID, clientSecret: AUTH_GOOGLE_SECRET }))
```
현재 `AUTH_GOOGLE_ID` 등이 플레이스홀더라 **구글 로그인 버튼이 동작 안 함**.

### 2-3. 👤 사용자(당신)가 준비할 것 — 구글
1. **Google Cloud Console** → 프로젝트 선택/생성
2. **OAuth 동의 화면** 구성 (앱 이름, 지원 이메일, 승인된 도메인 `takeaseat.co.kr`)
3. **사용자 인증 정보 → OAuth 2.0 클라이언트 ID → "웹 애플리케이션"** 생성
   - 승인된 리디렉션 URI에 추가:
     - `https://takeaseat.co.kr/api/auth/callback/google`
     - (dev도 쓰면) `https://dev.takeaseat.co.kr/api/auth/callback/google`
4. 발급된 **클라이언트 ID / 시크릿**을 tas 웹 배포 환경변수에 설정:
   - `AUTH_GOOGLE_ID = <클라이언트 ID>`
   - `AUTH_GOOGLE_SECRET = <클라이언트 시크릿>`
5. **tas 웹 재배포** (env 반영)
> 카카오·네이버도 동일 패턴: 각 개발자 콘솔에서 OAuth 앱 생성 → redirect URI
> `…/api/auth/callback/kakao`, `…/api/auth/callback/naver` → `AUTH_KAKAO_ID/SECRET`,
> `AUTH_NAVER_ID/SECRET` 설정.

### 2-4. 🤖 다음 세션(Claude)이 할 것 — 코드
- [ ] 웹 `/login`이 **모바일 콜백**(`nonce`/`provider` 파라미터 → 성공 시 `tasios://auth/callback?code=` 리디렉트)을 지원하는지 확인. 미비하면 tas 웹에 구현 (`/api/mobile-auth/*` 브리지는 이미 존재).
- [ ] 앱 `SessionStore.signIn` → `exchangeMobileCode` **E2E 동작 검증**(구글로 1회 로그인 → 매장 로드 → 게스트 종료).
- [ ] 로그인 성공 후 **#3(이관) 트리거** 연결(아래 §3).
- [ ] 실패 케이스(사용자 취소/`no_store`/`no_session`) 메시지 확인 — 이미 `SessionStore.message(for:)`에 있음.

### 2-5. (선택) 완전 네이티브 SDK로 고도화
사용자가 "웹 시트도 싫고 완전 네이티브"를 원하면:
- 👤 사용자: Google Cloud **OAuth 클라이언트 ID(iOS 타입)** 생성(번들 `kr.co.takeaseat.app`) → iOS 클라이언트 ID + reversed client ID
- 🤖 Claude:
  - `GoogleSignIn` SPM 추가 (project는 커밋된 pbxproj라 **패키지 의존성 추가가 필요** — SPM package reference를 pbxproj에 넣거나 project.yml+xcodegen 재생성 경로 검토)
  - Info.plist `CFBundleURLSchemes`에 reversed client ID 추가
  - 네이티브 로그인 매니저(구글 id_token 획득)
  - **백엔드 신규 엔드포인트**: 네이티브 `id_token`을 검증하고 TAS 세션(Bearer) 발급 (현재 `mobile-auth/exchange`는 웹 `code`용이라 별도 필요)
- ⚠️ 웹 위임 방식보다 작업량 크고 백엔드 변경 필요. **먼저 §2-3~2-4로 동작시키고 나중에 고도화 권장.**

---

## 3. 게스트 → 로그인 데이터 이관 (#21)

- 엔드포인트: `POST /api/migrate-local` (Bearer + **owner** 권한).
  - body: `{ shopName, shopType, services, assignees, customers, reservations, confirm? }`
    → `GuestSnapshot` 필드가 그대로 매핑됨.
  - 이미 매장 데이터가 있으면 **409 `ALREADY_SETUP`** → `confirm: true`로 재전송해야 덮어씀.
- 🤖 작업: 로그인 성공 직후 게스트 데이터가 있으면
  "게스트 데이터를 계정으로 옮길까요?" → 예 → 스냅샷 전송 → 성공 시 `GuestStore.reset()/deactivate()`.
  409면 "이미 매장 데이터가 있습니다. 덮어쓸까요?" 재확인 → `confirm:true`.
- 👤 사용자: 없음(로그인만 되면 검증 가능). **키 없이 로직은 미리 구현 가능**, 검증은 로그인 열릴 때.

---

## 4. 남은 로그인 전용 연동 (#22, #23)

전부 로그인 세션이 있어야 의미. 각 항목별 필요한 키/설정:

| 기능 | 필요한 것 |
|------|-----------|
| SNS 계정 연동 | 위 소셜 provider 키(§2-3) |
| 멤버 관리·초대코드 | 로그인(owner). 추가 키 없음. `/api/members`, `/api/invites` |
| 네이버 예약 동기화 | **Gmail OAuth**(`AUTH_GOOGLE_ID/SECRET` + Gmail 범위) + `/api/gmail/*`, `/api/naver-booking-sync`. 네이버 예약메일 파싱 기반 |
| 온라인 예약 설정 | 로그인. 공개 예약 페이지 `book/[slug]`는 **웹 전용 유지**(앱은 설정만) |
| 마이페이지/계정 | 닉네임 `/api/user/nickname`, 탈퇴 `/api/account/delete`, 문의 `/api/inquiry` |

---

## 5. 나중에 / 선택 항목

- **쿠폰·회원권 발급·차감**: 웹도 "추후 지원" 상태. (지금은 상품 등록까지만.) 발급(고객에게)·결제 차감까지 하려면 웹/앱 양쪽 신규 작업.
- **캘린더 타임라인 확장**: 현재 일(day) 뷰만 타임라인. 주(week) 뷰 타임라인은 모바일 7칼럼이 좁아 보류 권장. 일 타임라인에 **담당자별 칼럼** 분리는 담당자 수 적으면 유효.
- **디자인**: 현재 네이티브 골격 + 웹 시각언어(색·용어·뱃지). 픽셀 매칭은 비권장(모바일 이점 상실). 필요 시 특정 화면만 폴리시.

---

## 6. 작업 규칙 (놓치기 쉬운 것)

- **푸시 전 검증**: 로컬 빌드 불가 → 심볼 참조(다른 타입의 static/메서드명), 괄호/중괄호 균형을 꼭 확인. (과거 `ShopIndustry.defaultSchedule`(실제 `ShopCatalog`) 오참조, `.secondary`/`.orange` ShapeStyle 삼항 혼용 등으로 빌드 깨진 적 있음.)
- **탭이 아닌 push 화면**은 자체 `NavigationStack` 넣지 말 것(설정에서 push → 중첩됨). 탭 루트(캘린더/고객/설정)만 자체 NavigationStack.
- 색 삼항은 `Color.x : Color.y`로 통일(ShapeStyle 혼용 금지).
- 커밋 후 CI green 확인 → 사용자 테스트용은 `[tf]`로 TestFlight.
- 웹 정합: 색·라벨·판정 로직은 하드코딩 말고 `/workspace/tas`(웹)에서 이식.

**핵심 파일**
- 라우팅/탭: `TAS/App/RootView.swift`
- 세션/로그인: `TAS/Core/Session/SessionStore.swift`, `TAS/Features/Login/*`(LoginView, WebAuthSession, AuthDeepLink), `TAS/Core/Config/AppConfig.swift`
- 데이터 분기: `TAS/Core/Networking/TASService.swift`, `TAS/Core/Storage/GuestStore.swift` + `GuestSnapshot.swift`
- 캘린더: `TAS/Features/Calendar/*` (CalendarView, DayTimelineView, ReservationDetail/Create/Payment/HistoryView)
- 설정: `TAS/Features/Settings/*`

---

### 다음 세션 첫 스텝 제안
1. (사용자) §2-3 구글 OAuth + `AUTH_GOOGLE_ID/SECRET` 설정 + tas 웹 재배포
2. (Claude) §2-4 웹 `/login` 모바일 콜백 확인/보완 → 구글 로그인 E2E
3. (Claude) §3 이관 로직 구현 → 로그인 후 게스트 데이터 이관 검증
