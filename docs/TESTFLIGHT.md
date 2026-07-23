# TestFlight 자동 업로드 셋업

`.github/workflows/testflight.yml`이 App Store Connect API 키로 **아카이브 → 클라우드 서명 → 업로드**까지 자동으로 한다.
아래 Apple 쪽 준비(일회성)만 끝내고 GitHub Secrets 4개를 넣으면, 이후엔 GitHub Actions에서 **"TestFlight Upload" 워크플로우를 수동 실행**하면 새 빌드가 올라간다.

## 1. Apple 쪽 준비 (일회성)

1. **Apple Developer Program** 가입(유료, 연 $99).
2. **App Store Connect → 앱 → 신규 앱** 생성
   - 플랫폼: iOS
   - 번들 ID: `kr.co.takeaseat.app` (없으면 [Certificates, Identifiers & Profiles]에서 먼저 등록)
   - 이름/기본 언어/SKU 입력
3. **App Store Connect API 키 발급**
   - App Store Connect → **사용자 및 액세스 → 통합 → App Store Connect API → 키 생성**
   - 역할: **Admin** ⚠️ (클라우드 서명이 인증서·프로파일을 만들려면 Admin 권한이 필요. App Manager는 인증서 관리 권한이 없어 export에서 "Cloud signing permission error"가 남)
   - 생성 후 **`.p8` 키 파일을 다운로드(딱 한 번만 받을 수 있음)**
   - **Key ID**와 **Issuer ID**를 기록
4. **Team ID** 확인: Developer 계정 → Membership → Team ID (10자리).

## 2. GitHub Secrets 등록

리포 → Settings → Secrets and variables → Actions → **New repository secret** 로 4개 등록:

| Secret 이름 | 값 |
|---|---|
| `ASC_KEY_ID` | API 키의 Key ID |
| `ASC_ISSUER_ID` | API 키의 Issuer ID |
| `ASC_TEAM_ID` | Apple Developer Team ID (10자리) |
| `ASC_KEY_P8_BASE64` | `.p8` 파일을 base64로 인코딩한 문자열 |

`.p8` base64 만드는 법 (맥 터미널):
```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # 클립보드에 복사됨 → 시크릿 값으로 붙여넣기
```

## 3. 업로드 실행

GitHub → **Actions → "TestFlight Upload" → Run workflow**.
- `marketing_version` 입력란은 비워두면 프로젝트 설정값(예: `0.0.1`)을 그대로 쓴다. 표시 버전을 바꾸려면 여기에 입력(예: `0.0.2`).
- **빌드 번호(CFBundleVersion)는 GitHub run number로 자동 설정**되어 업로드마다 유일하다(규약: TestFlight마다 +1).

실행이 끝나면 App Store Connect에서 처리(10~30분) 후 TestFlight에 노출된다.
내부 테스터 그룹에 본인 계정을 추가하면 폰의 **TestFlight 앱**에서 바로 설치할 수 있다.

## 참고 / 문제 해결

- **버전 규약**: 표시 버전(`MARKETING_VERSION`)은 `0.0.0`에서 시작해 PR 머지 시 semver 범프, 빌드 번호(`CURRENT_PROJECT_VERSION`)는 업로드마다 +1 (이 워크플로우가 run number로 자동 처리). 자세한 내용은 루트 `CLAUDE.md`.
- **클라우드 서명**: 이 워크플로우는 인증서/프로파일을 수동 관리하지 않고 API 키로 Xcode가 자동 발급·서명(`-allowProvisioningUpdates`)한다. 팀에 배포용 인증서가 없으면 Xcode가 자동 생성한다.
- **"Cloud signing permission error" / "No profiles were found"**: API 키 역할이 **Admin**이어야 함(App Manager는 인증서 생성 불가). Admin 키로 재발급 후 `ASC_KEY_ID`·`ASC_KEY_P8_BASE64` 교체.
- **서명 실패 시**: `ASC_TEAM_ID`가 맞는지 확인. 그래도 안 되면 배포 인증서(.p12)+App Store 프로파일을 시크릿으로 넣는 수동 서명 또는 Fastlane `match` 방식으로 전환 가능.
- **첫 업로드는 수출 규정(Export Compliance) 질문**이 뜰 수 있다 — 암호화 미사용이면 App Store Connect에서 한 번 답하면 이후 자동 처리된다.
