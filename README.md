<div align="center">

# SFTP Manager

**macOS 네이티브 SFTP 파일 전송기**
왼쪽은 이 Mac, 오른쪽은 서버. 두 창 사이로 파일을 옮깁니다.

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.x-F05138?logo=swift&logoColor=white)
![Version](https://img.shields.io/badge/version-0.0.1%20pre--release-orange)
![License](https://img.shields.io/badge/License-MIT-blue)
![UI](https://img.shields.io/badge/UI-한국어%20·%20English-8A2BE2)

[English](README.en.md) · **한국어**

</div>

| 밝게 | 어둡게 |
|:--:|:--:|
| <img src="docs/screenshot-light.png" alt="두 창 파일 브라우저"> | <img src="docs/screenshot-dark.png" alt="두 창 파일 브라우저, 어두운 테마"> |
| <img src="docs/terminal-light.png" alt="아래쪽 패널에 열린 원격 셸"> | <img src="docs/terminal-dark.png" alt="아래쪽 패널에 열린 원격 셸, 어두운 테마"> |

<div align="center"><sup>위: 두 창 브라우저와 전송 큐 · 아래: 같은 연결 위에서 열린 터미널. 테마는 설정에서 시스템·밝게·어둡게 중에 고릅니다.</sup></div>

---

## 목차

| | |
|---|---|
| [✨ 주요 기능](#features) | [⌨️ 단축키](#shortcuts) |
| [🧱 기술 스택](#stack) | [🧰 개발 및 빌드](#build) |
| [⚠️ macOS 설치 및 실행 시 주의사항](#macos) | [📄 라이선스](#license) |

---

<a id="features"></a>

## ✨ 주요 기능

### 🗂️ 두 창 파일 브라우저

- **좌우 분할** — 왼쪽 로컬, 오른쪽 원격. 창마다 뒤로 / 앞으로 / 상위 / 홈, 경로 직접 입력, 이름 필터
- **열** — 이름 · 크기 · 수정일 · 소유자 · 권한. 아무 열이나 눌러 정렬하고, 다시 누르면 역순 (폴더 우선)
- **파일 작업** — 새 폴더, 이름 변경, 삭제(원격은 재귀), 경로 복사, Finder에서 보기
- **빈 곳 우클릭** — 현재 폴더에 대한 메뉴: 새 폴더, 새로고침, Finder에서 열기, 선택 항목 전송,
  경로 복사, 상위/홈 이동, 숨김 파일 토글, 전체 선택

### ⇅ 파일 전송

- **보내는 방법** — 버튼(`⌘→` / `⌘←`), 두 창 사이 드래그, Finder에서 원격 창으로 바로 드래그
- **폴더째 전송** — 하위 구조를 그대로 옮깁니다
- **전송 큐** — 진행률과 속도 표시, 개별/전체 취소, 실패 항목 재시도
- **이름이 겹칠 때** — 기본값은 **물어보기**. 두 파일의 크기와 날짜를 나란히 보여줍니다.

  | 선택 | 결과 |
  |---|---|
  | 덮어쓰기 | 기존 파일을 대체 |
  | 이름 바꿔 저장 | `보고서 2.pdf` 로 저장 |
  | 건너뛰기 | 그 항목만 넘어감 |
  | 취소 | 아무것도 큐에 넣지 않고 중단 |

  여러 개가 겹치면 `남은 N개에 동일 적용` 으로 한 번에 답할 수 있고, 항상 같은 동작을 원하면
  툴바나 설정에서 정책을 고정할 수 있습니다.

- **더블클릭** — 로컬 파일은 **기본이 업로드**입니다. `기본 앱으로 열기` 로 바꾸려면 로컬 창의 `…`
  메뉴나 메뉴 막대의 `전송 › 로컬 파일 더블클릭` 을 쓰세요. 폴더는 어느 쪽이든 이동합니다.

<details>
<summary><b>전송 속도</b> — 요청 파이프라이닝과 SSH 채널 윈도</summary>

<br>

요청을 하나씩 보내고 답을 기다리면 32 KB마다 왕복이 생겨 `32 KB / RTT` 로 묶입니다. 요청 64개를
동시에 띄우고, swift-nio-ssh가 128 KB로 잡는 채널 수신 윈도를 OpenSSH와 같은 2 MB로 올렸습니다.
**다운로드가 업로드보다 유독 느렸던 이유가 이 윈도였습니다.**

| 조건 | 이전 | 현재 |
|---|---:|---:|
| 40 ms RTT · 8 MB 업로드 | 0.7 MB/s | **24.5 MB/s** |
| 40 ms RTT · 8 MB 다운로드 | 0.7 MB/s | **16.0 MB/s** |
| 루프백 · 64 MB 업로드 | 237.8 MB/s | **473.7 MB/s** |
| 루프백 · 64 MB 다운로드 | 248.6 MB/s | **344.6 MB/s** |

<sup>같은 조건에서 <code>scp</code> 는 각각 8.8 MB/s, 202.5 MB/s 입니다</sup>

</details>

### 📝 원격 파일 편집

원격 파일 우클릭 → `편집기로 열기`. 임시 사본을 내려받아 기본 편집기에 넘기고,
**저장할 때마다 다시 올립니다.** 열려 있는 파일은 툴바의 `편집 중` 메뉴에서 관리하며,
중지하면 임시 사본을 지웁니다.

### 💻 터미널

툴바의 `터미널` 버튼이나 `보기 › 터미널`(`⌥⌘S`)로 아래쪽 패널에 셸이 열립니다.
파일 창이 쓰는 **바로 그 SSH 연결에 채널을 하나 더 여는 방식**이라 —

- 비밀번호를 다시 묻지 않고, 호스트 키도 다시 확인하지 않습니다
- 서버에는 접속이 하나로 보입니다
- 연결이 끊기면 같이 닫힙니다

원격 창이 보고 있는 폴더에서 시작하고, 명령이 끝나 출력이 잠잠해지면 원격 목록을 새로고침합니다.
`터미널을 창 위치로` / `창을 터미널 위치로` 버튼으로 둘의 위치를 맞출 수 있는데, 후자는 셸이
**스스로 알려준** 위치(OSC 7, 없으면 창 제목의 `user@host:path`)만 씁니다 — 위치를 알아내려고
사용자의 터미널에 명령을 몰래 입력하지 않습니다. `exit` 로 끝내도 화면은 남고 `다시 열기` 로
새로 시작합니다.

### 🔐 보안

- **비밀번호를 저장하지 않습니다** — 연결할 때마다 입력받고 메모리에만 둡니다. 키체인을 포함해
  어디에도 쓰지 않습니다. 개인 키는 **경로만** 저장하고, 키 파일이 실제로 암호화되어 있을 때만
  암호를 묻습니다. 예전 버전이 키체인에 넣어둔 자격 증명은 첫 실행 때 한 번 삭제합니다.
- **호스트 키 검증** — `ssh` 와 같은 `~/.ssh/known_hosts` 로 서버를 확인합니다. 처음 보는 서버는
  SHA256 지문을 보여주고, 키가 바뀌었으면 이전 지문과 함께 경고하며, `@revoked` 키는 거부합니다.
  키 교환 단계에서 일어나므로 **승인 전에는 서버로 아무것도 보내지 않습니다.**
- **서버가 보낸 값은 믿지 않습니다** — 셸에 넣는 경로는 항상 따옴표로 감싸고(`'\''` 이스케이프),
  `/` · `.` · `..` · NUL 이 든 이름은 목록에서 제외하며, 폴더째 내려받을 때도 모든 경로가 고른
  폴더 안인지 검사해 벗어나면 실패로 남깁니다.

### 🌐 언어 · 도움말 · 설정

- **한국어 / English** — 설정 첫 탭에서 고릅니다. **고르는 즉시 바뀌고 다시 실행할 필요가 없습니다.**
  저장된 값이 없으면 첫 실행 때 macOS 언어를 따라갑니다.
- **도움말(`⌘?`)** — 시작하기, 탐색, 전송, 원격 편집, 터미널, 단축키, 보안 7개 주제를 두 언어로.
- **폰트** — 설정 › 폰트에서 인터페이스 폰트와 글자 크기, 터미널 폰트와 크기를 따로 고릅니다. 터미널
  목록에는 고정폭 폰트만 나오고, Nerd Font 계열을 고르면 셸 프롬프트의 아이콘 글자까지 제대로 보입니다.
  아무것도 번들하지 않고 Mac에 설치된 폰트를 씁니다.
- **설정(`⌘,`)** — 일반(언어·테마·비밀번호 정책) / 폰트(인터페이스·터미널) /
  파일 목록(숨김 파일·기본 정렬·더블클릭) / 전송(충돌 기본값·시작 시 큐 열기·완료 알림·동시 요청 수) /
  고급(편집 확인 주기·경로·초기화) / 정보

---

<a id="shortcuts"></a>

## ⌨️ 단축키

| | | | |
|---|---|---|---|
| `⌘N` | 새 연결 | `⌘R` | 클릭한 창 새로고침 |
| `⌘,` | 설정 | `⇧⌘R` | 양쪽 창 새로고침 |
| `⌘?` | 도움말 | `⌘↑` | 로컬 상위 폴더 |
| `⌘→` | 업로드 | `⇧⌘↑` | 원격 상위 폴더 |
| `⌘←` | 다운로드 | `⌥⌘T` | 전송 목록 열기/닫기 |
| | | `⌥⌘S` | 터미널 열기/닫기 |

`⌘R` 은 **마지막으로 클릭한 창 하나만** 새로고침합니다 — 테두리가 강조된 쪽입니다.

---

<a id="stack"></a>

## 🧱 기술 스택

| 항목 | 사용 |
|---|---|
| 언어 · UI | Swift 6 (언어 모드 5) · SwiftUI, AppKit 연동은 `NSViewRepresentable` |
| 동시성 | actor 기반 세션, `@MainActor` UI, 진행률 콜백은 100 ms 단위로 합침 |
| 빌드 | SwiftPM 실행 파일 + 손으로 조립하는 `.app` 번들 (Xcode 불필요) |
| 최소 사양 | macOS 15 |

| 패키지 | 라이선스 | 쓰임 |
|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH 연결, SFTP, PTY 채널 |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | 터미널 패널의 ANSI/vt100 에뮬레이션 |

나머지(swift-nio, swift-crypto, swift-log, swift-collections, BigInt 등)는 위 둘이 끌고 옵니다.

> [!NOTE]
> SSH 전송 계층은 `apple/swift-nio-ssh` 가 아니라
> [`Wellz26/swift-nio-ssh`](https://github.com/Wellz26/swift-nio-ssh) 포크를 씁니다. 이 앱이 고른 게
> 아니라 **Citadel 0.12.1 이 자기 `Package.swift` 에 그렇게 선언**해 둔 것입니다(포크는 인증서 인증과
> Mac Catalyst 지원을 추가). SSH 클라이언트라면 밝혀 둘 만한 사실이라 적습니다. 정확한 버전과 커밋은
> `Package.resolved` 에 고정되어 있습니다.

---

<a id="build"></a>

## 🧰 개발 및 빌드

**설치 방법은 소스 빌드 하나뿐입니다.** 아직 0.0.1이라 미리 빌드한 파일은 올려 두지 않았습니다.

### 준비물

| | |
|---|---|
| macOS | 15 이상 — 원격 셸이 쓰는 PTY API가 여기서부터 있습니다 |
| Swift | 6.x. Command Line Tools에 들어 있으며 **Xcode는 필요 없습니다** |

`swift --version` 이 응답하지 않으면 Command Line Tools를 설치하세요.

```bash
xcode-select --install
```

### 빌드와 실행

```bash
git clone https://github.com/wawds123/sftp-manager.git
cd sftp-manager

./Scripts/make_icon.sh     # Resources/AppIcon.icns 생성 (최초 1회)
./Scripts/make_app.sh      # build/SFTPManager.app 생성
open build/SFTPManager.app
```

첫 빌드는 의존성을 받아 컴파일하므로 몇 분 걸리고, 이후는 증분 빌드입니다. `.build/` 는 몇 GB까지
커지지만 git에서 제외되어 있으니 언제든 지워도 됩니다. 소스 밖으로 옮기려면
`mv build/SFTPManager.app /Applications/`.

### 옵션

```bash
./Scripts/make_app.sh --universal   # arm64 + x86_64 한 번들에
./Scripts/make_app.sh debug         # 디버그 빌드, 심볼 유지
swift run SFTPManager               # 번들 없이 바로 실행 (개발 중)
```

릴리즈 빌드는 서명 전에 strip 해서 크기가 대략 절반이 됩니다(슬라이스당 18.8 MB → 9.0 MB).
`swift build --arch a --arch b` 는 Xcode의 빌드 시스템을 요구하므로, `--universal` 은 두 번째
아키텍처를 명시적 타깃 트리플로 따로 빌드해 `lipo` 로 붙입니다.

### 검증

Command Line Tools 환경에는 XCTest가 없어서, **실행 가능한 자체 검사**를 씁니다.

```bash
# 순수 로직 — 경로 처리, 정렬·필터·히스토리, 셸 로직, 번역, 드래그 페이로드
swift run SFTPManager --selftest

# 실제 서버 대상: 업로드 → 목록 → 다운로드(바이트 비교) → 이름 변경 → 재귀 순회 → 재귀 삭제
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519

# 처리량 측정 (지정한 크기를 양방향으로 보내고 MB/s 출력)
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --bench-mb 64

# 뷰나 모델에 한글 문자열이 하드코딩되어 있으면 실패
./Scripts/check_l10n.sh
```

<details>
<summary><b>화면 확인 — 오프스크린 스냅샷</b> (화면 기록 권한이 필요 없습니다)</summary>

<br>

```bash
swift run SFTPManager --snapshot /tmp/ui.png                       # 창 전체
swift run SFTPManager --snapshot /tmp/settings.png --view settings --tab advanced

# 고정된 예시 데이터 — 홈 디렉터리도, 저장된 서버 목록도 읽지 않습니다
swift run SFTPManager --snapshot /tmp/demo.png --demo

# 도움말·정보 창을 원하는 언어와 주제로
swift run SFTPManager --snapshot /tmp/help.png --view help --lang ko --topic terminal

# 창 프레임(제목 표시줄·툴바)까지, 레티나 2배로
swift run SFTPManager --snapshot /tmp/window.png --demo --chrome --scale 2
```

고정 크기 컨테이너에 그린 뒤 잘라내므로 실제 창과 같은 조건입니다 — 넘치는 레이아웃은 넘친 채로 보입니다.
`--chrome` 은 그 고정 크기 검사 대신 진짜 창 프레임을 그리므로, 레이아웃 확인이 아니라 스크린샷용입니다.
`--demo` 로 만든 그림에는 홈 디렉터리 경로도, 저장된 서버 목록도 들어가지 않습니다.

</details>

---

<a id="macos"></a>

## ⚠️ macOS 설치 및 실행 시 주의사항

- **직접 빌드한 앱은 막히지 않습니다.** `make_app.sh` 가 ad-hoc 서명까지 해주고, 내려받은 파일이
  아니라 격리(quarantine) 속성이 붙지 않기 때문입니다.
- **어딘가에서 받은 `.zip` 이라면** 공증되지 않은 앱이라 Gatekeeper가 조용히 실행을 막습니다.
  Finder에서 **우클릭 → 열기** 로 한 번 허용하거나, 격리 속성을 직접 떼세요.
  ```bash
  xattr -dr com.apple.quarantine /Applications/SFTPManager.app
  ```
- **처음 접속하는 서버는 지문 승인이 필요합니다.** SHA256 지문이 뜨면 서버에서
  `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` 로 확인한 값과 맞는지 보고 승인하세요.
  승인하면 `~/.ssh/known_hosts` 에 기록됩니다.
- **비밀번호는 매번 입력합니다.** 저장하지 않는 설계이고, 한 세션 안에서도 캐시하지 않습니다.
- **RSA 키는 권장하지 않습니다.** 백엔드(Citadel)가 구식 `ssh-rsa` 로만 서명하는데 OpenSSH 8.8+ 는
  이를 기본적으로 거부합니다. **ED25519 키를 쓰세요.** 꼭 RSA를 써야 한다면 서버 `sshd_config` 에
  `PubkeyAcceptedAlgorithms +ssh-rsa` 가 필요하며, 이 경우 앱이 오류 메시지로 알려줍니다.
  암호가 걸린 키는 ED25519·RSA만 지원하고 ECDSA는 지원하지 않습니다.
- **언어 전환이 닿지 않는 곳이 있습니다.** 앱이 직접 그리는 화면은 즉시 바뀌지만, macOS가 넣어주는
  메뉴(`종료`, `가리기`, `서비스`, 편집·윈도우 메뉴)는 시스템 언어를 따릅니다. `.lproj` 대신 앱 안의
  문자열 표를 쓴 대가이고, 대신 다시 실행할 필요가 없습니다.
- **셸을 막아 둔 서버**(`ForceCommand internal-sftp` 등)에서는 터미널이 열리지 않습니다.
- **로컬 ↔ 로컬 복사는 지원하지 않습니다.**
- **큐는 한 번에 한 파일씩 보냅니다.** 큰 파일은 위 속도가 나오지만, 작은 파일이 아주 많은 폴더는
  파일마다 열기/닫기 왕복이 필요해 여전히 느립니다.

---

<a id="license"></a>

## 📄 라이선스

MIT — [LICENSE](LICENSE) 참고.
