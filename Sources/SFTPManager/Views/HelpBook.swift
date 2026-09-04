import Foundation

/// The contents of the Help window, kept as data so the view stays a renderer
/// and `--selftest` can check that no entry is blank in either language.
enum HelpBook {

    struct Entry: Identifiable {
        let id = UUID()
        /// A short lead-in, shown in bold. Nil for a plain paragraph.
        var term: String?
        var detail: String
        /// Rendered as a key-cap chip on the right, e.g. "⌘R".
        var shortcut: String?

        init(_ term: String? = nil, _ detail: String, shortcut: String? = nil) {
            self.term = term
            self.detail = detail
            self.shortcut = shortcut
        }
    }

    struct Topic: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let entries: [Entry]
    }

    static var topics: [Topic] {
        [gettingStarted, browsing, transferring, editing, terminal, shortcuts, security]
    }

    // MARK: - Getting started

    private static var gettingStarted: Topic {
        Topic(
            id: "start",
            symbol: "flag",
            title: t("시작하기", "Getting Started"),
            entries: [
                Entry(t("서버 추가", "Add a server"),
                      t("왼쪽 목록 아래의 + 버튼을 누르고 호스트·사용자·인증 방식을 채웁니다. ‘이름’은 목록에 표시할 별칭일 뿐이라 비워도 됩니다.",
                        "Click + under the list on the left and fill in the host, user, and authentication method. “Name” is just a label for the list and can be left empty.")),
                Entry(t("연결", "Connect"),
                      t("서버를 두 번 클릭하거나, 골라 두고 [연결]을 누릅니다. 비밀번호나 키 암호는 이때 물어봅니다.",
                        "Double-click a server, or select it and press Connect. You're asked for the password or passphrase at that moment.")),
                Entry(t("호스트 키 확인", "Check the host key"),
                      t("처음 연결하는 서버는 지문을 보여주는 창이 뜹니다. 서버 관리자가 알려준 값과 같은지 확인한 뒤 신뢰하세요. 이 시점까지 비밀번호는 아직 서버로 가지 않습니다.",
                        "The first connection to a server shows its fingerprint. Check it against what your administrator gave you before trusting it. No password has been sent to the server at this point.")),
                Entry(t("시작 폴더", "Start folders"),
                      t("서버 편집 창에서 원격·로컬 시작 폴더를 정해두면 연결하자마자 그 폴더가 열립니다. 비우면 원격은 홈 디렉터리, 로컬은 지금 보던 폴더를 씁니다.",
                        "Set a remote and local start folder in the server editor and they open as soon as you connect. Left empty, the remote pane uses your home directory and the local pane stays where it was.")),
            ]
        )
    }

    // MARK: - Browsing

    private static var browsing: Topic {
        Topic(
            id: "browse",
            symbol: "folder",
            title: t("파일 탐색", "Browsing"),
            entries: [
                Entry(nil,
                      t("왼쪽 창은 이 Mac, 오른쪽 창은 연결한 서버입니다.",
                        "The left pane is this Mac; the right pane is the server you connected to.")),
                Entry(t("경로 입력", "Type a path"),
                      t("주소 칸에 경로를 직접 쓰고 Return을 누르면 그 폴더로 갑니다. 없는 경로면 알려주고 원래 자리에 머무릅니다.",
                        "Type a path into the address field and press Return to jump there. If it doesn't exist you're told, and the pane stays where it was.")),
                Entry(t("필터", "Filter"),
                      t("필터 칸은 지금 보고 있는 폴더 안에서만 이름을 걸러냅니다. 하위 폴더까지 뒤지지는 않습니다.",
                        "The filter field narrows names inside the folder you're looking at. It does not search subfolders.")),
                Entry(t("정렬", "Sorting"),
                      t("열 머리글을 누르면 그 기준으로 정렬하고, 다시 누르면 방향이 뒤집힙니다. 폴더는 어떤 기준에서도 파일보다 위에 옵니다.",
                        "Click a column header to sort by it; click again to reverse. Folders stay above files whatever the sort.")),
                Entry(t("새로 고침", "Refresh"),
                      t("⌘R은 마지막으로 클릭한 창 하나만 새로 고칩니다. 어느 창인지는 테두리로 표시됩니다. 양쪽을 한꺼번에 하려면 ⇧⌘R입니다.",
                        "⌘R refreshes only the pane you last clicked — the highlighted border shows which. ⇧⌘R does both."),
                      shortcut: "⌘R"),
                Entry(t("오른쪽 클릭", "Right-click"),
                      t("빈 곳과 항목 위에서 각각 다른 메뉴가 나옵니다. 대부분의 동작이 여기 모여 있습니다.",
                        "Empty space and items have different context menus, and most actions live there.")),
            ]
        )
    }

    // MARK: - Transferring

    private static var transferring: Topic {
        Topic(
            id: "transfer",
            symbol: "arrow.up.arrow.down",
            title: t("전송", "Transferring"),
            entries: [
                Entry(t("보내기", "Send"),
                      t("파일을 고르고 각 창 위의 [업로드]·[다운로드] 버튼을 누르거나, 반대편 창으로 끌어다 놓습니다. 폴더를 통째로 옮기면 안쪽 내용까지 따라갑니다.",
                        "Select files and press Upload or Download above the pane, or drag them to the other side. Dropping a folder brings everything inside it."),
                      shortcut: "⌘→ / ⌘←"),
                Entry(t("진행 상황", "Progress"),
                      t("아래 [전송] 탭에 진행률과 속도가 나옵니다. 개별 항목은 취소하거나 실패한 뒤 다시 시도할 수 있습니다.",
                        "The Transfers tab at the bottom shows progress and speed. Individual items can be cancelled, or retried after they fail."),
                      shortcut: "⌥⌘T"),
                Entry(t("이름이 겹칠 때", "When a name clashes"),
                      t("같은 이름이 이미 있으면 양쪽의 크기·수정일을 나란히 보여주는 창이 뜹니다. 덮어쓰기 / 이름 바꿔 저장 / 건너뛰기 중에 고르고, 남은 항목에도 같은 선택을 적용할 수 있습니다.",
                        "If the name already exists you get a dialog comparing both sizes and dates. Choose Overwrite, Keep Both, or Skip — and optionally apply the same answer to the rest.")),
                Entry(t("매번 묻지 않기", "Stop being asked"),
                      t("설정 > 전송에서 기본 동작을 정해두면 확인 창 없이 그대로 처리합니다.",
                        "Pick a default in Settings ▸ Transfers and it happens without a dialog.")),
                Entry(t("더블클릭", "Double-click"),
                      t("로컬 파일을 더블클릭했을 때 업로드할지 기본 앱으로 열지는 설정에서 고릅니다. 원격 파일은 언제나 내려받습니다.",
                        "Whether double-clicking a local file uploads it or opens it in your default app is a setting. A remote file always downloads.")),
            ]
        )
    }

    // MARK: - Remote editing

    private static var editing: Topic {
        Topic(
            id: "edit",
            symbol: "square.and.pencil",
            title: t("원격 파일 편집", "Editing Remote Files"),
            entries: [
                Entry(nil,
                      t("서버의 파일을 내려받아 다시 올리는 과정을 손으로 하지 않아도 됩니다.",
                        "You don't have to download a file, edit it, and upload it again by hand.")),
                Entry(t("여는 법", "How to open"),
                      t("원격 파일을 오른쪽 클릭하고 [편집기로 열기]를 고릅니다. 임시 사본을 내려받아 기본 편집기로 엽니다.",
                        "Right-click a remote file and choose Open in Editor. A scratch copy is downloaded and handed to your default editor.")),
                Entry(t("자동 업로드", "Automatic upload"),
                      t("편집기가 저장할 때마다 바뀐 내용이 서버로 다시 올라갑니다. 저장만 하면 되고 따로 누를 것은 없습니다.",
                        "Every time your editor saves, the change goes back to the server. Saving is all you do.")),
                Entry(t("편집 중 목록", "The editing list"),
                      t("툴바의 [편집 중] 항목에서 지금 열려 있는 파일과 업로드 횟수를 보고, 지금 올리거나 편집을 끝낼 수 있습니다. 편집을 끝내면 임시 사본은 지워집니다.",
                        "The Editing item in the toolbar lists what's open and how many times it uploaded, and lets you upload now or stop. Stopping deletes the scratch copy.")),
                Entry(t("주기", "Interval"),
                      t("저장이 멎고 얼마나 지나야 올릴지는 설정 > 고급에서 바꿉니다.",
                        "How long the file must stop changing before it uploads is in Settings ▸ Advanced.")),
            ]
        )
    }

    // MARK: - Terminal

    private static var terminal: Topic {
        Topic(
            id: "terminal",
            symbol: "terminal",
            title: t("터미널", "Terminal"),
            entries: [
                Entry(t("여는 법", "How to open"),
                      t("아래 [터미널] 탭을 누르거나 툴바의 터미널 아이콘을 누릅니다. 이미 인증된 SSH 연결 위에 채널을 하나 더 여는 것이라 비밀번호를 다시 묻지 않고, 두 번째 접속으로도 잡히지 않습니다.",
                        "Click the Terminal tab at the bottom or the toolbar icon. It opens a second channel on the SSH connection you already authenticated, so there's no second password prompt and no second login on the server."),
                      shortcut: "⌥⌘S"),
                Entry(t("터미널을 창 위치로", "Move Terminal to Pane"),
                      t("오른쪽 창이 보고 있는 폴더로 셸을 cd 합니다. 쓰다 만 입력이 있으면 지우고 보내므로 명령이 붙어서 실행되지 않습니다 — 지워진 줄은 Ctrl-Y로 되살릴 수 있습니다.",
                        "cd's the shell to the folder the remote pane is showing. A half-typed line is cleared first so nothing gets concatenated — Ctrl-Y brings it back.")),
                Entry(t("창을 터미널 위치로", "Move Pane to Terminal"),
                      t("반대로 오른쪽 창을 셸이 있는 폴더로 옮깁니다. 셸이 창 제목이나 OSC 7으로 자기 위치를 알릴 때만 됩니다. 알아내려고 사용자의 셸에 명령을 대신 입력하지는 않습니다.",
                        "Moves the remote pane to where the shell is. It works only when the shell announces its location through its window title or OSC 7 — no command is ever typed into your shell to find out.")),
                Entry(t("자동 새로 고침", "Automatic refresh"),
                      t("명령이 끝나 화면이 잠시 조용해지면 원격 목록이 저절로 새로 고쳐집니다.",
                        "When a command finishes and the screen falls quiet, the remote listing reloads on its own.")),
                Entry(t("끝내기", "Ending it"),
                      t("exit를 입력하거나 [세션 닫기]를 누릅니다. 끝난 화면은 그대로 남아 있고 [다시 열기]로 새 셸을 엽니다. 탭을 오간다고 셸이 다시 열리지는 않습니다.",
                        "Type exit or press Close Session. The finished screen stays put, and Reopen starts a new shell. Switching tabs never opens one behind your back.")),
                Entry(t("전체 화면 프로그램", "Full-screen programs"),
                      t("vim이나 top처럼 화면 전체를 쓰는 프로그램이 떠 있는 동안에는 버튼이 명령을 보내지 않고 알려만 줍니다. 그 프로그램에 키가 들어가면 안 되기 때문입니다.",
                        "While a program like vim or top owns the screen, the buttons refuse to send anything and say so — those keystrokes would go to that program, not a shell.")),
            ]
        )
    }

    // MARK: - Shortcuts

    private static var shortcuts: Topic {
        Topic(
            id: "keys",
            symbol: "keyboard",
            title: t("단축키", "Shortcuts"),
            entries: [
                Entry(nil, t("새 연결", "New connection"), shortcut: "⌘N"),
                Entry(nil, t("설정", "Settings"), shortcut: "⌘,"),
                Entry(nil, t("도움말 (이 창)", "Help (this window)"), shortcut: "⌘?"),
                Entry(nil, t("클릭한 창 새로 고침", "Refresh the clicked pane"), shortcut: "⌘R"),
                Entry(nil, t("양쪽 새로 고침", "Refresh both panes"), shortcut: "⇧⌘R"),
                Entry(nil, t("로컬 상위 폴더", "Local parent folder"), shortcut: "⌘↑"),
                Entry(nil, t("원격 상위 폴더", "Remote parent folder"), shortcut: "⇧⌘↑"),
                Entry(nil, t("업로드", "Upload"), shortcut: "⌘→"),
                Entry(nil, t("다운로드", "Download"), shortcut: "⌘←"),
                Entry(nil, t("전송 목록 열기/닫기", "Show or hide transfers"), shortcut: "⌥⌘T"),
                Entry(nil, t("터미널 열기/닫기", "Show or hide the terminal"), shortcut: "⌥⌘S"),
            ]
        )
    }

    // MARK: - Security

    private static var security: Topic {
        Topic(
            id: "security",
            symbol: "lock.shield",
            title: t("보안", "Security"),
            entries: [
                Entry(t("비밀번호", "Passwords"),
                      t("비밀번호와 키 암호는 키체인을 포함해 어디에도 저장하지 않습니다. 연결할 때마다 입력받고, 연결이 끝나면 메모리에서도 사라집니다.",
                        "Passwords and passphrases are never stored anywhere, Keychain included. You enter them on each connection and they leave memory when it ends.")),
                Entry(t("호스트 키", "Host keys"),
                      t("서버의 키를 ~/.ssh/known_hosts로 검사합니다. 처음 보는 키는 지문을 보여주고, 이전과 달라졌으면 경고합니다. 이 확인은 인증보다 먼저 이뤄지므로, 거절하면 비밀번호는 서버로 가지 않습니다.",
                        "Server keys are checked against ~/.ssh/known_hosts. A new key shows its fingerprint; a changed one raises a warning. This happens before authentication, so declining means your password never reaches the server.")),
                Entry(t("서버가 보낸 이름", "Names from the server"),
                      t("목록에 오는 파일 이름은 그대로 믿지 않습니다. `/`나 `..`가 든 이름은 목록에서 빼고, 내려받을 경로가 고른 폴더를 벗어나면 그 항목만 실패로 표시합니다.",
                        "Filenames in a listing are not taken on trust. Names containing `/` or `..` are dropped, and if a download path would land outside the folder you chose, that one item is marked failed.")),
                Entry(t("터미널", "The terminal"),
                      t("앱이 셸로 보내는 경로는 항상 작은따옴표로 감쌉니다. 이름에 공백이나 `$(…)`가 있어도 명령으로 해석되지 않습니다.",
                        "Any path this app sends to the shell is single-quoted, so a name containing a space or `$(…)` is never interpreted as a command.")),
            ]
        )
    }
}
