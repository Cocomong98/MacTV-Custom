# MacTV-Custom

MacBook Air M1과 LG 32UP830을 아이폰 하나로 제어하는 개인용 Mac TV 커스텀 프로젝트다. 기존 홈과 QR 웹 리모컨을 유지하고 국내 OTT, 유튜브 TV 모드, 화면별 밝기 및 측면 OSD를 추가한다.

Arunprakaash가 만든 [Mac TV v0.22](https://github.com/Arunprakaash/mac-tv/tree/v0.22)를 기반으로 한다. 원본 커밋 `50c9fd90f2f9f373cfdb5aed1a6adac15b369051`과 Git 이력, [MIT 라이선스](LICENSE)를 보존한다.

## 다운로드

[GitHub Releases](https://github.com/Cocomong98/MacTV-Custom/releases)에서 `MacTV-Custom-<버전>.dmg`를 받아 열고 **MacTV Custom.app**을 **Applications**로 끌어 놓는다. 이 앱은 임시 서명으로 배포한다. 최초 실행에서 macOS의 확인 화면이 나오면 설치 파일이 이 저장소의 릴리스에서 받은 것인지 확인한 뒤 Apple 안내를 따른다. [Apple의 앱 열기 안내](https://support.apple.com/ko-kr/102445)

## 시작하기

1. `AGENTS.md`와 [로드맵](docs/ROADMAP.md)에서 현재 단계와 미검증 항목을 확인한다.
2. 기준 버전은 원본 `v0.22` (`50c9fd90f2f9f373cfdb5aed1a6adac15b369051`)다. 공식 빌드와 테스트 절차는 [원본 기여 가이드](CONTRIBUTING.md)를 따른다.
3. 프로젝트 루트에서 `./build.sh --custom`으로 `build/MacTV Custom.app`을 빌드한다. `open "build/MacTV Custom.app"`으로 실행한다.

## 로컬 설치와 복구

- Finder에서 `build/MacTV Custom.app`을 그대로 열거나 응용 프로그램 폴더에 `MacTV Custom.app` 이름으로 복사한다. 설정과 페어링은 `~/Library/Application Support/MacTV Custom`과 별도 앱 환경설정에 저장된다. 최초 실행 때 화면에 표시된 QR로 아이폰을 연결한다.
- 초기 설정에서 필요한 OTT는 새로 로그인한다. 내장 플레이어는 커스텀 앱의 웹 세션을 사용한다. 외부 브라우저를 선택한 사이트는 그 브라우저의 프로필을 사용한다. 유튜브 광고 필터를 사용한다면 유니콘 Pro에서 실행용 `MacTV Custom.app`을 별도로 등록한다. LG의 BetterDisplay 밝기 경로에는 설치된 BetterDisplay가 실행 중이어야 한다.
- 로컬 네트워크 접근을 요청하면 아이폰 웹 리모컨에 필요한 권한을 허용한다. 외부 Chrome·IINA 창 배치와 조작에 필요한 경우 macOS 개인정보 보호 및 보안에서 `MacTV Custom`에 손쉬운 사용 권한을 부여한다. 임시 서명으로 다시 빌드하면 macOS가 권한을 다시 요청할 수 있다. 같은 로컬 서명으로 반복 빌드하려면 원본 스크립트 `./scripts/make-signing-cert.sh 'MacTV Custom Local Signing'`을 한 번 실행한다. 키체인에 로컬 서명 인증서를 만들며 유료 Apple Developer 계정은 필요 없다.
- 업데이트할 때는 커스텀 앱을 종료하고 `./build.sh --custom`으로 다시 빌드한다. 응용 프로그램 폴더에 복사해 쓰는 경우에만 그곳의 `MacTV Custom.app`을 새 빌드로 교체한다. 문제 발생 시 커스텀 앱을 종료한 뒤 기존 `/Applications/Mac TV.app`을 열면 기존 설정과 페어링을 사용할 수 있다. 원본 소스는 형제 폴더 `MacTV-Upstream`의 `v0.22`에 보존했다.

## 문서 찾기

| 문서 | 내용 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | 개발 원칙과 문서 참조 기준 |
| [환경](docs/ENVIRONMENT.md) | 장비, 연결, 버전과 권한 확인 항목 |
| [요구사항](docs/REQUIREMENTS.md) | R01–R16과 범위 |
| [아키텍처](docs/ARCHITECTURE.md) | 원본 조사 지점, 기능별 구현 후보와 제약 |
| [UI 명세](docs/UI_SPEC.md) | 홈, 아이폰 리모컨, 측면 OSD |
| [로드맵](docs/ROADMAP.md) | 원본 확보, 기준선 빌드, 구현 순서와 현황 |
| [테스트 계획](docs/TEST_PLAN.md) | 요구사항별 검증과 회귀 기준 |
| [결정 기록](docs/DECISIONS.md) | 확정된 선택과 기술 검토 항목 |
| [브랜치와 배포](docs/RELEASING.md) | 기능 브랜치, SemVer, DMG 게시 |

## 원본 프로젝트 안내

<p align="center">Turn a Mac into an Apple TV-style box: a tvOS-style home screen, your streaming apps in their official web players, and your phone as the remote.</p>

![Home screen](docs/screenshots/home.png)

### Screenshots

| Top Shelf | App grid |
|---|---|
| ![Top Shelf](docs/screenshots/top-shelf.png) | ![App grid](docs/screenshots/app-grid.png) |
| **Settings** | **Screensaver** |
| ![Settings](docs/screenshots/settings.png) | ![Screensaver](docs/screenshots/screensaver.png) |

| Phone remote | Apps | TV controls |
|---|---|---|
| ![Remote](docs/screenshots/remote.png) | ![Apps](docs/screenshots/remote-apps.png) | ![TV controls](docs/screenshots/remote-controls.png) |

### Install

1. Download `MacTV-<version>.dmg` from the [upstream releases](https://github.com/Arunprakaash/mac-tv/releases), open it, and drag **Mac TV** to Applications.
2. The first time you open it, macOS says it can't check the app, because it isn't notarized by Apple. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
3. When macOS asks whether Mac TV may accept incoming network connections, choose **Allow**, so your phone can reach the remote.
4. A short setup follows: choose your apps, scan a QR code to use your phone as the remote, and you're done.

Requires macOS 14 or later, on an Apple silicon or Intel Mac.

### What it does

- **Apple TV's home screen:** a Top Shelf of the latest shows on each app, a dock of app tiles and the full grid below, in Liquid Glass.
- **Your streaming apps:** Netflix, YouTube, Prime Video, JioHotstar, Apple TV, Spotify and YouTube Music in their official web players, with DRM. Add any website, Mac app or Steam game as a tile.
- **Phone remote:** scan a QR code, no app to install. Clickpad, touchpad, typing, volume and haptics; wake the screen, choose the display, or open a website. Works away from home over Tailscale.
- **Game controllers:** PlayStation, Xbox, Switch Pro and other controllers drive it like an Apple TV controller.
- **Movies:** plays your own video files, including MKV, with subtitles and Continue Watching, from the Mac, drives, a NAS (network shares stay connected) or a Jellyfin server you sign in to. Browse them from your phone.
- **Watching:** skips intros and recaps, plays the next episode, and has a sleep timer.
- **Screen saver:** Apple's live aerial wallpapers, show art, your photos, or drifting colour, with a clock.
- **Profiles:** each person gets their own apps and sign-ins.
- **Power:** keeps the Mac awake for the remote, and can stay awake with the lid closed.
- **Updates:** installs new versions by itself while nothing is playing, or when you choose in Settings › About.
- **Your browser (optional):** open websites in Brave, Chrome, Edge or another Chromium browser instead of the built-in player, with that browser's sign-ins, extensions and ad blocking. Close its window and you're back on Mac TV.

### Privacy

Mac TV has no account and no servers of its own, and never records what you watch. It asks once whether to share anonymous usage (which features you use) through [TelemetryDeck](https://telemetrydeck.com), and sends nothing unless you say yes. Every event is in [`Analytics.swift`](Sources/MacTV/Core/Analytics.swift). Details: [privacy policy](https://arunprakaash.github.io/mac-tv/privacy.html).

### Contributing

For the original project’s source, tests and pull requests, see [upstream CONTRIBUTING.md](https://github.com/Arunprakaash/mac-tv/blob/v0.22/CONTRIBUTING.md). For its security policy, see [upstream SECURITY.md](https://github.com/Arunprakaash/mac-tv/blob/v0.22/SECURITY.md).

### Who makes it

Mac TV is made by Arunprakaash ([LinkedIn](https://www.linkedin.com/in/Arunprakaash)). Questions and bug reports go to [GitHub issues](https://github.com/Arunprakaash/mac-tv/issues).

### License

MIT. See [LICENSE](LICENSE). "Mac" is an Apple trademark. This is a personal project, not affiliated with Apple, Netflix, Google, Amazon, JioStar, Spotify or Brave. App icons and service names belong to their owners and aren't covered by the license.
