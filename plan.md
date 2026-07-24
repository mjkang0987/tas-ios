# plan.md — tas-ios

> takeaseat(TAS) iOS 클라이언트의 태스크 소스오브트루스.
> 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas)(로컬 `/workspace/tas`). 구조는 `README.md`, 버전 규약은 `CLAUDE.md`.
>
> _상태_ ⬜ 예정 · 🟡 진행 · ✅ 완료 · 🔒 외부 준비 필요(키/설정)
> _작업 브랜치이자 default: `claude/tas-service-ios-stlzh4`_

---

## 0. 현재 상태 (완료 ✅ · 게스트 기반 운영 기능은 사실상 완성)

**진입**
- ✅ 로그인 화면(웹 기반 리디자인) → **약관 동의** → 온보딩(업종 선택·기본 서비스 시드) → 메인
- ✅ 게스트 모드: 오프라인 로컬 스냅샷(`GuestStore`/`GuestSnapshot`), 로그아웃 시 데이터 삭제
- ✅ 탭: 캘린더 · 고객 · 설정 (서비스는 설정 하위로 이관)

**캘린더/예약**
- ✅ 일(**시간축 타임라인**, 겹침 클러스터)/주/월/년, 담당자 필터, 월·년 하단 예약 리스트
- ✅ 예약 생성·수정·취소·노쇼·예약전환·삭제
- ✅ 결제(결제완료/결제수단/예약완료) + **결제 시 적립률 자동 적립**(고객 크레딧+이력)
- ✅ 예약 변경 이력(before→after diff)

**고객/담당자/서비스**
- ✅ 고객 등록·수정·적립금 조정·**병합**
- ✅ 담당자 추가·수정·삭제·근무시간·**병합**
- ✅ 서비스 카탈로그 CRUD

**매장/설정**
- ✅ 매장 이름·업종·기능토글·영업시간/휴무·적립률/충전 설정
- ✅ 설정>관리: 서비스·담당자·**공지**·**쿠폰(상품)**·**회원권(상품)**·매출
- ✅ **Store 디코딩 버그 수정**(로그인 대비): `storeName→name`, `id` 누락 허용

**인프라**
- ✅ `TASService`가 게스트(로컬)↔로그인(API Bearer) 자동 분기
- ✅ CI: `ios-build.yml`(빌드 검증) + `testflight.yml`(`[tf]` 커밋 시 업로드)

---

## P0 — 로그인 (구글 먼저) 🔒 최우선

> 앱엔 **웹 위임(ASWebAuthenticationSession)** 로그인이 이미 구현돼 있음:
> `signIn(provider)` → 웹 `/login?nonce&provider`(NextAuth OAuth) → `tasios://auth/callback?code` → `/api/mobile-auth/exchange` → Bearer→Keychain.
> iOS 소셜 SDK 없이도 **웹 NextAuth에 provider만 켜지면** 로그인 가능. 현재 `AUTH_*_ID`가 `REPLACE…` 플레이스홀더라 비활성.

**👤 사용자 준비 — 구글**
1. Google Cloud Console → OAuth 동의 화면(승인 도메인 `takeaseat.co.kr`)
2. OAuth 2.0 클라이언트 ID **"웹 애플리케이션"** → 리디렉션 URI `https://takeaseat.co.kr/api/auth/callback/google` (+dev 도메인)
3. tas 웹 env: `AUTH_GOOGLE_ID`, `AUTH_GOOGLE_SECRET`
4. 웹 재배포
- (카카오/네이버 동일: `…/callback/{kakao,naver}` + `AUTH_KAKAO_ID/SECRET`, `AUTH_NAVER_ID/SECRET`)

