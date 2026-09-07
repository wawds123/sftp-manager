<div align="center">

<img src="docs/icon.png" width="120" alt="SFTP Manager">

# SFTP Manager

**macOS 네이티브 SFTP 파일 전송기**
왼쪽은 이 Mac, 오른쪽은 서버. 두 창 사이로 파일을 옮깁니다.

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.x-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Self-test](https://img.shields.io/badge/self--test-262%20passing-brightgreen)
![UI](https://img.shields.io/badge/UI-한국어%20·%20English-8A2BE2)

[English](README.en.md) · **한국어**

[**직접 빌드하기 →**](#build) · Command Line Tools만 있으면 됩니다

</div>

---

## 목차

| | |
|---|---|
| [✨ 기능](#features) | [⌨️ 단축키](#shortcuts) |
| [📦 의존성](#dependencies) | [🧰 직접 빌드하기](#build) |
| [✅ 검증](#verification) | [⚡ 전송 성능](#performance) |
| [🛡️ 보안 설계](#security-design) | [⚠️ 알려진 제약](#limitations) |
| [🗺️ 구조](#layout) | [📄 라이선스](#license) |

---

<a id="features"></a>

## ✨ 기능

### 🗂️ 두 창 브라우저

- **2분할** — 왼쪽 로컬 / 오른쪽 원격. 창마다 뒤로·앞으로·상위·홈 이동, 경로 직접 입력, 이름 필터
- **열** — 이름 · 크기 · 수정일 · 소유자 · 권한
  <sup>원격 소유자 이름은 서버가 함께 보내는 `ls -l` 줄에서 읽습니다(SFTP 자체는 숫자 uid만 보장합니다).
  읽을 수 없으면 uid를, 그것도 없으면 `—` 를 보여줍니다.</sup>
- **정렬** — 어느 열이든, 폴더 우선. 머리글을 누르면 정렬되고 다시 누르면 방향이 뒤집힙니다
- **빈 공간 우클릭** — 현재 폴더 기준 메뉴: 새 폴더, 새로 고침, Finder에서 열기, 선택 항목 업로드/다운로드,
  경로 복사, 상위/홈 이동, 숨김 파일 토글, 전체 선택
- **파일 조작** — 새 폴더, 이름 바꾸기, 삭제(원격은 재귀), 경로 복사, Finder에서 보기

### ⇅ 전송

- **보내는 법** — 버튼(`⌘→` / `⌘←`), 두 창 사이 끌어다 놓기, Finder에서 원격 창으로 바로 끌어 놓기
- **폴더째** — 하위 트리를 그대로 복제합니다
- **전송 큐** — 진행률과 속도 표시, 개별/전체 취소, 실패 항목 재시도
- **파이프라인** — 요청 64개를 동시에 띄우고 SSH 채널 윈도를 2MB로 올려 왕복 지연을 감춥니다
  → [전송 성능](#performance)
- **이름이 겹칠 때** — 기본값은 **물어보기**. 양쪽 파일의 크기·수정일을 나란히 보여주고 고르게 합니다

  | 선택 | 결과 |
  |---|---|
  | 덮어쓰기 | 있던 파일을 대체 |
  | 이름 바꿔 저장 | `report 2.pdf` 로 저장 |
  | 건너뛰기 | 그 항목만 넘어감 |
  | 취소 | 큐에 아무것도 넣지 않고 중단 |

  겹치는 게 여러 개면 `남은 N개에도 같은 선택 적용` 으로 한 번만 답하면 됩니다.
  항상 같은 동작을 원하면 툴바나 설정에서 고정할 수 있습니다.

- **더블클릭** — 로컬 파일은 **기본값이 업로드**입니다. `기본 앱으로 열기` 로 바꾸려면 로컬 창의 `…` 메뉴 또는
  메뉴 막대 `전송 › 로컬 파일 더블클릭`. 폴더는 설정과 무관하게 항상 이동하고, 두 동작 모두 우클릭 메뉴에
  남아 있습니다.

### 📝 원격 파일 편집

원격 파일 우클릭 → `편집기로 열기`. 내려받아 기본 편집기로 열고, **저장할 때마다 자동으로 다시 올립니다.**
편집 중인 파일은 툴바의 `편집 중` 메뉴에서 관리하고, 편집을 끝내면 임시 사본은 지워집니다.

### 💻 터미널

툴바의 `터미널` 또는 `보기 › 터미널`(`⌥⌘S`)로 아래쪽에 셸이 열립니다.
파일 창이 쓰는 **바로 그 SSH 연결에 채널을 하나 더 여는 방식**이라 —

- 비밀번호를 다시 묻지 않고, 호스트 키도 다시 확인하지 않습니다
- 서버 입장에서 두 번째 접속으로 잡히지 않습니다
- 연결을 끊으면 함께 닫힙니다

오른쪽 창이 보고 있는 폴더에서 시작하고, 명령이 끝나 출력이 멎으면 원격 목록을 자동으로 새로 고칩니다.

<details>
<summary><b>양쪽 위치 맞추기, 그리고 하지 않는 것</b></summary>

<br>

패널의 두 버튼이 창과 셸의 위치를 맞춥니다.

| 버튼 | 하는 일 |
|---|---|
| `터미널을 창 위치로` | 오른쪽 창이 보는 폴더로 셸을 `cd` |
| `창을 터미널 위치로` | 셸이 있는 폴더로 오른쪽 창을 이동 |

두 번째 버튼은 셸이 **스스로 알려준** 위치만 씁니다 — OSC 7 보고, 없으면 창 제목의 `user@host:경로`.
위치를 알아내려고 사용자의 터미널에 명령을 대신 입력하지는 않습니다. 셸이 OSC 7을 보내는 환경이면
`cd` 할 때마다 원격 창이 알아서 따라갑니다.

앱이 셸에 명령을 보낼 때는(시작 시 `cd`, 위 버튼) **먼저 입력하다 만 줄을 지웁니다.** 안 그러면 그 앞에
붙어서 한 줄로 실행됩니다. 지운 내용은 셸의 kill ring에 남아 `Ctrl-Y` 로 되살릴 수 있고,
`vim`·`less` 같은 전체 화면 프로그램이 떠 있을 때는 아예 보내지 않고 안내합니다.

`exit` 로 셸을 끝내면 화면은 그대로 남고 `다시 열기` 로 새 셸을 엽니다 — 탭을 오간다고 채널이 다시
열리지는 않습니다.

터미널 색은 앱 테마를 따릅니다. 어둡게로 바꾸면 이미 떠 있는 셸의 배경과 글자색도 함께 바뀝니다.

</details>

### 🌐 언어와 도움말

- **한국어 / 영어** — 설정 첫 탭에서 고릅니다. **고르는 즉시 바뀌고 앱을 다시 실행할 필요가 없습니다.**
  저장된 값이 없는 첫 실행에는 macOS의 언어 설정을 따릅니다.
- **도움말 (`⌘?`)** — `도움말 › SFTP Manager 도움말`.
  시작하기 · 파일 탐색 · 전송 · 원격 편집 · 터미널 · 단축키 · 보안 7개 주제를 두 언어로 담고 있습니다.

### ⚙️ 설정 (`⌘,`)

| 탭 | 내용 |
|---|---|
| 일반 | 언어, 테마(시스템/밝게/어둡게), 비밀번호 정책 안내 |
| 파일 목록 | 숨김 파일, 기본 정렬 기준·방향, 로컬 더블클릭 동작 |
| 전송 | 이름 충돌 기본 정책, 시작 시 전송 목록 열기, 완료 알림, 동시 요청 수 |
| 고급 | 편집 감시 주기, known_hosts·서버 목록 위치, 임시 파일 정리, 설정 초기화 |
| 정보 | 만든이, 버전, 사용 기술 |

아래 패널은 `전송` 과 `터미널` 탭이 같은 자리를 나눠 씁니다. 손잡이를 끌어 높이를 바꾸고, 두 번 클릭하면
내용에 맞춘 자동 크기로 돌아갑니다. 조절한 높이는 저장됩니다.

<a id="security"></a>

### 🔐 보안

- **비밀번호는 저장하지 않음** — 연결할 때마다 입력받고 메모리에만 둡니다. 키체인을 포함해 어디에도
  기록하지 않습니다. 개인 키는 **경로만** 저장하고, 키 파일이 실제로 암호화되어 있을 때만 키 암호를 묻습니다
  (OpenSSH 키 헤더의 cipher 필드로 판별). 이전 버전이 키체인에 저장해 둔 자격 증명은 첫 실행 때 한 번 삭제됩니다.
- **호스트 키 검증** — `~/.ssh/known_hosts`(`ssh` 와 같은 파일)로 서버 신원을 확인합니다. 처음 보는 서버는
  SHA256 지문을 보여주고 승인을 받으며, 키가 바뀌면 이전 지문과 함께 경고하고, `@revoked` 키는 거부합니다.
  검증은 키 교환 단계에서 이뤄지므로 **승인 전에는 비밀번호나 키가 서버로 전송되지 않습니다.**
- **서버 프로필** — 이름 · 호스트 · 포트 · 사용자 · 시작 경로
- **인증** — 비밀번호, ED25519 개인 키, RSA 개인 키

자세한 방어 설계는 [🛡️ 보안 설계](#security-design)에 있습니다.

---

<a id="shortcuts"></a>

## ⌨️ 단축키

| | | | |
|---|---|---|---|
| `⌘N` | 새 연결 | `⌘R` | 클릭한 창 새로 고침 |
| `⌘,` | 설정 | `⇧⌘R` | 양쪽 새로 고침 |
| `⌘?` | 도움말 | `⌘↑` | 로컬 상위 폴더 |
| `⌘→` | 업로드 | `⇧⌘↑` | 원격 상위 폴더 |
| `⌘←` | 다운로드 | `⌥⌘T` | 전송 목록 열기/닫기 |
| | | `⌥⌘S` | 터미널 열기/닫기 |

`⌘R` 은 **마지막으로 클릭한 창 하나만** 새로 고칩니다. 어느 창인지는 테두리로 표시됩니다.

---

<a id="dependencies"></a>

## 📦 의존성

| 패키지 | 라이선스 | 쓰임 |
|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH 연결, SFTP, PTY 채널 |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | 터미널 패널의 ANSI/vt100 에뮬레이션 |

나머지(swift-nio, swift-crypto, swift-log, swift-collections, BigInt 등)는 위 두 패키지가 끌어옵니다.

> [!NOTE]
> SSH 전송 계층은 `apple/swift-nio-ssh` 가 아니라
> [`Wellz26/swift-nio-ssh`](https://github.com/Wellz26/swift-nio-ssh) 포크에서 옵니다.
> 이 앱이 고른 게 아니라 **Citadel 0.12.1이 자기 `Package.swift` 에 그렇게 선언**해 둔 것입니다
> (인증서 인증과 Mac Catalyst 대응이 추가된 포크). SSH 클라이언트에서는 짚고 넘어갈 부분이라 적어 둡니다.
> 정확한 버전과 커밋은 `Package.resolved` 에 고정되어 있습니다.

---

<a id="build"></a>

## 🧰 직접 빌드하기

**소스에서 빌드하는 것이 원래 설치 방법입니다.** 편의를 위해
[릴리즈 빌드](https://github.com/wawds123/sftp-manager/releases)를 올려 두긴 했지만, 공증이 아닌 ad-hoc
서명이라 내려받으면 macOS가 격리해서 손으로 풀어줘야 합니다. 직접 빌드하면 명령 한 줄이면 되고
macOS도 군말 없이 실행합니다.

### 준비물

| | |
|---|---|
| macOS | 15 이상 — 원격 셸이 쓰는 PTY API가 여기서부터입니다 |
| Swift | 6.x. Command Line Tools에 포함돼 있습니다. **Xcode는 필요 없습니다** |

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

첫 빌드는 의존성을 받아 컴파일하므로 몇 분 걸립니다. 이후로는 증분 빌드라 빠릅니다. `.build/` 는 몇 GB까지
커지지만 git이 무시하므로, 공간이 필요하면 아무 때나 지워도 됩니다.

소스 폴더 밖으로 옮기려면 `mv build/SFTPManager.app /Applications/` 하면 됩니다.

본인이 직접 서명한 것이라 격리 속성이 붙지 않고, 따로 풀어줄 것도 없습니다.

### 옵션

```bash
./Scripts/make_app.sh --universal   # arm64 + x86_64 를 한 번들에
./Scripts/make_app.sh debug         # 디버그 빌드, 심볼 유지
```

릴리즈 빌드는 서명 전에 스트립해서 크기가 절반쯤 됩니다(슬라이스당 18.8MB → 9.0MB).
`--universal` 은 두 번째 아키텍처를 타깃 트리플로 따로 빌드해 `lipo` 로 합칩니다 —
`swift build --arch a --arch b` 는 Xcode 빌드 시스템을 요구하기 때문입니다.

### 개발할 때

`swift run SFTPManager` 는 빌드 디렉터리에서 바로 실행돼서 반복 작업에 빠릅니다. 실제로 쓸 때는
`make_app.sh` 로 만든 번들이 낫습니다 — Dock 아이콘이 붙고 코드 서명 신원이 고정됩니다.

셀프테스트, 번역 검사, 오프스크린 스냅샷은 [✅ 검증](#verification)에 있습니다. 전부 Xcode 없이 돕니다.

---

<a id="verification"></a>

## ✅ 검증

Command Line Tools 환경에는 XCTest가 없어서, **실행 가능한 셀프테스트**를 씁니다.

```bash
# 순수 로직만 — 경로 처리, 정렬/필터/히스토리, 셸 로직, 번역, 드래그 페이로드
swift run SFTPManager --selftest

# 실제 서버 상대로 SFTP 왕복까지
#   업로드 → 목록 → 다운로드(바이트 비교) → 이름 바꾸기 → 재귀 탐색 → 재귀 삭제
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519

# 전송 속도 측정 (지정한 크기만큼 주고받고 MB/s 출력)
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --bench-mb 64

# 암호로 보호된 키
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --passphrase '...'
```

**번역 누락은 정적으로도 검사합니다** — 뷰나 모델에 한글 문자열이 그대로 박혀 있으면 실패합니다.

```bash
./Scripts/check_l10n.sh
```

`--selftest` 는 열거 가능한 것(enum 레이블, 도움말 전체)을 훑고, 이 스크립트가 나머지 `L` 항목을
소스 검색으로 덮습니다.

<details>
<summary><b>UI 렌더링 확인 — 오프스크린 스냅샷</b> (화면 기록 권한 불필요)</summary>

<br>

```bash
swift run SFTPManager --snapshot /tmp/ui.png                       # 전체 창
swift run SFTPManager --snapshot /tmp/sidebar.png --view sidebar
swift run SFTPManager --snapshot /tmp/settings.png --view settings --tab advanced

# 고정 예시 데이터 — 실제 홈 디렉터리·저장된 서버를 읽지 않습니다
swift run SFTPManager --snapshot /tmp/demo.png --demo

# 도움말 / 정보 창, 언어와 주제를 지정해서
swift run SFTPManager --snapshot /tmp/help.png  --view help --lang en --topic terminal
swift run SFTPManager --snapshot /tmp/about.png --view about --lang ko

# 전송 목록 레이아웃 (샘플 항목 N개, 창 크기 지정)
swift run SFTPManager --snapshot /tmp/queue.png --view transfers --rows 12 --size 1100x620
```

스냅샷은 지정한 크기의 고정 컨테이너에 그려서 잘라냅니다 — 실제 창과 같은 조건이라 레이아웃이 창 밖으로
넘치는 문제도 그대로 드러납니다.

> `NavigationSplitView` 의 사이드바는 vibrancy 레이어에 있어 전체 창 스냅샷에서는 비어 보입니다.
> 사이드바를 확인할 때는 `--view sidebar` 를 쓰세요.

</details>

---

<a id="performance"></a>

## ⚡ 전송 성능

전송은 OpenSSH 클라이언트와 같은 방식으로 동작합니다.

| 조건 | 이전 | 현재 |
|---|---:|---:|
| RTT 40ms · 8MB 업로드 | 0.7 MB/s | **24.5 MB/s** |
| RTT 40ms · 8MB 다운로드 | 0.7 MB/s | **16.0 MB/s** |
| 루프백 · 64MB 업로드 | 237.8 MB/s | **473.7 MB/s** |
| 루프백 · 64MB 다운로드 | 248.6 MB/s | **344.6 MB/s** |

<sup>같은 조건에서 <code>scp</code> 는 각각 8.8 MB/s, 202.5 MB/s</sup>

<details>
<summary><b>느렸던 이유 두 가지</b></summary>

<br>

**1. 요청을 하나씩 보내고 응답을 기다렸습니다.**
32KB마다 왕복을 기다리면 속도 상한이 `32KB / RTT` 로 고정됩니다(RTT 40ms → 0.8 MB/s).
이제 요청 64개를 동시에 띄우고 도착하는 대로 처리합니다.

**2. SSH 채널 수신 윈도가 128KB였습니다.**
swift-nio-ssh는 자식 채널의 수신 윈도를 `maximumPacketSize`(기본 128KB)에서 가져오므로, 아무리 많이
요청해도 서버는 왕복당 128KB만 보낼 수 있었습니다. OpenSSH와 같은 2MB로 올렸습니다.
**다운로드가 업로드보다 훨씬 느렸던 원인**이 이것입니다.

진행률 콜백도 메인 액터로 넘기기 전에 100ms 단위로 합칩니다 — 초당 수천 번의 액터 홉이 전송보다
비쌌기 때문입니다.

</details>

---

<a id="security-design"></a>

## 🛡️ 보안 설계

> [!IMPORTANT]
> 서버가 보내는 값은 **하나도 믿지 않는다**는 전제로 만들었습니다. 파일 이름도 서버가 정하는 값입니다.

- **셸에 넘기는 경로는 항상 인용** — 터미널에 보내는 `cd` 는 경로를 작은따옴표로 감싸고, 안의 `'` 를
  `'\''` 로 닫았다 여는 POSIX 방식으로 이스케이프합니다. 서버가 파일 이름을 `$(...)` 나 `;rm -rf ~` 로
  지어도 명령이 되지 않습니다.
- **원격이 준 이름은 한 조각으로만 취급** — `/`, `.`, `..`, 널 바이트가 든 이름은 프로토콜상 정상적인
  디렉터리 항목이 아니므로 목록에서 걸러냅니다.
- **내려받는 경로는 대상 폴더를 벗어날 수 없음** — 폴더를 통째로 받을 때도 각 경로가 사용자가 고른 폴더
  안에 있는지 검사하고, 벗어나는 항목은 전송 큐에 **실패로 남깁니다**(조용히 넘기지 않습니다).
  원격 파일을 편집기로 열 때 만드는 임시 사본도 같은 검사를 거칩니다.
- **이름 입력란은 경로가 아님** — 새 폴더·이름 바꾸기에 `/` 가 들어간 값은 거부합니다.
- 호스트 키 검증과 비밀번호 비저장 정책은 [🔐 보안](#security) 항목을 참고하세요.

---

<a id="limitations"></a>

## ⚠️ 알려진 제약

- **RSA 키** — 백엔드(Citadel)가 레거시 `ssh-rsa` 서명만 지원합니다. OpenSSH 8.8 이상 서버는 이를 기본적으로
  거부하므로 **ED25519 키를 권장**합니다. RSA를 꼭 써야 한다면 서버 `sshd_config` 에
  `PubkeyAcceptedAlgorithms +ssh-rsa` 가 필요합니다. 앱이 이 상황을 감지해 오류 메시지에 안내를 넣습니다.
- **암호화된 개인 키** — 키 암호는 ED25519/RSA OpenSSH 키만 처리합니다. ECDSA 키는 미지원입니다.
- **로컬 → 로컬 복사**는 지원하지 않습니다.
- **언어 전환의 범위** — 앱이 직접 그리는 화면은 즉시 바뀌지만, macOS가 대신 넣어 주는 메뉴 항목
  (`종료`·`가리기`·`서비스`, 편집/윈도우 메뉴)은 시스템 언어를 따릅니다. `.lproj` 번들이 아니라 앱 안의
  문자열 표로 전환하기 때문입니다 — 그 대신 다시 실행하지 않고도 바로 바뀝니다.
- **비밀번호 재입력** — 저장하지 않으므로 연결할 때마다 입력해야 합니다. 세션 중 캐시도 하지 않습니다.
- **원격 셸** — 서버가 `ForceCommand internal-sftp` 등으로 셸을 막아 두었다면 터미널이 열리지 않습니다.
  `창을 터미널 위치로` 는 셸이 위치를 알리지 않는 환경(제목도 OSC 7도 없는 최소 프롬프트)에서는 쓸 수 없고,
  그 이유를 안내합니다. 명령 종료는 SSH가 알려주지 않으므로, 출력이 0.7초간 멎으면 끝난 것으로 봅니다.
- **전송 큐는 파일을 한 번에 하나씩** 처리합니다. 파일 하나의 속도는 위 표와 같지만, 아주 작은 파일이 많은
  폴더는 파일마다 열기/닫기 왕복이 필요해 여전히 느립니다.

---

<a id="layout"></a>

## 🗺️ 구조

```
Sources/SFTPManager/
├─ main.swift                 진입점 — GUI / --selftest / --snapshot 분기
├─ SFTPManagerApp.swift       App 정의, 메뉴 명령, 도움말·정보 창, AppDelegate
├─ SelfTest.swift             헤드리스 검증
├─ Snapshot.swift             오프스크린 UI 렌더링
├─ Model/
│  ├─ FileItem.swift          두 창이 공유하는 파일 항목 + 경로 유틸(봉쇄 검사 포함)
│  ├─ FileGlyph.swift         확장자·이름·폴더별 아이콘과 색 표
│  ├─ Localization.swift      한국어/영어 문자열 표와 언어 전환
│  └─ Connection.swift        서버 프로필 + 디스크 저장 (구 스키마 마이그레이션 포함)
├─ Core/
│  ├─ SFTPSession.swift       Citadel 기반 SSH/SFTP 액터 (목록·전송·재귀 삭제·트리 탐색)
│  ├─ ShellSession.swift      같은 연결 위의 PTY 셸 (SwiftTerm 연결, 유휴 감지 새로 고침)
│  ├─ LocalFileSystem.swift   로컬 파일 조작
│  ├─ KnownHosts.swift        known_hosts 파싱·매칭(해시 항목 포함)·지문 계산·기록
│  ├─ HostKeyValidator.swift  키 교환 단계의 호스트 키 검증과 거부 사유
│  ├─ OpenSSHKeyInspector.swift  개인 키가 암호화되어 있는지 헤더로 판별
│  ├─ Keychain.swift          구버전이 저장한 자격 증명 정리 (더 이상 저장하지 않음)
│  ├─ RemoteEdit.swift        편집 중인 원격 파일과 저장 감지 규칙
│  ├─ PaneState.swift         한쪽 창의 상태 (경로·목록·선택·정렬·히스토리)
│  ├─ Transfer.swift          전송 항목 모델
│  ├─ Preferences.swift       설정 읽기/쓰기, 테마 적용
│  ├─ AppModel.swift          앱 전역 상태, 연결 관리, 파일 조작
│  ├─ AppModel+Transfers.swift  전송 큐 확장·진행률·충돌 정책
│  └─ AppModel+Editing.swift  내려받기·감시·자동 재업로드
└─ Views/                     SwiftUI 화면
   ├─ HelpBook.swift          도움말 내용 (두 언어, 데이터로만)
   ├─ HelpView.swift          도움말 창
   └─ AboutView.swift         만든이·버전·사용 기술

Scripts/
├─ make_app.sh                .app 번들 조립 + ad-hoc 서명
├─ check_l10n.sh              하드코딩된 한글 문자열 검사
├─ make_icon.sh               아이콘 생성
└─ DrawIcon.swift             CoreGraphics 아이콘 드로잉
```

---

<a id="license"></a>

## 📄 라이선스

MIT — [LICENSE](LICENSE) 참조.

<a id="author"></a>

## 👤 만든이

**jackson** &lt;wawds123@gmail.com&gt;

앱 안에서는 `SFTP Manager › SFTP Manager 정보` 또는 `설정 › 정보` 에서 볼 수 있습니다.
