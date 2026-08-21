# plan.md — tas-ios

> takeaseat(TAS) iOS 클라이언트의 태스크 소스오브트루스.
> 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas)(로컬 `/workspace/tas`). 구조는 `README.md`, 버전 규약은 `CLAUDE.md`.
>
> _상태_ ⬜ 예정 · 🟡 진행 · ✅ 완료 · 🔒 외부 준비 필요(키/설정)
> _작업 브랜치: 세션마다 지정되는 `claude/*` 브랜치(현재 `claude/web-design-mismatch-q7hfs7`).
> 머지된 PR 브랜치엔 이어붙이지 말고 머지된 default에서 새로 딴다._

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
  - ⚠️ **전 매장 공개 기능이 아니다.** 웹은 허용 매장에만 노출하도록 게이트를 걸었다(tas `server/naver-access.ts` —
    허용 슬러그 목록 **또는** 기존 `GmailConnection` 보유). 이식할 땐 **`GET /api/store`의 `naverBookingEnabled`가
    true인 매장에서만** 메뉴·화면을 띄운다(`Store` 모델에 필드 추가부터). 이 값을 안 보고 화면을 붙이면
    비대상 매장 오너에게 노출되고, 연동 버튼은 `/api/gmail/connect`가 **403**을 주므로 눌러도 실패한다.
- 🟡 **온라인 예약 설정 — iOS 이식 완료(E2E만 로그인 후).** `BookingSettingsEditView`가 웹
  `BookingManageSection`과 같은 범위를 편집: 영문 매장명(슬러그, 형식검증 + `?checkSlug=` 중복 확인) ·
  **매장 연락처(필수)** · 예약 간격(10/15/20/30/60) · 최소 사전 예약 시간 · 최대 예약 가능 일수 ·
  담당자 선택 허용 · 안내문구 4종(기본 문구 채움) · 노출 서비스 화이트리스트(전체 선택=전체 노출).
  저장은 `PATCH /api/store`(`bookingSlug`+`bookingSettings`), 모델은 `BookingSettings`.
  공개 예약 페이지 자체는 웹 전용 유지 → **게스트는 로그인 게이트**. 다국어(i18n) 입력은 제외(우선순위 낮음).
- ⬜ 마이페이지/계정 — 닉네임 `/api/user/nickname`, 탈퇴 `/api/account/delete`, 문의 `/api/inquiry`

## P3 — 기능 완성도 갭 (일부 게스트에서도 가능)

- ✅ **예약 생성 폼 고도화**: 담당자 **가용성/중복 예약 체크**(겹침 경고 + 저장 전 확인, `ReservationOverlap`) + **예약 시점 결제완료 등록**(단일 결제수단 + 적립률 자동 적립, `PointLedger.apply` 재사용). (적립금 *사용* 결제는 상세의 결제 화면에서.)
- ✅ **적립금(포인트) 사용 결제** — 결제수단 `적립금` 사용분을 고객 잔액에서 차감(`paymentUse` 이력) + 보유 잔액 표시·초과 검증. 수정 시 차액만 반영.
- ✅ **적립금 충전(선불) 실행** — 설정의 충전 규칙을 실제로 쓰는 화면이 없어 규칙이 사장돼 있었다.
  고객 상세 > **적립금 충전**(`PointRechargeView`, 웹 `AddressCustomerRecharge` 이식): 규칙(기준금액+보너스)
  선택 또는 직접 입력 → `recharge` 이력. 매장 설정에서 선불 충전이 켜진 경우에만 노출.
- ✅ **기능 토글 ↔ 설정 진입 일치** — 매장 정보 편집에 **쿠폰 토글 추가**(그동안 앱에선 쿠폰 기능을 켤 수
  없어 웹에서만 가능했다). 설정 화면의 읽기 전용 토글 섹션은 제거하고, 켠 기능마다 **그 기능의 설정
  화면으로 바로 들어가는** 항목을 노출(적립금 설정 · 쿠폰 관리 · 회원권 관리 · 온라인예약 설정).
