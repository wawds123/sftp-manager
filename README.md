# SFTP Manager

macOS 네이티브 SFTP 파일 전송기. 왼쪽은 로컬, 오른쪽은 원격의 2분할 파일 브라우저입니다.

## 기능

- **2분할 브라우저** — 왼쪽 로컬 / 오른쪽 원격, 각 창마다 뒤로·앞으로·상위·홈 이동, 경로 직접 입력, 이름 필터
- **열** — 이름 / 크기 / 수정일 / 소유자 / 권한. 원격 소유자 이름은 서버가 함께 보내는 `ls -l` 줄에서
  읽습니다(SFTP 자체는 숫자 uid만 보장합니다). 읽을 수 없으면 uid를 보여주고, 그것도 없으면 `—`입니다.
- **정렬** — 위 열 중 아무거나, 폴더 우선. 열 머리글 아무 데나 클릭하면 정렬되고 다시 누르면 방향 전환
- **전송** — 버튼(⌘→ 업로드 / ⌘← 다운로드), 창 사이 끌어다 놓기, Finder에서 원격 창으로 끌어다 놓기
- **폴더 전송** — 하위 트리를 그대로 복제. 진행률·속도가 표시되는 전송 큐, 개별/전체 취소, 실패 항목 재시도
- **파이프라인 전송** — 요청 64개를 동시에 띄우고 SSH 채널 윈도를 2MB로 올려 왕복 지연을 감춥니다 (`scp` 와 동급)
- **충돌 처리** — 기본값은 **물어보기**입니다. 이름이 겹치면 확인 창이 떠서 양쪽 파일의 크기·수정일을
  나란히 보여주고 덮어쓰기 / 이름 바꿔 저장(`report 2.pdf`) / 건너뛰기 / 취소를 고릅니다. 겹치는 게 여러
  개면 `남은 N개에도 같은 선택 적용`으로 한 번만 답하면 됩니다. 항상 같은 동작을 원하면 툴바나 설정에서
  덮어쓰기·이름 바꿔 저장·건너뛰기로 고정할 수 있습니다.
- **파일 조작** — 새 폴더, 이름 바꾸기, 삭제(원격은 재귀 삭제), 경로 복사, Finder에서 보기
- **빈 공간 우클릭** — 창의 아무 곳이나 우클릭하면 현재 폴더 기준 메뉴가 뜹니다: 새 폴더, 새로 고침,
  Finder에서 열기(로컬), 선택 항목 업로드/다운로드, 경로 복사, 상위/홈 이동, 숨김 파일 토글, 전체 선택
- **한국어 / 영어** — 설정 첫 탭에서 언어를 고릅니다. 고르는 즉시 바뀌며 앱을 다시 실행할 필요가 없습니다.
  저장된 값이 없는 첫 실행에는 macOS의 언어 설정을 따릅니다. ([영어 화면](docs/screenshot-en.png))
- **도움말 (⌘?)** — `도움말 › SFTP Manager 도움말`. 시작하기·파일 탐색·전송·원격 편집·터미널·단축키·보안
  7개 주제를 두 언어로 담고 있습니다.
- **설정 창 (⌘,)** — 언어, 테마(시스템/밝게/어둡게), 파일 목록 기본값(숨김 파일·정렬·더블클릭 동작),
  전송 기본값(충돌 정책·완료 알림·동시 요청 수), 고급(편집 감시 주기, known_hosts·서버 목록 위치,
  임시 파일 정리, 설정 초기화)
