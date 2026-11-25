# CouchDial 개발 기록

2026-11-25에 CouchDial 0.3.1까지의 개발 기록을 정리했다. 초기 테스트 앱의 기능 및 재현 조건을 찾을 때는 [테스트 계획과 결과](TEST_PLAN.md)를 기준으로 삼는다. 각 기능의 요구사항은 [요구사항](REQUIREMENTS.md), 선택한 방법과 제약은 [결정 기록](DECISIONS.md), 화면과 조작은 [UI 명세](UI_SPEC.md), 배포 절차는 [브랜치와 배포](RELEASING.md)에 있다.

## 기능별 개발과 검증

| 단계 | 변경 및 검증 기록 | 소스와 배포 |
| --- | --- | --- |
| 기준선 | 원본 무수정 빌드에서 QR 연결, 홈, 기존 OTT, 스피커 음량 및 아이폰 재연결을 확인했다. Swift 139개와 웹 테스트 8종이 통과했다. | [Mac TV 원본 v0.22](https://github.com/Arunprakaash/mac-tv/tree/v0.22), 고정 커밋 [50c9fd9](https://github.com/Arunprakaash/mac-tv/commit/50c9fd90f2f9f373cfdb5aed1a6adac15b369051) |
| 국내 OTT | 웨이브·왓챠·티빙·라프텔 기본 타일과 홈 복귀를 확인했다. 서비스별 로그인 유지, DRM, 최대 화질과 전체화면 세부 결과는 기록이 없다. | [v0.1.0 소스](https://github.com/Cocomong98/MacTV-Custom/tree/v0.1.0), [당시 아이콘 변경](https://github.com/Cocomong98/MacTV-Custom/tree/add-ott-icons) |
| YouTube | 초기 YouTube TV 타일의 열기와 재생을 실기기에서 확인했다. 조작과 재생 회귀의 세부 범위는 테스트 기록에 있다. 0.3.0부터 공개판의 타일은 일반 웹 플레이어를 사용한다. | [초기 v0.1.0](https://github.com/Cocomong98/MacTV-Custom/tree/v0.1.0), [공개판 PR #1](https://github.com/Cocomong98/MacTV-Custom/pull/1) |
| 내장·외장 밝기 | M1 내장 밝기 읽기와 변경·복원을 확인했다. LG의 직접 DDC는 응답하지 않았다. 소프트웨어 밝기, 0·25·50·75·100% 프리셋과 길게 누르는 정밀 조작을 검증했고, 마지막에는 BetterDisplay 일반 밝기 눈금과 리모컨 값을 맞췄다. | [v0.1.0 밝기 구현](https://github.com/Cocomong98/MacTV-Custom/blob/v0.1.0/Sources/MacTV/Features/Display/DisplayBrightness.swift) |
| 측면 OSD | 조절할 화면의 밝기 왼쪽, 재생 화면의 음량 오른쪽 표시를 적용했다. Mac의 창과 macOS 전체화면에서 입력 포커스와 자동 닫힘을 확인했다. | [v0.1.0 측면 OSD](https://github.com/Cocomong98/MacTV-Custom/blob/v0.1.0/Sources/MacTV/Features/Display/SideLevelOSD.swift) |
| 아이폰 리모컨 | 화면별 밝기와 스피커 음량을 한 화면에 모았다. 여섯 화면 크기의 웹 레이아웃, 연결 복구, M1 내장 스피커 읽기·변경·복원을 확인했다. | [v0.1.0 리모컨](https://github.com/Cocomong98/MacTV-Custom/tree/v0.1.0/Sources/MacTV/Features/Remote) |
| 한국어·앱 아이콘·Homebrew | 첫 실행과 QR 안내를 한국어로 바꾸고 아이콘을 적용했다. 고정된 인증서로 DMG를 서명하고 기존 Cask 설치를 검증했다. 연속 업데이트에서 macOS 실행 승인이 이어지는지는 실기기 확인 항목이다. | [한국어 첫 연결](https://github.com/Cocomong98/MacTV-Custom/tree/add-korean-onboarding), [아이콘 변경](https://github.com/Cocomong98/MacTV-Custom/tree/add-custom-app-icon), [Homebrew 변경](https://github.com/Cocomong98/MacTV-Custom/tree/add-homebrew-cask), [v0.2.0](https://github.com/Cocomong98/MacTV-Custom/releases/tag/v0.2.0) |
| CouchDial 0.3.0 | 홈 상단 영역을 앱 초점과 연동하고 외부 추천을 제거했다. 서비스별 색 타일과 한국어 설정·제어 센터·웹 리모컨을 적용했다. 공개판과 개인용 로컬판의 산출물을 분리했다. 자동 검증과 공개 DMG 무결성을 확인했다. | [PR #1](https://github.com/Cocomong98/MacTV-Custom/pull/1), [v0.3.0](https://github.com/Cocomong98/MacTV-Custom/releases/tag/v0.3.0) |
| CouchDial 0.3.1 | 다른 환경의 첫 QR 연결에서 Safari가 Mac의 .local 주소에서 응답을 받지 못했다. 첫 QR을 숫자 IP로 열고, .local은 응답할 때만 사용하도록 바꿨다. Swift 144개, 웹 테스트 8종, Mac WebKit 재연결과 공개 DMG를 검증했다. 신고 기기의 최초 연결·조작·Safari 재연결은 확인 대상이다. | [PR #2](https://github.com/Cocomong98/MacTV-Custom/pull/2), [v0.3.1](https://github.com/Cocomong98/MacTV-Custom/releases/tag/v0.3.1) |
| 개인용 MacTV | 로컬판을 응용 프로그램 폴더에 설치하고 이름과 아이콘을 갱신했다. 로컬판의 번들 ID, 데이터 경로와 서명 요건을 유지했다. | 로컬 빌드 절차의 공개 개요는 [배포 문서](RELEASING.md)에 있다. 개인용 패치와 아이콘 원본은 Mac에 보관한다. |

## 예전 테스트 결과를 찾는 방법

- 기준선은 테스트 계획의 **기준선과 준비**, **결과 기록**을 참고한다.
- OTT, YouTube, 밝기, 측면 OSD, 리모컨은 각각 테스트 계획의 **1~5단계**에서 재현 조건과 결과를 확인할 수 있다. 밝기 테스트는 직접 DDC, 소프트웨어, 프리셋 및 BetterDisplay 통합 눈금을 별도로 읽는다.
- 통합 빌드와 서명·DMG·Homebrew는 테스트 계획의 **6단계**와 버전별 배포 항목에 기록돼 있다. [전체 변경 기록](../CHANGELOG.md)과 [GitHub Releases](https://github.com/Cocomong98/MacTV-Custom/releases)에서 공개 버전 간 차이를 비교할 수 있다.
- 초기 기능은 대체로 v0.1.0에 통합됐다. 각 테스트용 앱의 임시 번들, 페어링과 계정 세션의 사본은 이 브랜치에 포함하지 않는다. 당시 정확한 코드가 개별 커밋으로 남지 않은 경우, 통합 버전과 테스트 기록으로 범위를 확인한다.
