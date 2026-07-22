# 모바일 인증 브리지 (Path A) — 설계

> tas-ios가 clipnote-ios처럼 **ASWebAuthenticationSession + 커스텀 스킴 딥링크**로
> Google/Kakao/Naver 로그인을 하도록, tas 백엔드(NextAuth v5, 쿠키 세션)에
> **모바일 전용 경로만 추가**한다. 기존 웹 로그인은 그대로 둔다(무회귀).
>
> 이 문서는 두 저장소(`tas` 백엔드 · `tas-ios`)의 계약(contract) 소스오브트루스다.

## 왜 이 방식인가
- clipnote는 Supabase Auth라 **토큰 네이티브** → 모바일이 쉬웠다.
- tas는 NextAuth **쿠키 세션**이라 앱이 그대로 못 붙는다(WKWebView는 Google이 차단).
- Path A = tas에도 **모바일 토큰 능력**을 달아준다. 웹은 NextAuth 유지, 앱만 Bearer 토큰.
- tas는 네이버를 NextAuth로 이미 지원하므로 clipnote의 네이버 우회로(magiclink)는 **불필요**.

## 전체 흐름
```
[iOS]  ASWebAuthenticationSession(callbackScheme: "tasios")
   │  open  https://takeaseat.co.kr/api/auth/mobile/start?provider=google&nonce=<N>
   ▼
[tas]  NextAuth OAuth (google/kakao/naver)  ← 기존 provider 재사용
   │  성공 → 세션 쿠키 발급 → callbackUrl=/api/auth/mobile/complete
   ▼
[tas]  /api/auth/mobile/complete
   │  세션 읽어 1회용 code 발급(nonce 바인딩, 60s, single-use)
   │  302 → tasios://auth/callback?code=<CODE>
   ▼
[iOS]  ASWeb 콜백으로 code 수신 → POST /api/auth/mobile/exchange {code, nonce}
   ▼
[tas]  code 검증 → Bearer 토큰(서명 JWT) 반환 {accessToken, expiresAt}
   ▼
[iOS]  Keychain 저장 → 이후 모든 요청에 Authorization: Bearer
```

## 백엔드 (`tas`) 작업
### 1. 신규 엔드포인트 (`server/api/auth/mobile/`)
| 엔드포인트 | 메서드 | 권한 | 설명 |
|-----------|-------|------|------|
| `/api/auth/mobile/start` | GET | 공개 | `provider`,`nonce` 받아 NextAuth OAuth 개시(callbackUrl=complete) |
| `/api/auth/mobile/complete` | GET | 세션 | 세션→1회용 code 발급, `tasios://auth/callback?code=`로 302. 실패 시 `?error=` |
| `/api/auth/mobile/exchange` | POST | 공개 | `{code,nonce}` 검증 → `{accessToken,expiresAt}` (서명 JWT) 반환 |

### 2. 1회용 code
- 서명 JWT 또는 서버 저장(Redis/DB). 클레임: `sub`(userId), `nonce`, `exp`(≤60s), `jti`.
- **single-use**: 교환 시 `jti` 소비 기록(재사용 거부). nonce 불일치 거부.

### 3. Bearer 토큰
- HS256 서명(`AUTH_SECRET` 재사용). 클레임: `sub`,`storeId`,`role`,`exp`(예: 30d).
- (선택) refresh 토큰으로 무중단 갱신. 1차엔 만료 시 재로그인으로 단순화.

### 4. `getApiSession` 확장 (`server/auth/api-session.ts`)
```
Authorization: Bearer <t> 있으면 → JWT 검증 → ApiSession(userId,storeId,role)
없으면 → 기존 쿠키(auth()) 경로  ← 웹 무회귀
```

## iOS (`tas-ios`) 작업 — clipnote 구조에 맞춤
- **커스텀 스킴 `tasios`** 등록 (Info.plist / project.yml `CFBundleURLTypes`).
- `Core/Config` — `Secrets.xcconfig`에서 `API_BASE` 주입(clipnote식 `https:/$()/` 트릭).
- `Auth/AuthDeepLink.swift` — `tasios://auth/callback?code=` / `?error=` 파싱.
- `Auth/AuthStore.swift` (`ObservableObject`) — `signIn(provider)`:
  1. nonce 생성 → `ASWebAuthenticationSession(url:start, callbackURLScheme:"tasios")`
  2. 콜백 code 수신 → `exchange` 호출 → 토큰 Keychain 저장 → 상태 갱신
  3. 유저 취소(`.canceledLogin`)는 무시.
- `Core/Session/KeychainTokenStore.swift` — 토큰 저장/조회/삭제.
- `APIClient` — 요청에 `Authorization: Bearer` 부착, 401 시 토큰 폐기·로그아웃.
- 현행 `WebAuthView`(WKWebView)는 이 방식 완성 후 제거.

## 보안 노트
- 커스텀 스킴은 비밀이 아님 → **1회용 code + single-use + nonce 바인딩 + 60s TTL**로 가로채기 방어.
- 실제 인증 채널은 ASWebAuthenticationSession(진짜 Safari) → Google 허용 + 안전.
- Bearer 토큰은 매 요청 서버 서명 검증. 유출 대비 만료·(선택)폐기 목록.

## ⚠️ 배포 안전 (중요)
tas 컨벤션은 **CI 그린 시 자동 머지 → Cloud Run 자동 배포**다. 인증 변경은
**자동 머지되면 즉시 프로덕션 로그인에 영향**을 준다. 따라서 이 작업 PR은:
- 자동 머지 대상에서 제외(사람 리뷰 게이트) 하거나
- 최소한 머지 전 명시적 승인을 받는다.
- `getApiSession`은 **쿠키 경로를 반드시 보존**(웹 무회귀)한 채 Bearer만 *추가*한다.

## 작업 분할(이슈 예정)
- [tas] `#a` 모바일 엔드포인트 3종 + 1회용 code
- [tas] `#b` Bearer 토큰 발급·검증 + `getApiSession` 확장
- [tas-ios] `#c` 커스텀 스킴 + Secrets.xcconfig + Keychain
- [tas-ios] `#d` AuthStore(ASWebAuth) + AuthDeepLink + APIClient Bearer, WKWebView 제거