- **원격 셸(터미널)** — 툴바의 `터미널` 또는 `보기 › 터미널`(⌥⌘S)로 아래쪽에 셸이 열립니다. 파일 창이 쓰는
  **바로 그 SSH 연결에 채널을 하나 더 여는 방식**이라 비밀번호를 다시 묻지 않고, 호스트 키도 다시 확인하지
  않으며, 연결을 끊으면 함께 닫힙니다. 오른쪽 창이 보고 있는 폴더에서 시작하고, 명령이 끝나 출력이 멎으면
  원격 목록을 자동으로 새로 고칩니다. 원격 창 빈 곳 우클릭 → `여기서 터미널 열기`로도 열 수 있습니다.
  패널의 `창 → 터미널` / `터미널 → 창` 버튼으로 양쪽 위치를 맞출 수 있습니다. 뒤쪽 버튼은 셸이 **스스로
  알려준** 위치(OSC 7 보고, 없으면 창 제목의 `user@host:경로`)를 씁니다 — 위치를 알아내려고 터미널에
  명령을 대신 입력하지는 않습니다. 셸이 OSC 7을 보내는 환경이면 `cd` 할 때마다 원격 창이 알아서 따라갑니다.
  터미널 색은 앱 테마를 따릅니다 — 어둡게로 바꾸면 이미 떠 있는 셸의 배경과 글자색도 함께 바뀝니다.
  앱이 셸에 명령을 보낼 때는(시작 시 `cd`, 위 버튼) 먼저 입력하다 만 줄을 지웁니다. 안 그러면 그 앞에
  붙어서 한 줄로 실행됩니다. 지운 내용은 셸의 kill ring에 남아 Ctrl-Y로 되살릴 수 있고, `vim`·`less` 같은
  전체 화면 프로그램이 떠 있을 때는 아예 보내지 않고 안내합니다.
- **아래 패널** — `전송`과 `터미널` 탭이 같은 자리를 나눠 씁니다. 기본값은 실행 시 `전송` 탭이 열린 상태이며
  설정에서 끌 수 있습니다.
- **전송 목록 크기 조절** — 목록 위 손잡이를 끌어 높이를 바꿀 수 있고, 두 번 클릭하면 내용에 맞춘 자동
  크기로 돌아갑니다. 조절한 높이는 저장됩니다.
- **더블클릭 동작** — 로컬 파일을 더블클릭하면 **기본값은 업로드**. `기본 앱으로 열기`로 바꾸려면
  로컬 창의 `…` 메뉴 또는 메뉴 막대 `전송 › 로컬 파일 더블클릭` 에서 선택 (선택은 저장됩니다).
  폴더는 설정과 무관하게 항상 이동하고, 두 동작 모두 우클릭 메뉴에 항상 남아 있습니다.
- **서버 프로필** — 이름·호스트·포트·사용자·시작 경로 저장
- **인증** — 비밀번호, ED25519 개인 키, RSA 개인 키
- **호스트 키 검증** — `~/.ssh/known_hosts`(`ssh`와 같은 파일)로 서버 신원을 확인합니다. 처음 보는 서버는
  SHA256 지문을 보여주고 승인을 받으며, 키가 바뀌면 이전 지문과 함께 경고합니다. `@revoked` 키는 거부합니다.
  검증은 키 교환 단계에서 이뤄지므로 **승인 전에는 비밀번호나 키가 서버로 전송되지 않습니다.**
- **원격 파일 편집** — 원격 파일 우클릭 → `편집기로 열기`. 내려받아 기본 편집기로 열고, 저장할 때마다
  자동으로 다시 올립니다. 편집 중인 파일은 툴바의 `편집 중` 메뉴에서 관리합니다.
- **비밀번호는 저장하지 않음** — 연결할 때마다 입력받고 메모리에만 두며, 어디에도 기록하지 않습니다.
  개인 키는 경로만 저장하고, **키 파일이 실제로 암호화되어 있을 때만** 연결 시 키 암호를 묻습니다
  (OpenSSH 키 헤더의 cipher 필드를 읽어 판별). 이전 버전이 키체인에 저장해 둔 자격 증명은 첫 실행 때 한 번 삭제됩니다.

## 의존성

| 패키지 | 라이선스 | 쓰임 |
| --- | --- | --- |
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH 연결, SFTP, PTY 채널 |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | 터미널 패널의 ANSI/vt100 에뮬레이션 |

나머지(swift-nio, swift-crypto, swift-log, swift-collections, BigInt 등)는 위 두 패키지가 끌어옵니다.

