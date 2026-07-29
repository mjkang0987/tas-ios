# 네이티브 Google 로그인 (GoogleSignIn SDK) — 셋업 & 계약

> 웹 위임(ASWebAuthenticationSession, `auth-mobile-bridge.md`)에 더해, **iOS 네이티브 Google 로그인**을
> 추가한다. iOS `GoogleSignIn` SDK로 직접 로그인해 Google id_token을 받고, 백엔드가 이를
> 검증해 Bearer 토큰으로 교환한다.
>
> 이 문서는 두 저장소(`tas` 백엔드 · `tas-ios`)의 계약(contract) 소스오브트루스다.

## 동작 방식 & 폴백 (중요)

- **키가 설정되면(네이티브):** Google 버튼 → `GoogleSignInManager.signIn()` → id_token →
  `POST /api/mobile-auth/google` → Bearer → Keychain → 세션 로드.
- **키가 없으면(폴백):** `AppConfig.googleClientID == nil` → 기존 **웹 위임 로그인**(`signIn(provider:"google")`)
  으로 자동 폴백. 즉 아래 셋업을 하기 전에도 앱은 정상 빌드·동작한다.
- **카카오/네이버**는 계속 웹 위임(네이티브 SDK 미도입).

```
[iOS]  Google 버튼 탭
   │  GoogleSignIn SDK (ASWebAuthenticationSession 내부 사용, 진짜 Safari)
   ▼
[Google]  로그인/동의 → 리버스 클라이언트 ID 스킴으로 콜백
   ▼
[iOS]  GIDSignInResult.user.idToken → POST /api/mobile-auth/google { idToken, serverAuthCode?, invite? }
   ▼
[tas]  id_token 서명·audience 검증 → 사용자 조회/생성 → { accessToken, expiresAt }
   ▼
[iOS]  Keychain 저장 → 이후 요청에 Authorization: Bearer
```

## 👤 사용자 준비 — Google Cloud Console

1. **OAuth 동의 화면**: 이미 웹용으로 구성돼 있으면 재사용(승인 도메인 `takeaseat.co.kr`).
2. **OAuth 2.0 클라이언트 ID → "iOS"** 새로 발급
   - 번들 ID: `kr.co.takeaseat.app`
   - 발급되면 **클라이언트 ID**(`…apps.googleusercontent.com`)와 그 **리버스 클라이언트 ID**
     (`com.googleusercontent.apps.…`)를 얻는다.
3. (선택) 백엔드가 **서버 인가코드**나 웹 클라이언트 audience로 검증하려면 웹(서버) 클라이언트 ID도 준비.

## 🤖 iOS 설정 (`TAS/Info.plist`)

발급값으로 아래 플레이스홀더 2곳을 교체:

| 위치 | 키 | 넣을 값 |
|------|----|--------|
| `GIDClientID` | iOS 클라이언트 ID | `123456-abc.apps.googleusercontent.com` |
| `CFBundleURLTypes`의 google dict (**주석 상태**) | 리버스 클라이언트 ID | `com.googleusercontent.apps.123456-abc` |

> ⚠️ google URL 스킴 dict는 **주석 처리된 채로 커밋돼 있다.** 플레이스홀더(`REPLACE_…`)가 들어간
> 채로 두면 App Store 업로드가 거부되기 때문이다 — `altool` 오류 **90158**
> (`URL schemes need to begin with an alphabetic character, and be comprised of alphanumeric
> characters, the period, the hyphen or the plus sign only`; 언더스코어 불가).
> 실제 리버스 클라이언트 ID를 받은 뒤 **주석을 풀고** 값을 채울 것. 그전까지는 스킴이 없어도
> 네이티브 로그인이 웹 위임으로 폴백하므로 동작에 영향이 없다.

- (선택) 백엔드 검증에 서버 클라이언트 ID가 필요하면 주석 처리된 `GIDServerClientID` 키를 활성화.
- `AppConfig`는 값이 비었거나 `REPLACE…`를 포함하면 미설정으로 간주 → 웹 위임으로 폴백한다.
- 코드 변경 없이 Info.plist 값만 채우면 네이티브가 활성화된다.

## 🤖 백엔드 (`tas`) 신규 엔드포인트 — 필수

네이티브 로그인은 아래 엔드포인트가 있어야 **완결**된다(없으면 iOS는 자동으로 웹 위임 폴백).

`POST /api/mobile-auth/google` (공개)

**요청**
```json
{ "idToken": "<google id_token(JWT)>", "serverAuthCode": "<선택>", "invite": "<선택 초대코드>" }
```

**서버 처리**
1. `idToken` 서명 검증(Google 공개키) + 클레임 확인
   - `iss` ∈ `accounts.google.com` / `https://accounts.google.com`
   - `aud` ∈ { iOS 클라이언트 ID, (설정 시) 서버 클라이언트 ID }
   - `exp` 유효
2. `email`/`sub`로 사용자 조회, 없으면 생성(웹 NextAuth Google provider와 동일 규칙).
   `invite`가 있으면 신규 등록 시 초대코드 반영(웹 `tas-invite-code` 쿠키와 동일 처리).
3. 매장 컨텍스트 확정.

**응답** (기존 `/api/mobile-auth/exchange`와 **동일 형태**)
```json
{ "accessToken": "<Bearer JWT>", "expiresAt": 1730000000 }
```

**에러**: `no_store`/`no_session` 등은 4xx + `{ "error": "no_store" }`.
iOS `SessionStore.message(for:)`가 해당 사유 문자열을 사용자 메시지로 변환한다.

> ⚠️ 배포 안전: `auth-mobile-bridge.md`와 동일 — 인증 변경 PR은 사람 리뷰 게이트를 거치고,
> `getApiSession`의 쿠키 경로(웹 무회귀)를 보존한 채 Bearer만 추가한다.

## 관련 파일 (iOS)

- `TAS/Features/Login/GoogleSignInManager.swift` — SDK 래퍼(id_token 획득, 취소 판정)
- `TAS/Core/Session/SessionStore.swift` — `signInGoogle(invite:)`(네이티브↔웹 폴백)
- `TAS/Core/Networking/TASService.swift` — `exchangeGoogleIDToken(...)`
- `TAS/Core/Config/AppConfig.swift` — `googleClientID`/`googleServerClientID`
- `TAS/App/TASApp.swift` — `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`
- `TAS/Info.plist` — `GIDClientID` + 리버스 클라이언트 ID 스킴
- 패키지: `TAS.xcodeproj`(SPM) · `project.yml`(XcodeGen) 양쪽에 `GoogleSignIn-iOS` 7.x