**🤖 Claude 작업**
- ⬜ 웹 `/login` 모바일 콜백(`nonce`/`provider`→`tasios://…?code`) 지원 확인·보완(`/api/mobile-auth/*` 브리지 존재)
- ⬜ 구글 로그인 E2E 검증(로그인→매장 로드→게스트 종료)
- 🟡 **네이티브 Google SDK — iOS 구현 완료**(`GoogleSignIn` SPM + `GoogleSignInManager` + `signInGoogle` 폴백 + Info.plist 키/스킴). 셋업·계약: `docs/GOOGLE_SIGNIN.md`.
  - 🔒 남은 준비: (사용자) Google Cloud **iOS 클라이언트 ID** 발급 → `GIDClientID`·리버스 스킴 교체 / (백엔드) `POST /api/mobile-auth/google`(id_token→Bearer) 신설.
  - 키 미설정 동안엔 Google 버튼이 자동으로 **웹 위임 로그인**으로 폴백(무회귀).

## P1 — 게스트→로그인 데이터 이관 🔒(로그인 의존)

- 🟡 **로직 구현 완료**(E2E 검증만 로그인 후): 로그인 직후 게스트 데이터가 있으면 `POST /api/migrate-local`로 이관.
  - `TASService.migrateLocal(snapshot:confirm:)` — body는 `MigrateLocalBody`가 스냅샷 필드를 최상위로 평탄화 + `confirm`. 409(`ALREADY_SETUP`)→`.alreadySetup`.
  - `SessionStore.migrateGuestDataIfNeeded()` — signIn/signInGoogle 성공 후 자동 호출. 403(owner 아님) 조용히 스킵, 409면 `pendingMigration`→RootView 확인 알럿→`confirmMigration()`(confirm:true). 성공 시 `GuestStore.reset()/deactivate()` + 매장 재로드.
  - 이관 실패는 로그인을 막지 않음(로컬 데이터 보존). 평탄화 인코딩은 `MigrateLocalBodyTests`로 검증.
  - 로그인이 실제로 켜지기 전까지 이 경로는 트리거되지 않아 **기존 동작 무회귀**.

## P2 — 로그인 전용 연동 🔒

- ⬜ SNS 계정 연동 `/api/account/link` (소셜 provider 키)
- ⬜ 멤버 관리·초대코드 `/api/members`·`/api/invites` (로그인 owner)
- ⬜ 네이버 예약 동기화 — **Gmail OAuth**(`AUTH_GOOGLE_ID/SECRET`+Gmail 범위) + `/api/gmail/*`·`/api/naver-booking-sync`
- ⬜ 온라인 예약 설정 `PUT /api/store`(공개 예약 페이지 `book/[slug]`는 웹 전용 유지)
- ⬜ 마이페이지/계정 — 닉네임 `/api/user/nickname`, 탈퇴 `/api/account/delete`, 문의 `/api/inquiry`

## P3 — 기능 완성도 갭 (일부 게스트에서도 가능)

- 🟡 **예약 생성 폼 고도화**: ✅ 담당자 **가용성/중복 예약 체크**(겹침 경고 + 저장 전 확인, `ReservationOverlap` 공용 유틸) / ⬜ 예약 시점 결제수단·포인트 입력
- ✅ **적립금(포인트) 사용 결제** — 결제수단 `적립금` 사용분을 고객 잔액에서 차감(`paymentUse` 이력) + 보유 잔액 표시·초과 검증. 수정 시 차액만 반영.
- 🟡 **온라인 예약 신청(requested) 처리** — ✅ 상세에서 예약확정(→active)/거절(→cancelled)/삭제 UI(기존 setReservationStatus 재사용). ⬜ 온라인 예약 유입 경로 자체는 🔒 온라인예약 연계 대기.
- ⬜ **다국어 이름(i18n)** — `nameI18n`/`storeNameI18n`/`titleI18n` 편집(공개 예약 페이지용, 우선순위 낮음)
- ✅ **매출 확장** — 기간 필터(월/년) + 추세 막대 차트(Swift Charts, 일별/월별). 합계·담당자별은 선택 기간 기준으로 집계.

## P4 — 쿠폰·회원권 발급/차감 (웹도 "추후 지원")

- ⬜ 현재 상품(템플릿) 등록까지만. 풀 기능 = 고객 **발급**(CustomerCoupon/Membership) + 결제 시 **할인/차감**. 백엔드 발급·사용 엔드포인트 신설 필요.

## P5 — 캘린더·디자인 마감