> **알아둘 것**: SSH 전송 계층은 `apple/swift-nio-ssh` 가 아니라
> [`Wellz26/swift-nio-ssh`](https://github.com/Wellz26/swift-nio-ssh) 포크에서 옵니다.
> 이 앱이 고른 게 아니라 **Citadel 0.12.1이 자기 `Package.swift` 에 그렇게 선언**해 둔 것입니다
> (인증서 인증과 Mac Catalyst 대응이 추가된 포크). SSH 클라이언트에서는 짚고 넘어갈 부분이라
> 적어 둡니다. 정확한 버전과 커밋은 `Package.resolved` 에 고정되어 있습니다.

## 요구 사항

- macOS 15 이상 (원격 셸이 쓰는 PTY API가 macOS 15부터입니다)
- Swift 6.x (Command Line Tools만 있어도 됨 — Xcode 불필요)

## 빌드

```bash
./Scripts/make_icon.sh     # 앱 아이콘 생성 (최초 1회)
./Scripts/make_app.sh      # build/SFTPManager.app 생성
open build/SFTPManager.app
```

개발 중에는 `swift run SFTPManager` 로도 실행되지만, Dock 아이콘과 안정적인 키체인 접근을 위해서는
`make_app.sh` 로 만든 번들을 쓰는 편이 좋습니다 (스크립트가 ad-hoc 서명을 붙여 코드 서명 신원을 고정합니다).

## 검증

이 저장소는 XCTest 대신 실행 가능한 셀프테스트를 씁니다 (Command Line Tools 환경에는 XCTest가 없습니다).

```bash
# 순수 로직만 검사 (경로 처리, 정렬/필터/히스토리, 드래그 페이로드)
swift run SFTPManager --selftest

# 실제 서버를 상대로 SFTP 왕복까지 검사
#   업로드 → 목록 → 다운로드(바이트 비교) → 이름 바꾸기 → 재귀 탐색 → 재귀 삭제
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519

# 전송 속도 측정 (지정한 크기만큼 업로드/다운로드하고 MB/s 출력)
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --bench-mb 64

# 암호로 보호된 키
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --passphrase '...'
```

번역 누락은 정적으로도 검사합니다 — 뷰나 모델에 한글 문자열이 그대로 박혀 있으면 실패합니다:

```bash
./Scripts/check_l10n.sh
```

`--selftest` 는 열거 가능한 것(enum 레이블, 도움말 전체)을 훑고, 이 스크립트가 나머지 `L` 항목을
소스 검색으로 덮습니다.

UI 렌더링은 오프스크린 스냅샷으로 확인합니다 (화면 기록 권한 불필요):

```bash
swift run SFTPManager --snapshot /tmp/ui.png            # 전체 창
swift run SFTPManager --snapshot /tmp/sidebar.png --view sidebar
swift run SFTPManager --snapshot /tmp/settings.png --view settings --tab advanced

# README용 스크린샷 — 실제 홈 디렉터리·저장된 서버 대신 고정 예시 데이터를 씁니다
swift run SFTPManager --snapshot docs/screenshot.png --demo

# 도움말 / 정보 창, 언어를 지정해서
swift run SFTPManager --snapshot /tmp/help.png  --view help --lang en --topic terminal
swift run SFTPManager --snapshot /tmp/about.png --view about --lang ko

# 전송 목록 레이아웃 (샘플 항목 N개, 창 크기 지정)
swift run SFTPManager --snapshot /tmp/queue.png --view transfers --rows 12 --size 1100x620
```

스냅샷은 지정한 크기의 고정 컨테이너에 그려서 잘라냅니다 — 실제 창과 같은 조건이라
레이아웃이 창 밖으로 넘치는 문제도 그대로 드러납니다.

> `NavigationSplitView`의 사이드바는 vibrancy 레이어에 있어 전체 창 스냅샷에서는 비어 보입니다.
> 사이드바를 확인할 때는 `--view sidebar` 를 쓰세요.

## 전송 성능

전송은 OpenSSH 클라이언트와 같은 방식으로 동작합니다.

| | 이전 | 현재 |
|---|---|---|
| RTT 40ms, 8MB 업로드 | 0.7 MB/s | **24.5 MB/s** |
| RTT 40ms, 8MB 다운로드 | 0.7 MB/s | **16.0 MB/s** |
| 루프백, 64MB 업로드 | 237.8 MB/s | **473.7 MB/s** |
| 루프백, 64MB 다운로드 | 248.6 MB/s | **344.6 MB/s** |

(같은 조건에서 `scp` 는 각각 8.8 MB/s, 202.5 MB/s)

느렸던 이유는 두 가지였습니다.

1. **요청을 하나씩 보내고 응답을 기다렸습니다.** 32KB마다 왕복을 기다리면 속도 상한이 `32KB / RTT` 로 고정됩니다
   (RTT 40ms → 0.8 MB/s). 이제 요청 64개를 동시에 띄우고 도착하는 대로 처리합니다.
2. **SSH 채널 수신 윈도가 128KB였습니다.** swift-nio-ssh는 자식 채널의 수신 윈도를 `maximumPacketSize`
   (기본 128KB)에서 가져오므로, 아무리 많이 요청해도 서버는 왕복당 128KB만 보낼 수 있었습니다.
   OpenSSH와 같은 2MB로 올렸습니다. 이것이 다운로드가 업로드보다 훨씬 느렸던 원인입니다.

진행률 콜백도 메인 액터로 넘기기 전에 100ms 단위로 합칩니다 — 초당 수천 번의 액터 홉이 전송보다
비쌌기 때문입니다.

## 보안 관련 처리

- **셸에 넘기는 경로는 항상 인용** — 터미널에 보내는 `cd`는 경로를 작은따옴표로 감싸고 안의 `'`를
  `'\''`로 닫았다 여는 POSIX 방식으로 이스케이프합니다. 서버가 파일 이름을 `$(...)`나 `;rm -rf ~`로
  지어도 명령이 되지 않습니다.
- **원격이 준 이름은 한 조각으로만 취급** — 디렉터리 목록의 이름은 서버가 마음대로 정할 수 있는 값입니다.
  `/`, `.`, `..`, 널 바이트가 든 이름은 프로토콜상 정상적인 항목이 아니므로 목록에서 걸러냅니다.
- **내려받는 경로는 대상 폴더를 벗어날 수 없음** — 폴더를 통째로 받을 때도 각 경로가 사용자가 고른 폴더
  안에 있는지 검사하고, 벗어나는 항목은 전송 큐에 실패로 남깁니다(조용히 넘기지 않습니다). 원격 파일을
  편집기로 열 때 만드는 임시 사본도 같은 검사를 거칩니다.
- **이름 입력란은 경로가 아님** — 새 폴더·이름 바꾸기에 `/`가 들어간 값을 넣으면 거부합니다.
- 호스트 키 검증과 비밀번호 비저장 정책은 위 기능 목록을 참고하세요.

## 알려진 제약

- **RSA 키**: 백엔드(Citadel)가 레거시 `ssh-rsa` 서명만 지원합니다. OpenSSH 8.8 이상 서버는 이를 기본적으로
  거부하므로 **ED25519 키를 권장**합니다. RSA를 꼭 써야 한다면 서버 `sshd_config` 에
  `PubkeyAcceptedAlgorithms +ssh-rsa` 가 필요합니다. 앱은 이 상황을 감지해 해당 안내를 오류 메시지에 표시합니다.
- **암호화된 개인 키**: 키 암호는 ED25519/RSA OpenSSH 키에 대해서만 처리됩니다. ECDSA 키는 미지원입니다.
- 로컬 창끼리의 복사(로컬→로컬)는 지원하지 않습니다.
- **언어 전환의 범위**: 앱이 직접 그리는 모든 화면은 즉시 바뀌지만, macOS가 대신 넣어 주는 메뉴 항목
  (`종료`·`가리기`·`서비스`, 편집/윈도우 메뉴)은 시스템 언어를 따릅니다. 이건 `.lproj` 번들이 아니라
  앱 안의 문자열 표로 전환하기 때문입니다 — 그 대신 다시 실행하지 않고도 바로 바뀝니다.
- 비밀번호를 저장하지 않으므로 **연결할 때마다 입력**해야 합니다. 세션 중 캐시도 하지 않습니다.
- **원격 셸**: 서버가 `ForceCommand internal-sftp` 등으로 셸을 막아 두었다면 터미널이 열리지 않습니다.
  `터미널 → 창`은 셸이 위치를 알리지 않는 환경(제목도 OSC 7도 없는 최소 프롬프트)에서는 쓸 수 없고,
  그 이유를 안내합니다.
  명령 종료는 SSH가 알려주지 않으므로, 출력이 0.7초간 멎으면 끝난 것으로 보고 원격 목록을 새로 고칩니다.
- 전송 큐는 파일을 **한 번에 하나씩** 처리합니다. 파일 하나의 속도는 위와 같지만, 아주 작은 파일이 많은
  폴더는 파일마다 열기/닫기 왕복이 필요해 여전히 느립니다.

## 구조

```
Sources/SFTPManager/
  main.swift              진입점 — GUI / --selftest / --snapshot 분기
  SFTPManagerApp.swift    App 정의, 메뉴 명령, AppDelegate
  SelfTest.swift          헤드리스 검증
  Snapshot.swift          오프스크린 UI 렌더링
  Model/
    FileItem.swift        양쪽 창이 공유하는 파일 항목 + 경로/용량 유틸
    FileGlyph.swift       확장자·이름·폴더별 아이콘과 색 표
    Localization.swift    한국어/영어 문자열 표와 언어 전환
    Connection.swift      서버 프로필 + 디스크 저장 (구 스키마 마이그레이션 포함)
  Core/
    SFTPSession.swift     Citadel 기반 SSH/SFTP 액터 (목록·전송·재귀 삭제·트리 탐색)
    LocalFileSystem.swift 로컬 파일 조작
    Keychain.swift        구버전이 저장한 자격 증명 정리 (더 이상 저장하지 않음)
    OpenSSHKeyInspector.swift  개인 키가 암호화되어 있는지 헤더로 판별
    KnownHosts.swift      known_hosts 파싱·매칭(해시 항목 포함)·지문 계산·기록
    HostKeyValidator.swift  키 교환 단계의 호스트 키 검증과 거부 사유
    RemoteEdit.swift      편집 중인 원격 파일과 저장 감지 규칙
    ShellSession.swift    같은 연결 위의 PTY 셸 (SwiftTerm 연결, 유휴 감지 새로 고침)
    AppModel+Editing.swift  내려받기·감시·자동 재업로드
    PaneState.swift       한쪽 창의 상태 (경로·목록·선택·정렬·히스토리)
    AppModel.swift        앱 전역 상태, 연결 관리, 파일 조작
    AppModel+Transfers.swift  전송 큐 확장·진행률·충돌 정책
    Transfer.swift        전송 항목 모델
  Views/                  SwiftUI 화면
    HelpBook.swift        도움말 내용 (두 언어, 데이터로만)
    HelpView.swift        도움말 창
    AboutView.swift       만든이·버전·사용 기술
Scripts/
  make_app.sh             .app 번들 조립 + ad-hoc 서명
  check_l10n.sh           하드코딩된 한글 문자열 검사
  make_icon.sh            아이콘 생성
  DrawIcon.swift          CoreGraphics 아이콘 드로잉
```

## 라이선스

MIT — [LICENSE](LICENSE) 참조.

## 만든이

jackson &lt;wawds123@gmail.com&gt;

앱 안에서는 `SFTP Manager › SFTP Manager 정보` 또는 `설정 › 정보` 에서 볼 수 있습니다.