- 🟡 **온라인 예약 신청(requested) 처리** — ✅ 상세에서 예약확정(→active)/거절(→cancelled)/삭제 UI(기존 setReservationStatus 재사용).
  ✅ 대기 목록은 P3.6 **온라인 예약 요청함**(`/api/book-requests`)이 담당 — 신규 신청뿐 아니라 변경·취소 요청까지 한 곳에서 처리한다.
  ⬜ 온라인 예약 유입 경로 자체는 🔒 온라인예약 연계 대기.
- ⬜ **다국어 이름(i18n)** — `nameI18n`/`storeNameI18n`/`titleI18n` 편집(공개 예약 페이지용, 우선순위 낮음)
- ✅ **매출 확장** — 기간 필터(월/년) + 추세 막대 차트(Swift Charts, 일별/월별). 합계·담당자별은 선택 기간 기준으로 집계.

## P3.5 — tas 백엔드/웹 변경 동기화 (2026-07-28 확인)

> tas main 기준으로 이 저장소가 뒤처졌던 항목. **아래 ✅는 이번 세션에서 iOS에 반영 완료.**

- ✅ **고객 메모 3종 제거**(tas #168, 마이그레이션 `0018`) — `Customer.allergyNote/claimNote/preferenceNote`
  컬럼이 운영에서 드롭됐다(참조 0건 확인). 입력 UI 없이 표시만 하던 임포트 레거시라 iOS도
  모델·상세 "노트" 섹션 배선을 제거. 서버가 안 주는 필드라 남겨두면 항상 빈 섹션.
- ✅ **사람 진료 업종 제외**(tas #168/#167) — 병원·의원/치과/한의원을 업종 선택 목록에서 제외.
  진료 내용은 건강정보(민감정보)라 개인정보보호법 §23의 별도 동의·안전조치가 필요한데
  예약 메모 등 자유 입력 경로가 열려 있어 현 구조로 감당하지 않는다. **동물병원은 유지.**
  - 웹은 `sanitizeShopType`이 목록 밖 값을 `null`로 만들지만, iOS는 **게스트 로컬 스냅샷이
    사용자 데이터**라 조용히 지우지 않는다 → `ShopCatalog.retiredIndustries`(표시 전용)로
    라벨은 계속 해석하고, 편집 화면 Picker엔 현재 값일 때만 끼워 넣는다(`industryGroups(including:)`).
    검증: `ShopCatalogTests`.
- ✅ **고객 병합 대상 선택에 판단 근거**(tas 병합 미리보기 이식) — 후보 행에 **예약 건수 · 적립금**.
  이름·연락처만으로는 동명이인·마스킹 이름(네이버 유입 `*`)을 구분할 수 없고, 잘못 고르면
  기준 고객의 잘못된 연락처가 남는다. 이미 받아둔 `reservationsByCustomer`·`points`로 충족(API 무변경).
- ✅ **예약 저장 연속 클릭 중복 고객 생성**(tas 운영 사고 수정) — iOS는 이미 `isSaving` 가드 +
  저장 버튼 disabled이고 신규 고객 id가 시트 생성 시점 `nextCustomerId` 고정값이라 재시도해도
  upsert된다. 회귀 방지용으로 근거를 주석화(무동작 변경).
- ✅ **매장 연락처(`bookingSettings.contactTel`)**(tas #169, 마이그레이션 `0019`) — 온라인 예약 사용 시
  **필수**(미입력 시 `PATCH /api/store` 400 `contactTel required`). P2 예약 설정 화면에 포함.
  숫자만 정규화하지 않고 **입력 원문 그대로** 저장(02·1588 등 자릿수 제각각) — 서버 규칙과 동일.
  - ⚠️ 서버 가드는 요청에 `bookingSettings`가 있을 때만 돈다. 기능 토글만 바꾸면(앱·웹 모두)
    연락처 없이 온라인예약이 켜진 상태가 만들어진다 → 설정 목록에 **"설정 필요"** 배지로 노출.
- ✅ **공개 예약 페이지 도메인 이전**(tas #160) — `takeaseat.co.kr/book/[slug]` → `book.takeaseat.co.kr/[slug]`
  (구 경로는 307). 예약 설정 화면의 공개 주소 미리보기가 `AppConfig.bookingPublicURL`로 새 호스트를 쓴다
  (운영 도메인이 아니면 dev·local엔 예약 서브도메인이 없어 구 경로 `/book/{slug}` 폴백).
- 확인만: 공지(`pinned`/카테고리)·쿠폰 `oncePerCustomer`·회원권 모델은 웹과 **이미 일치**. 그 밖의
  tas 변경(모바일 하단탭·설정 UI 공통화·매출 기간선택 iOS Safari 겹침 등)은 웹 전용이라 이식 대상 아님.

## P3.6 — tas 백엔드/웹 변경 동기화 (2026-08-10 확인)

> tas `main`(12538e2, 2026-08-02)까지 훑었다. 7/28 이후 `server/` 변경은 전부 네이버싱크·Gmail
> 내부(P2 로그인 전용 백엔드)라 **iOS API 계약 변경은 없다.** 이식 대상은 아래 3건.

- 🟡 **온라인 예약 요청함 — `/api/book-requests` 이식** (tas #76·#115·#142, 백엔드 2026-07-16부터 존재)
  - **왜 지금 나왔나:** tas `index.md`가 "확인/변경/취소(1d, Phase 2) **미구현**"이라고 잘못 적어 두었고
    7/28 동기화가 그 문장을 믿고 건너뛰었다. tas가 `59eb02c`로 **오표기를 정정**하면서 드러났다.
  - **실제 갭:** 고객이 공개 예약 페이지(`book.takeaseat.co.kr/{slug}/r/{token}`)에서 보낸 **변경·취소
    요청**은 즉시 반영이 아니라 `pendingAction`으로 대기하고, 오너가 수락해야 반영된다. 이 대기 항목을
    **앱에서 볼 방법이 전혀 없다** — 웹 헤더 벨(`BookingRequestNotification`)에만 있다. 앱만 쓰는
    오너는 고객 요청을 영영 못 본다.
  - **계약**(`server/api/book-requests.ts`): `GET` → `{requests: [{id, legacyId, kind, customerName,
    assigneeName, requestedAt, current{date,startTime,endTime,serviceSummary}, requestedChange|null}]}`.
    `kind`는 `new`(status=requested) · `change` · `cancel`. `POST {id, decision:'approve'|'reject', reason?}`
    → `{ok, applied}`. 수락 시: new→active, cancel→cancelled, change→저장된 payload 적용.
    거절 시: new→cancelled, change/cancel→요청만 폐기(예약 유지). 대기 없으면 409 `no_pending`.
  - **iOS:** `BookingRequest` 모델 + `TASService.fetchBookingRequests()/decideBookingRequest()`(게스트 차단)
    + `BookingRequestsView`(캘린더 툴바 벨 → 시트). 온라인예약 ON + 로그인일 때만 노출(웹 게이트와 동일).
  - **iOS 이식 완료**(모델+서비스+UI). ⬜ E2E는 🔒 로그인 후 — 그때까지 호출 경로가 열리지 않아 무회귀.
- ✅ **이름 정렬 규칙 이식** (tas #175 `compareCustomerName` · 기존 `compareAssigneeName`)
  - iOS는 `$0.name < $1.name`(코드포인트 비교)이라 `Z`가 `apple`보다 앞서고 `고객10`이 `고객9`보다 앞선다.
  - 고객: `Intl.Collator('ko', {numeric:true})` → `compare(options:.numeric, locale: ko_KR)`, 동명이인은 id로 안정화.
  - 담당자: 웹은 **영문 → 한글 → 기타** 그룹 후 `localeCompare('ko')`. iOS엔 이 그룹 규칙이 없었다.
  - 적용처: 예약 추가 고객 추천 목록(웹이 고친 자리) · 고객 명단 · 담당자 목록.
- ✅ **근무시간 요약 `summarizeSchedule` 이식** (tas #183) — **기존 표시가 틀렸다.**
  - iOS `AssigneeRow`는 근무 요일을 전부 `·`로 잇고 **첫 요일의 시간만** 붙인다. 월~금 10–20 / 토 10–18이면
    `월·화·수·목·금·토 10:00–20:00`으로 **토요일 시간이 틀리게** 나온다.
  - 웹처럼 같은 근무시간끼리 구간으로 묶는다: `월~금 10:00~20:00 · 토 10:00~18:00 · 일 휴무`.
  - 7일 미만 스케줄은 모자란 요일을 휴무로 채운다(웹 동작 동일). 검증: `AssigneeScheduleTests`.
- ✅ **요일 라벨 공용화** — `["월"…"일"]`이 5곳(캘린더 월/주, 영업시간, 담당자 폼/목록)에 복붙돼 있었다.
  `KST.weekdayLabels` 하나로 모은다(CLAUDE.md 공통 영역 재사용 규칙).
- 확인만: 7/28 이후 tas `server/` 변경은 네이버싱크 복원력(재시도·페이지네이션·워터마크)·Gmail 토큰 버퍼로
  **전부 백엔드 내부**. 워크플로/버전/테스트 도입 커밋은 웹 저장소 운영 규약이라 이식 대상 아님.

## P3.7 — tas 백엔드/웹 변경 동기화 (2026-08-11 확인)

> tas #193(네이버예약 연동 노출 제한 + 미구축 "통합 예약 관리" 문구 제거) 반영 확인.

- **iOS 코드 변경 없음.** 웹은 네이버예약 연동을 허용 매장에만 노출하도록 게이트를 걸었지만,
  iOS엔 감출 대상이 **아직 없다** — 연동 UI가 미구현이다(P2 항목). 근거: 앱이 호출하는 API에
  `/api/gmail/*`·`/api/naver-booking-*`이 없고(`TAS` 전수), 설정 화면에 연동 항목이 없다.
  앱의 네이버 언급은 **SNS 로그인 provider**·**결제수단(네이버페이·네이버 예약금)**·**예약 경로 라벨**뿐인데,
  이 셋은 웹에서도 게이트 대상이 아니라 그대로 두는 것이 웹과 일치하는 상태다.
- **이식할 때 지킬 것** → P2 "네이버 예약 동기화" 항목의 ⚠️ 참조(`naverBookingEnabled` 확인 없이 화면을 붙이면
  비대상 매장에 노출되고 `/api/gmail/connect`가 403).
- 웹이 함께 정리한 "네이버·당근 등 통합 예약 관리" 마케팅 문구는 **이 저장소에 없다**(전수 확인).
  단, **App Store Connect의 앱 이름·부제·설명은 저장소 밖**이라 같은 문구가 남아 있는지는 콘솔에서 확인 필요.

## P3.8 — 휴무(임시 휴업일·정기 휴무) 캘린더 표시 ✅ (실기기 확인만 남음)

> 웹(tas)이 캘린더에 휴무를 표시하도록 바뀌었다. iOS도 데이터(`Store.closedDates`/`closedWeekdays`)는
> 이미 갖고 있으면서 화면에 그리지 않는다.

- ✅ **판정 이식 완료** — `Store.closedKind(on:)`(`TAS/Models/Store.swift`) + `StoreClosedKind`.
  웹 `getStoreClosedKind`와 같은 규칙: 임시 휴업일이 정기 휴무보다 우선, 요일 인덱스는
  앱 공통 `0=월 … 6=일`(`Calendar.weekday` 는 `1=일` 이라 `(weekday+5)%7`).
- ✅ **단위 테스트** `TASTests/StoreClosedKindTests.swift` 6케이스(요일 전수·일요일 경계·우선순위·깨진 날짜).
  `TASTests` 는 `PBXFileSystemSynchronizedRootGroup` 이라 파일만 추가하면 CI 가 컴파일한다.
- ✅ **화면 표시 완료** — `TAS/Core/UI/StoreClosedStyle.swift` **(신규 공용 modifier)**.
  `.storeClosed(kind, cornerRadius:)` 하나로 틴트 + 테두리 + `accessibilityLabel` 이 함께 붙는다.
  임시=적색(`FF3B30`) 계열, 정기=회색 계열. 글자(배지)는 쓰지 않는다 — 웹에서 모바일 좁은 열에
  글자가 안 들어가 한 글자씩 세로로 쪼개져 결국 걷어냈고, 앱 월 셀은 그보다 더 좁다.
  - **왜 View 가 아니라 modifier 인가** — 붙는 세 곳(월 셀 44pt 정사각 / 일 헤더 가로 바 /
    주 섹션 헤더)의 크기·모서리가 제각각이라 감싸면 기존 여백·정렬이 틀어진다. 장식만 입힌다.
  - **왜 색 함수 공유가 아닌가** — 색만 공유하면 접근성 라벨을 호출부가 빠뜨려도 아무도 모른다.
    modifier 를 쓰는 것만으로 라벨이 따라오게 묶었다.
  - 연결부: `CalendarView.closedKind(_:)` → 월 셀(`:214`) · 일 헤더(`:437`) · 주 섹션 헤더(`:525`).
- ✅ **막지 않는다** — 웹과 동일하게 표시 전용. 휴무일에도 예약 생성은 그대로.
- ⬜ **실기기/시뮬레이터 확인** — 이 컨테이너에 Xcode 가 없어 빌드·렌더 확인을 못 한다.
  CI 그린까지가 여기서의 검증이고, 색 농도·다크모드 대비는 화면으로 봐야 한다.

## P4 — 쿠폰·회원권 발급/차감

> tas 원본 스펙 확인 결과(2026-07-28 갱신): **회원권·쿠폰 모두 발급/취소 API가 실재**
> (`/api/membership-issue`·`/api/membership-use`·`/api/coupon-issue`, staff, **로그인 전용** — 게스트 local-db 미지원).
> 결제수단 자동 차감(`PaymentMethod.membership/coupon`)은 양쪽 다 Phase 3 미구현.

- 🟡 **회원권 발급/차감(로그인 전용)** — iOS 이식 완료(데이터+서비스+UI), E2E만 로그인 후:
  `CustomerMembership` 모델 + `MembershipsResponse.memberships` + `TASService.issueMembership/cancelMembership/useMembership`(게스트는 "로그인 후 이용" 차단).
  회원권 화면에 **상품/발급 탭** — 발급 탭(로그인 시): 고객+상품 선택 발급 시트, 발급 내역에 차감/복원/취소. 게스트는 잠금 안내.
- 🟡 **쿠폰 발급(직접, Phase 2)** — iOS 이식 완료 + **백엔드 머지·배포 완료**(로그인 E2E만 남음).
  **tas #156**(`coupon-issue.ts`, 보관·코드형 차단) → 머지 `0862f73`. **tas #159**(상품별 '고객당 1장'
  `oncePerCustomer` + 미사용 보유 시 재발급 400, 마이그레이션 `0017`) → 머지 `3bd3034`.
  머지본 계약이 iOS 구현과 일치함을 2026-07-28 재대조 확인. 계약 문서: `docs/COUPON_ISSUE_BACKEND.md`.
  ⬜ 코드형 발급·결제 차감(Phase 3)은 후속.
- ✅ **발급 가드 일치** — **tas #157** 머지(`89c87d0`): 회원권 발급도 보관 상품 차단(쿠폰과 동일 규칙).
  iOS는 양쪽 모두 발급 목록에서 보관(쿠폰은 코드형도) 제외로 이미 일치.
- ✅ **게스트에겐 쿠폰·회원권·온라인예약 자체를 노출하지 않는다** — 매장 정보 편집의 기능 토글에서도
  빼고(적립금만 남김), 설정 목록의 진입 항목에서도 뺀다. 켤 수는 있는데 못 쓰는 토글은 두지 않는다는
  규칙. (웹은 토글을 노출하지만, 앱은 이 규칙을 우선한다.)
- ✅ **쿠폰·회원권은 화면 전체가 로그인 전용**(웹 `isLocal` 게이트와 일치). 예전엔 상품 CRUD만 게스트에서
  됐는데, 발급을 못 할 뿐 아니라 **`POST /api/migrate-local`이 받는 건 `services·assignees·customers·
  reservations`뿐**이라 게스트가 만든 쿠폰·회원권 상품은 로그인해도 계정으로 넘어가지 않는 막다른
  데이터였다. 설정 목록의 해당 항목엔 게스트일 때 "로그인 필요" 표기.
  (기존 게스트 스냅샷의 상품 데이터는 지우지 않는다 — 화면에서만 감춘다.)
- ⬜ **이관 대상 확대 검토(백엔드)** — `migrate-local`이 공지·쿠폰 상품·회원권 상품·매장설정
  (영업시간·적립 설정)을 받지 않는다. 게스트가 준비한 설정을 로그인 후 그대로 쓰려면 tas 쪽 확장 필요.
- ⬜ **결제 연동 차감**(예약 결제수단으로 회원권/쿠폰 차감) — 백엔드 Phase 3(`PaymentMethod` enum 확장) 선행 필요.

## P5 — 캘린더·디자인 마감

- ✅ **주(Week) 뷰 진입 시 현재 요일로 스크롤**
  - **문제:** 주 뷰는 월~일 7개 섹션 리스트인데 진입하면 항상 **맨 위(월요일)** 였다. 주 후반(목~일)엔
    오늘을 보려고 매번 손으로 스크롤해야 했고, 일 뷰에서 주 뷰로 넘어올 때마다 반복됐다.
  - **구현:** `weekList`를 `ScrollViewReader`로 감싸고 각 `Section`에 날짜 키(`YYYY-MM-DD`)를 `.id`로
    준 뒤, 진입(`onAppear`) 시 **선택 날짜(기본값 = 오늘)** 섹션으로 `scrollTo(anchor: .top)`.
    상단 DatePicker로 날짜를 옮기면(`onChange(of: dateKey)`) 그 요일로 따라간다(이때만 애니메이션).
    선택 날짜는 항상 표시 중인 주 안에 있다(`weekDayKeys`가 선택 날짜의 주에서 파생).
  - **주의:** `onAppear` 시점엔 List가 아직 셀을 만들기 전이라 바로 부르면 스크롤이 먹지 않는다
    → `Task { @MainActor in … }`로 다음 런루프에 호출.
  - **범위:** `TAS/Features/Calendar/CalendarView.swift`의 주 뷰 한정. 다른 모드(일/월/년)·데이터 로직 무변경.
    같이 정리: P7에 적어둔 `CalendarView.swift` 빈 줄 잔재 제거.
- ✅ **시술(서비스) 배지 웹 일치** — 이식 누락 복구
  - **문제:** "네이티브 골격" 예외가 아니라 웹 정의 이식이 빠진 것. tas 저장소 대조로 3건 확인.
    1. **색이 서비스별이 아니라 카테고리별.** 웹 `client/features/services/model.ts:126` `buildServiceColorMap`은
       카테고리 기본색에 `SHADE_STEPS = [0,14,-14,26,-26,36,-36,46,-46]`을 `adjustHexColor`로 얹어
       **같은 카테고리 안에서 서비스마다 농도**를 준다(남성/여성/주니어커트가 서로 다른 파랑).
       iOS `CalendarViewModel.swift:148`은 `ServiceColor.categoryColor(item.category)`를 그대로 써서
       **커트 3종이 전부 같은 `#2D7FF9`.** `adjustHexColor`·`SHADE_STEPS`·`LEGACY_NAME_MAP` 미이식.
    2. **배지가 아니라 점+회색 글씨.** 웹 `ServiceChip.tsx`는 알약 칩(`radius 999`, `padding 3/7`,
       배경 `${color}18`≈9% 틴트, **글자색이 서비스색**, 11px/600). iOS는 `ColorDot`+회색 텍스트이거나
       (`CalendarView:588`, `ReservationDetailView:69`) 색이 아예 없다(`CalendarView:368`,
       `DayTimelineView:72`, `CustomerDetailView:135`).
    3. **복수 시술이 안 쪼개짐.** 웹은 `parseServiceString`으로 `+`를 분리(이름에 `+`가 든 서비스는
       greedy 보존)해 칩 하나씩. iOS는 `"커트+펌"`이 통짜 한 줄.
  - **구현:** `Core/UI/ServiceColor.swift`에 `adjustHex`·`shadeDelta`·`legacyNameMap`·
    `buildServiceColorMap`·`serviceHex`·`parseServiceString` 이식. `Core/UI/ServiceChip.swift`
    **신규 공용 컴포넌트**(`ServiceChipList`/`ServiceChip` + 넘칠 때 흐르는 `Layout`) — 표시 지점이
    6곳이라 화면마다 칩 마크업을 복붙하면 CLAUDE.md가 금지한 웹의 하드코딩 반복을 그대로 옮기게 된다.
    `CalendarViewModel`은 `[String: Color]` 대신 웹과 같은 **hex 맵**(`serviceColorMap`)을 들고 있는다.
  - **웹과 의도적으로 다른 점:** 리스트 행은 `wraps: false`(1줄 말줄임) — 웹도 목록에선
    `nowrap`+ellipsis로 행 높이가 터지는 걸 막는다(`AddressCustomerSummary.tsx:197` 주석). 상세는 흐름 배치.
  - **주의:** 웹 `FALLBACK_COLOR`가 3자리 `#999`라 `Color(hex:)`에 3자리 지원을 더해야 한다(기존 6자리 무영향).
    `serviceHex`의 부분 문자열 폴백은 웹이 길이 내림차순·동률은 카탈로그 순서인데 Swift `Dictionary`는
    순서가 없어 **동률은 이름 오름차순**으로 결정론적 고정(카탈로그에 없는 이름에서만 타는 경로).
  - **범위:** `Core/UI/{ServiceColor,ServiceChip,Color+Hex}.swift` · `CalendarViewModel` ·
    `CalendarView`·`DayTimelineView`·`ReservationDetailView`·`CustomerDetailView`·`ReservationCreateView`.
    데이터·API 무변경.
- ⬜ 주(week) 타임라인 — 모바일 7칼럼 좁아 **보류 권장**(리스트가 적합)
- ⬜ 일 타임라인 담당자별 칼럼 분리(담당자 수 적을 때 옵션)
- 디자인: 네이티브 골격 + 웹 시각언어 유지 확정. 픽셀 매칭 비권장. 거슬리는 화면만 폴리시.

## P6 — 출시 준비 (App Store / TestFlight)

- ✅ 버전 규약(`MARKETING_VERSION` 0.1.0/`CURRENT_PROJECT_VERSION` CI run_number), 아이콘(보라 의자), `ITSAppUsesNonExemptEncryption=false`
- ✅ **업로드 차단 해소** — Google 로그인 작업(PR #10) 때 들어간 플레이스홀더 URL 스킴
  (`com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID`)이 App Store 업로드를 거부시켰다
  (altool **90158**, 언더스코어 불가). 실제 리버스 클라이언트 ID를 받을 때까지 주석 처리.
  키를 받으면 주석을 풀 것 — `docs/GOOGLE_SIGNIN.md`.
  ⚠️ TestFlight는 **기본 브랜치 push + 커밋 메시지 `[tf]`** 둘 다 만족해야 돈다. `[tf]` 없이 머지하면
  워크플로가 `skipped`로 넘어가 기기 빌드가 조용히 낡는다(7/24~7/29 실제로 그랬음).
- ⬜ App Store Connect 앱 등록(`kr.co.takeaseat.app`)·SKU·카테고리
- ⬜ 스크린샷·앱 설명·키워드
- ⬜ 개인정보 처리방침 URL(웹 `/privacy`·`/terms` 연결) · App Privacy 라벨
- ⬜ 심사 제출(정식 릴리스 전까진 TestFlight 반복)

## P7 — 품질

- ✅ 자동 테스트: 유닛 테스트 타깃(TASTests) + `ios-test.yml` CI. 커버: 겹침(ReservationOverlap)·Store 디코딩·고객/예약 헬퍼·매출 집계/추세·**게스트 CRUD/병합**(GuestStore)·**적립 계산·잔액 원장**(PointMath·PointLedger)·이관 인코딩(MigrateLocalBody). (추가 회귀 케이스는 필요 시 확장.)
- ⬜ 접근성/다크모드/다이내믹 타입 재점검(컴팩트 폰트 후 큰 글자 레이아웃)
- ⬜ 푸시 알림(없음) — APNs 키·등록·백엔드 발송(로그인 기반)
- ⬜ 로그인 후 다기기 동기화/충돌 처리(웹 `conflict-resolution` 미반영)
- ⬜ **시술 문자열을 쓰는 기존 계산 2곳 정리**(시술 배지 이식 중 발견, 이번 범위 밖이라 보류) —
  둘 다 이식 전부터 있던 버그고, 이제 `ServiceColor`에 도구가 생겨 고치기 쉬워졌다.
  - `ReservationCreateView.catalogMap`에 레거시 별칭이 없다(웹 `buildCatalogMap`은 넣는다).
    옛 이름으로 저장된 예약을 편집하면 소요시간·가격이 0으로 잡힌다.
  - `RevenueViewModel.swift:81`이 `servicePriceByName[r.service]`로 **조합 문자열 원문**을 찾는다.
    "커트+펌"은 맵에 없어 0원 처리 → 웹은 `sumPrice(parseServiceString(...))`로 합산한다.
- ⬜ **웹 톤 색상값 중복 정리**(PR #17 리뷰 지적, 출시 전까지 보류) — `A88417`(warning)·`6526D9`(purple)·
  `EA4335`(danger)가 `Core/UI/Badges.swift`(`StatusBadge`)와 `Calendar/BookingRequestsView.swift`
  (`BookingRequestKindBadge`)에 **각각** 하드코딩돼 있다. 한쪽만 고치면 같은 톤이 화면마다 어긋난다.
  정리안: `Core/UI/Color+Hex.swift`에 토큰 3개(`.tasWarning`/`.tasPurple`/`.tasDanger`)를 두고 양쪽이 참조
  (값 동일 → 화면 변화 0). 배지가 더 늘기 전에 하는 게 싸다.
  (`CalendarView.swift`의 빈 줄 잔재는 P5 주 뷰 스크롤 작업 때 함께 제거 — 색상 토큰만 남았다.)

---

## 작업 규약

- **세션 지정 `claude/*` 브랜치**에 커밋·푸시. 머지된 PR 브랜치엔 이어붙이지 말고 머지된 default에서 새로 딴다.
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
1. (사용자) P0 구글 OAuth + `AUTH_GOOGLE_ID/SECRET` + tas 웹 재배포 — **여전히 최대 병목**.
   로그인이 켜져야 P0 E2E·P1 이관·P4 쿠폰/회원권 발급(백엔드는 이미 배포됨)이 한꺼번에 검증된다.
2. (Claude) 로그인 후 E2E 3종 한 번에: 구글 로그인 → 게스트 데이터 이관 → 쿠폰·회원권 발급/차감.
3. (Claude) 로그인 후 온라인 예약 설정 E2E — 슬러그 중복 확인·저장, 연락처 400 가드, 공개 페이지 반영.
4. (사용자/Claude) P6 App Store Connect 등록·스크린샷·개인정보 처리방침 URL.
5. (Claude) P7 접근성/다크모드/다이내믹 타입 점검 — 로그인 없이 진행 가능한 잔여 작업.

## tas 저장소 동기화 방법

`plan.md`가 참조하는 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas)다. 세션에서
`add_repo` 후 `/workspace/tas`로 클론해 `git log`로 마지막 동기화 이후 변경을 훑는다. 판단 기준:

- **모델·엔드포인트·정책 변경** → 반드시 이식(예: 고객 메모 제거, 업종 목록 축소, 발급 가드).
- **판단 근거·라벨·산식** → 이식(예: 병합 미리보기 예약 건수·적립금).
- **웹 전용 레이아웃/스타일**(styled-components, 미디어쿼리, 하단 탭바 등) → 이식 대상 아님.