- ⬜ 주(week) 타임라인 — 모바일 7칼럼 좁아 **보류 권장**(리스트가 적합)
- ⬜ 일 타임라인 담당자별 칼럼 분리(담당자 수 적을 때 옵션)
- 디자인: 네이티브 골격 + 웹 시각언어 유지 확정. 픽셀 매칭 비권장. 거슬리는 화면만 폴리시.

## P6 — 출시 준비 (App Store / TestFlight)

- ✅ 버전 규약(`MARKETING_VERSION` 0.0.0/`CURRENT_PROJECT_VERSION` CI run_number), 아이콘(보라 의자), `ITSAppUsesNonExemptEncryption=false`
- ⬜ App Store Connect 앱 등록(`kr.co.takeaseat.app`)·SKU·카테고리
- ⬜ 스크린샷·앱 설명·키워드
- ⬜ 개인정보 처리방침 URL(웹 `/privacy`·`/terms` 연결) · App Privacy 라벨
- ⬜ 심사 제출(정식 릴리스 전까진 TestFlight 반복)

## P7 — 품질

- ✅ 자동 테스트: 유닛 테스트 타깃(TASTests) + `ios-test.yml` CI. 커버: 겹침(ReservationOverlap)·Store 디코딩·고객/예약 헬퍼·매출 집계/추세·**게스트 CRUD/병합**(GuestStore)·**적립 계산**(PointMath)·이관 인코딩(MigrateLocalBody). (추가 회귀 케이스는 필요 시 확장.)
- ⬜ 접근성/다크모드/다이내믹 타입 재점검(컴팩트 폰트 후 큰 글자 레이아웃)
- ⬜ 푸시 알림(없음) — APNs 키·등록·백엔드 발송(로그인 기반)
- ⬜ 로그인 후 다기기 동기화/충돌 처리(웹 `conflict-resolution` 미반영)

---

## 작업 규약

- **단일 작업 브랜치** `claude/tas-service-ios-stlzh4`(default)에 커밋·푸시. 머지된 PR엔 이어붙이지 말 것.
- **로컬 빌드 불가 → 푸시 후 CI green으로 검증.** 푸시 전 수동 점검:
  - 심볼 참조(다른 타입 static/메서드 오참조 주의 — 예: `ShopIndustry.defaultSchedule`(실제 `ShopCatalog`))
  - 괄호/중괄호/대괄호 균형, 색 삼항은 `Color.x : Color.y`(ShapeStyle 혼용 금지)
  - **탭 아닌 push 화면은 자체 `NavigationStack` 금지**(중첩). 탭 루트만 자체 NavigationStack.
- 테스트용 빌드는 커밋 메시지에 `[tf]` → TestFlight.
- 색·라벨·판정 로직은 하드코딩 말고 웹(`/workspace/tas`)에서 이식.
- 버전 범프는 `CLAUDE.md` 규약(`TAS.xcodeproj` + `project.yml` 양쪽).

## 핵심 파일

- 라우팅/탭 `TAS/App/RootView.swift` · 세션/로그인 `TAS/Core/Session/SessionStore.swift`·`TAS/Features/Login/*`·`TAS/Core/Config/AppConfig.swift`
- 데이터 분기/저장 `TAS/Core/Networking/TASService.swift`·`TAS/Core/Storage/{GuestStore,GuestSnapshot}.swift`
- 캘린더 `TAS/Features/Calendar/*`(CalendarView, DayTimelineView, ReservationDetail/Create/Payment/HistoryView)
- 설정/관리 `TAS/Features/{Settings,Services,Assignees,Notices,Coupons,Memberships,Revenue}/*` · 모델 `TAS/Models/*`

## 다음 세션 첫 스텝
1. (사용자) P0 구글 OAuth + `AUTH_GOOGLE_ID/SECRET` + tas 웹 재배포
2. (Claude) P0 구글 로그인 E2E → P1 이관 로직
3. (Claude) P3 예약 폼 고도화(담당자 중복 체크) — 로그인 없이 가치
4. (사용자/Claude) P6 App Store Connect 등록·스크린샷
