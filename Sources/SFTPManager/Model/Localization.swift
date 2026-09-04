import Foundation

/// The languages the interface is written in.
///
/// Two hand-maintained columns rather than `.lproj` bundles: this app is built
/// by SwiftPM into a hand-assembled bundle, and `NSLocalizedString` would need a
/// relaunch to change language. `t(_:_:)` reads a variable, so the picker in
/// Settings takes effect on the next frame.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    /// Named in its own language, the way system language pickers do it.
    var label: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// What a first launch picks: Korean only for a Korean system.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ko") ? .korean : .english
    }
}

/// The language every `t(_:_:)` lookup reads.
///
/// Written from the Settings window, read from anywhere — error descriptions are
/// built on background tasks — so the store is behind a lock rather than pinned
/// to the main actor.
enum Lang {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: AppLanguage = .korean

    static var current: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Picks the Korean or the English wording. Both are required at the call site,
/// so a string can never be half-translated.
func t(_ korean: String, _ english: String) -> String {
    Lang.current == .korean ? korean : english
}

/// Every fixed string the interface shows.
///
/// Grouped by where it appears. Anything with a value in it is a function, so
/// the two languages can put the number in different places.
enum L {

    // MARK: - Shared words

    static var ok: String { t("확인", "OK") }
    static var cancel: String { t("취소", "Cancel") }
    static var save: String { t("저장", "Save") }
    static var delete: String { t("삭제", "Delete") }
    static var edit: String { t("편집…", "Edit…") }
    static var choose: String { t("선택…", "Choose…") }
    static var connect: String { t("연결", "Connect") }
    static var disconnect: String { t("연결 해제", "Disconnect") }
    static var open: String { t("열기", "Open") }
    static var reveal: String { t("보기", "Reveal") }
    static var error: String { t("오류", "Error") }
    static var unknown: String { t("알 수 없음", "Unknown") }
    static var upload: String { t("업로드", "Upload") }
    static var download: String { t("다운로드", "Download") }
    static var terminal: String { t("터미널", "Terminal") }
    static var transfers: String { t("전송", "Transfers") }
    static var local: String { t("로컬", "Local") }
    static var remote: String { t("원격", "Remote") }
    static var password: String { t("비밀번호", "Password") }
    static var privateKey: String { t("개인 키", "Private key") }
    static var newFolder: String { t("새 폴더…", "New Folder…") }
    static var refresh: String { t("새로 고침", "Refresh") }
    static var goUp: String { t("상위 폴더", "Parent Folder") }
    static var home: String { t("홈", "Home") }
    static var showHidden: String { t("숨김 파일 보기", "Show Hidden Files") }
    static var syncOppositePane: String {
        t("반대편 창을 같은 이름 폴더로", "Match Other Pane to This Folder")
    }
    static var revealInFinder: String { t("Finder에서 보기", "Show in Finder") }
    static var openInFinder: String { t("Finder에서 열기", "Open in Finder") }
    static var openInDefaultApp: String { t("기본 앱으로 열기", "Open with Default App") }
    static var copyPath: String { t("경로 복사", "Copy Path") }

    // MARK: - Panes and columns

    static var columnName: String { t("이름", "Name") }
    static var columnSize: String { t("크기", "Size") }
    static var columnModified: String { t("수정일", "Modified") }
    static var columnKind: String { t("종류", "Kind") }
    static var columnOwner: String { t("소유자", "Owner") }
    static var columnPermissions: String { t("권한", "Permissions") }
    static func sortByColumn(_ title: String) -> String {
        t("\(title)(으)로 정렬", "Sort by \(title.lowercased())")
    }

    static func folderCount(_ n: Int) -> String { t("폴더 \(n)", "\(n) folders") }
    static func fileCount(_ n: Int) -> String { t("파일 \(n)", "\(n) files") }
    static func selectionCount(_ n: Int, _ size: String) -> String {
        t("선택 \(n) (\(size))", "\(n) selected (\(size))")
    }

    static var path: String { t("경로", "Path") }
    static var filterInFolder: String { t("이 폴더에서 필터", "Filter this folder") }
    static var back: String { t("뒤로", "Back") }
    static var forward: String { t("앞으로", "Forward") }
    static var selectAll: String { t("전체 선택", "Select All") }
    static var deselectAll: String { t("선택 해제", "Deselect All") }
    static var uploadSelection: String { t("선택 항목 업로드", "Upload Selection") }
    static var downloadSelection: String { t("선택 항목 다운로드", "Download Selection") }
    static var openTerminalHere: String { t("여기서 터미널 열기", "Open Terminal Here") }
    static var copyFolderPath: String { t("이 폴더 경로 복사", "Copy Folder Path") }
    static var renameEllipsis: String { t("이름 바꾸기…", "Rename…") }
    static var openInEditor: String { t("편집기로 열기", "Open in Editor") }
    static var openInEditorHelp: String {
        t("내려받아 기본 편집기로 열고, 저장할 때마다 자동으로 다시 올립니다",
          "Downloads it, opens your default editor, and re-uploads on every save")
    }
    static var uploadHelp: String {
        t("선택한 항목을 업로드합니다 (⌘→)", "Upload the selected items (⌘→)")
    }
    static var downloadHelp: String {
        t("선택한 항목을 다운로드합니다 (⌘←)", "Download the selected items (⌘←)")
    }
    static var localFileDoubleClick: String { t("파일 더블클릭", "Double-click a file") }

    static var notConnected: String { t("연결 안 됨", "Not connected") }
    static var notConnectedDetail: String {
        t("왼쪽 목록에서 서버를 선택하고 연결하세요.", "Pick a server on the left and connect.")
    }
    static var folderUnavailable: String { t("폴더를 열 수 없음", "Can't open folder") }
    static var emptyFolder: String { t("빈 폴더", "Empty folder") }
    static var emptyFolderDetail: String {
        t("이 폴더에는 표시할 항목이 없습니다.", "There is nothing to show in this folder.")
    }
    static var noMatches: String { t("일치하는 항목 없음", "No matches") }
    static var noMatchesDetail: String {
        t("필터를 지우고 다시 시도하세요.", "Clear the filter and try again.")
    }

    // MARK: - Sidebar

    static var servers: String { t("서버", "Servers") }
    static var noServers: String { t("서버 없음", "No servers") }
    static var noServersDetail: String {
        t("아래 + 버튼으로 SFTP 서버를 추가하세요.", "Add an SFTP server with the + button below.")
    }
    static var addServer: String { t("서버 추가", "Add server") }
    static var editServer: String { t("서버 편집", "Edit server") }
    static var deleteServer: String { t("서버 삭제", "Delete server") }

    // MARK: - Connection editor

    static var newServer: String { t("새 서버", "New Server") }
    static var editServerTitle: String { t("서버 편집", "Edit Server") }
    static var newConnection: String { t("새 연결", "New connection") }
    static var notConfigured: String { t("설정되지 않음", "Not configured") }
    static var fieldName: String { t("이름", "Name") }
    static var fieldNamePrompt: String { t("예: 운영 서버", "e.g. Production") }
    static var fieldHost: String { t("호스트", "Host") }
    static var fieldPort: String { t("포트", "Port") }
    static var fieldUser: String { t("사용자", "User") }
    static var sectionAuth: String { t("인증", "Authentication") }
    static var authMethod: String { t("방식", "Method") }
    static var privateKeyPath: String { t("개인 키 경로", "Private key path") }
    static var sectionStartPaths: String { t("시작 위치 (선택)", "Start folders (optional)") }
    static var remotePath: String { t("원격 경로", "Remote path") }
    static var remotePathPrompt: String { t("비우면 홈 디렉터리", "Empty means the home directory") }
    static var localPath: String { t("로컬 경로", "Local path") }
    static var localPathPrompt: String { t("비우면 현재 위치 유지", "Empty keeps the current folder") }
    static var passwordNotStoredNote: String {
        t("비밀번호는 저장하지 않습니다. 연결할 때마다 입력합니다.",
          "The password is never stored. You'll be asked for it on every connection.")
    }
    static var passphraseNotStoredNote: String {
        t("키 암호는 저장하지 않습니다. 암호로 보호된 키일 때만 연결 시 물어봅니다.",
          "The passphrase is never stored. You're only asked when the key is protected.")
    }

    // MARK: - Connecting

    static func passwordPromptTitle(_ server: String) -> String {
        t("\(server) 비밀번호", "Password for \(server)")
    }
    static var passwordPromptMessage: String {
        t("비밀번호는 저장되지 않으며 연결할 때마다 입력합니다.",
          "The password is not stored; you enter it on every connection.")
    }
    static var passphrasePromptTitle: String { t("개인 키 암호", "Private Key Passphrase") }
    static var passphrasePromptMessage: String {
        t("키 암호는 저장되지 않습니다.", "The passphrase is not stored.")
    }
    static var passphrase: String { t("키 암호", "Passphrase") }
    static func connecting(_ name: String) -> String { t("\(name) 연결 중…", "Connecting to \(name)…") }
    static var connectionFailed: String { t("연결 실패", "Connection failed") }
    static func connectFailedMessage(_ name: String, _ reason: String) -> String {
        t("\(name)에 연결하지 못했습니다.\n\n\(reason)",
          "Couldn't connect to \(name).\n\n\(reason)")
    }
    static func knownHostsWriteFailed(_ reason: String) -> String {
        t("known_hosts에 저장하지 못했습니다.\n\n\(reason)",
          "Couldn't write to known_hosts.\n\n\(reason)")
    }
    static var connectFirst: String {
        t("먼저 서버에 연결해 주세요.", "Connect to a server first.")
    }

    // MARK: - Host key

    static var hostKeyUnknownTitle: String {
        t("처음 접속하는 서버입니다", "First time connecting to this server")
    }
    static var hostKeyChangedTitle: String {
        t("호스트 키가 바뀌었습니다", "The host key has changed")
    }
    static var hostKeyRevokedTitle: String {
        t("취소된 호스트 키입니다", "This host key was revoked")
    }
    static func hostKeyUnknownMessage(_ fingerprint: String) -> String {
        t("처음 접속하는 서버입니다. 호스트 키를 확인해 주세요.\n\n\(fingerprint)",
          "This is the first connection to this server. Please check its host key.\n\n\(fingerprint)")
    }
    static func hostKeyChangedMessage(_ fingerprint: String) -> String {
        t("서버의 호스트 키가 이전과 다릅니다. 중간자 공격일 수 있습니다.\n\n새 키: \(fingerprint)",
          "The server's host key differs from the one on file. This may be a man-in-the-middle attack.\n\nNew key: \(fingerprint)")
    }
    static var hostKeyRevokedMessage: String {
        t("이 호스트 키는 known_hosts에서 취소(@revoked)된 키입니다. 접속하지 않는 것이 좋습니다.",
          "This host key is marked @revoked in known_hosts. You should not connect.")
    }
    static var hostKeyUnknownDetail: String {
        t("이 서버의 신원을 확인할 수 없습니다. 아래 지문이 서버 관리자가 알려준 값과 같은지 확인하세요.",
          "This server's identity can't be verified. Check that the fingerprint below matches the one your administrator gave you.")
    }
    static var hostKeyChangedDetail: String {
        t("이전에 신뢰한 키와 다른 키를 제시했습니다. 서버를 다시 설치했다면 정상일 수 있지만, **중간자 공격일 수도 있습니다.** 확실하지 않다면 연결하지 마세요.",
          "The server offered a different key from the one you trusted. That's normal after a reinstall, but it **may also be a man-in-the-middle attack.** Don't connect unless you're sure.")
    }
    static var hostKeyRevokedDetail: String {
        t("이 키는 known_hosts에 `@revoked`로 표시되어 있습니다. 신뢰해서는 안 됩니다.",
          "This key is marked `@revoked` in known_hosts. It must not be trusted.")
    }
    static var fingerprint: String { t("지문", "Fingerprint") }
    static var newFingerprint: String { t("새 지문", "New fingerprint") }
    static var previouslyTrustedFingerprint: String {
        t("이전에 신뢰한 지문", "Previously trusted fingerprint")
    }
    static func keyAlgorithm(_ algorithm: String) -> String {
        t("키 종류: \(algorithm)", "Key type: \(algorithm)")
    }
    static var nothingSentYet: String {
        t("아직 비밀번호나 키는 서버로 전송되지 않았습니다. 호스트 키 확인은 인증보다 먼저 이뤄집니다.",
          "No password or key has been sent yet — the host key is checked before authentication.")
    }
    static var trustAndConnect: String { t("신뢰하고 연결", "Trust and Connect") }
    static var replaceAndTrust: String { t("기존 키를 지우고 신뢰", "Replace Key and Trust") }

    // MARK: - Errors

    static var errNoPassword: String {
        t("비밀번호가 입력되지 않았습니다.", "No password was entered.")
    }
    static func errUnsupportedKey(_ type: String) -> String {
        t("지원하지 않는 키 형식입니다: \(type). RSA 또는 ED25519 OpenSSH 키를 사용해 주세요.",
          "Unsupported key format: \(type). Use an RSA or ED25519 OpenSSH key.")
    }
    static func errKeyUnreadable(_ path: String) -> String {
        t("개인 키를 읽을 수 없습니다: \(path)", "Can't read the private key: \(path)")
    }
    static func errLocalFileUnavailable(_ path: String) -> String {
        t("로컬 파일을 열 수 없습니다: \(path)", "Can't open the local file: \(path)")
    }
    static var errNotConnected: String {
        t("SFTP 세션이 연결되어 있지 않습니다.", "The SFTP session is not connected.")
    }
    static var errAuthFailed: String {
        t("인증에 실패했습니다. 사용자 이름과 비밀번호/키를 확인해 주세요.",
          "Authentication failed. Check the username and your password or key.")
    }
    static var errRSAHint: String {
        t("RSA 키를 사용 중입니다. 최신 OpenSSH 서버는 기본적으로 ssh-rsa 서명을 거부하므로 ED25519 키(ssh-keygen -t ed25519)를 사용하거나, 서버 sshd_config에 `PubkeyAcceptedAlgorithms +ssh-rsa`를 추가해야 합니다.",
          "You're using an RSA key. Modern OpenSSH servers reject ssh-rsa signatures by default, so use an ED25519 key (ssh-keygen -t ed25519) or add `PubkeyAcceptedAlgorithms +ssh-rsa` to the server's sshd_config.")
    }

    // MARK: - Folder, rename, delete

    static func newFolderTitle(_ side: String) -> String {
        t("\(side)에 새 폴더 만들기", "New folder in \(side.lowercased())")
    }
    static var folderName: String { t("폴더 이름", "Folder name") }
    static var untitledFolder: String { t("새 폴더", "untitled folder") }
    static var create: String { t("만들기", "Create") }
    static var slashNotAllowedInFolder: String {
        t("폴더 이름에는 /를 쓸 수 없습니다.", "A folder name can't contain /.")
    }
    static func createFolderFailed(_ reason: String) -> String {
        t("폴더를 만들지 못했습니다.\n\n\(reason)", "Couldn't create the folder.\n\n\(reason)")
    }
    static var renameTitle: String { t("이름 바꾸기", "Rename") }
    static var newName: String { t("새 이름", "New name") }
    static var rename: String { t("바꾸기", "Rename") }
    static var slashNotAllowedInName: String {
        t("이름에는 /를 쓸 수 없습니다. 옮기려면 끌어다 놓으세요.",
          "A name can't contain /. Drag the item if you want to move it.")
    }
    static func renameFailed(_ reason: String) -> String {
        t("이름을 바꾸지 못했습니다.\n\n\(reason)", "Couldn't rename it.\n\n\(reason)")
    }
    static func deleteTitle(_ n: Int) -> String {
        t("\(n)개 항목을 삭제할까요?", n == 1 ? "Delete this item?" : "Delete \(n) items?")
    }
    static func andMore(_ n: Int) -> String { t(" 외 \(n)개", " and \(n) more") }
    static func deleteMessage(_ names: String) -> String {
        t("\(names)\n\n이 작업은 되돌릴 수 없습니다.", "\(names)\n\nThis can't be undone.")
    }
    static func deleteFailed(_ reason: String) -> String {
        t("삭제하지 못했습니다.\n\n\(reason)", "Couldn't delete it.\n\n\(reason)")
    }
    static func pathDoesNotExist(_ path: String) -> String {
        t("아직 만들어지지 않은 경로입니다.\n\n\(path)", "That path doesn't exist yet.\n\n\(path)")
    }
    static func readFolderFailed(_ name: String, _ reason: String) -> String {
        t("폴더를 읽지 못했습니다: \(name)\n\n\(reason)",
          "Couldn't read the folder: \(name)\n\n\(reason)")
    }

    // MARK: - Transfers

    static var queued: String { t("대기 중", "Queued") }
    static func completed(_ size: String) -> String { t("완료 · \(size)", "Done · \(size)") }
    static var skipped: String { t("건너뜀", "Skipped") }
    static var cancelled: String { t("취소됨", "Cancelled") }
    static var retry: String { t("다시 시도", "Retry") }
    static var cancelAll: String { t("모두 취소", "Cancel All") }
    static var clearFinished: String { t("완료 항목 지우기", "Clear Finished") }
    static func remainingItems(_ n: Int) -> String { t("남은 항목 \(n)", "\(n) remaining") }
    static var emptyQueue: String {
        t("파일을 선택해 업로드/다운로드하거나 두 창 사이로 끌어다 놓으세요.",
          "Select files to upload or download, or drag them between the two panes.")
    }
    static var escapedDestination: String {
        t("이름이 대상 폴더를 벗어나서 건너뜀", "Skipped: the name escapes the destination folder")
    }
    static var transfersHelp: String { t("전송 목록 보기/숨기기", "Show or hide the transfer list") }
    static var terminalHelp: String {
        t("연결된 서버의 셸을 아래에 엽니다", "Opens a shell on the connected server below")
    }
    static var transferList: String { t("전송 목록", "Transfer List") }

    // MARK: - Conflicts

    static var conflictPolicyLabel: String { t("충돌 시", "On conflict") }
    static var conflictPolicyHelp: String {
        t("같은 이름의 파일이 이미 있을 때의 동작", "What to do when a name already exists")
    }
    static var conflictAsk: String { t("물어보기", "Ask") }
    static var conflictOverwrite: String { t("덮어쓰기", "Overwrite") }
    static var conflictRename: String { t("이름 바꿔 저장", "Keep Both") }
    static var conflictSkip: String { t("건너뛰기", "Skip") }
    static var conflictFileHeadline: String {
        t("같은 이름의 파일이 이미 있습니다", "A file with that name already exists")
    }
    static var conflictFolderHeadline: String {
        t("같은 이름의 폴더가 이미 있습니다", "A folder with that name already exists")
    }
    static var conflictIncoming: String { t("보내는 것", "Incoming") }
    static var conflictExisting: String { t("이미 있는 것", "Already there") }
    static func conflictApplyToRest(_ n: Int) -> String {
        t("남은 \(n)개에도 같은 선택 적용", "Apply to the remaining \(n)")
    }
    static func conflictRenameHelp(_ name: String) -> String {
        t("\(name) (으)로 저장합니다", "Saves it as \(name)")
    }
    static var modifiedUnknown: String { t("수정일 알 수 없음", "Modified date unknown") }

    // MARK: - Remote editing

    static var editPreparing: String { t("내려받는 중…", "Downloading…") }
    static var editWatching: String { t("변경 감시 중", "Watching for changes") }
    static var editUploading: String { t("업로드 중…", "Uploading…") }
    static func editingCount(_ n: Int) -> String { t("편집 중 \(n)", "\(n) editing") }
    static var editingHelp: String {
        t("편집 중인 원격 파일 — 저장하면 자동으로 업로드됩니다",
          "Remote files open for editing — saving uploads them automatically")
    }
    static func uploadCount(_ n: Int) -> String { t("저장 후 업로드 \(n)회", "Uploaded \(n) times") }
    static var openInEditorApp: String { t("편집기에서 열기", "Open in Editor") }
    static var uploadNow: String { t("지금 업로드", "Upload Now") }
    static var resumeWatching: String { t("감시 다시 시작", "Resume Watching") }
    static var stopEditing: String { t("편집 종료", "Stop Editing") }
    static var stopAllEditing: String { t("모두 편집 종료", "Stop All Editing") }
    static func editNamePrefix(_ name: String) -> String { t("편집: \(name)", "Editing: \(name)") }
    static var editUploadDisconnected: String {
        t("연결이 끊겨 업로드하지 못했습니다", "Disconnected before the upload finished")
    }
    static func editNameInvalid(_ name: String) -> String {
        t("파일 이름이 올바르지 않아 편집할 수 없습니다: \(name)",
          "That filename can't be edited: \(name)")
    }
    static func editDownloadFailed(_ name: String, _ reason: String) -> String {
        t("\(name)을(를) 편집용으로 내려받지 못했습니다.\n\n\(reason)",
          "Couldn't download \(name) for editing.\n\n\(reason)")
    }

    // MARK: - Terminal panel

    static var openTerminalNeedsConnection: String {
        t("터미널을 열려면 먼저 서버에 연결하세요.", "Connect to a server before opening the terminal.")
    }
    static var terminalBusyWithFullScreen: String {
        t("터미널에서 전체 화면 프로그램이 실행 중입니다. 그 프로그램을 끝낸 뒤 다시 시도하세요.",
          "A full-screen program is running in the terminal. Quit it and try again.")
    }
    static var shellOpening: String { t("셸 여는 중…", "Opening shell…") }
    static var shellOpeningDetail: String {
        t("원격 창이 보고 있는 폴더에서 시작합니다.", "It starts in the folder the remote pane is showing.")
    }
    static var shellNeedsConnectionDetail: String {
        t("서버에 연결하면 그 연결 위에서 셸이 열립니다. 비밀번호를 다시 묻지 않습니다.",
          "Connect to a server and the shell opens on that same connection — no second password prompt.")
    }
    static var terminalToPane: String { t("터미널을 창 위치로", "Move Terminal to Pane") }
    static var terminalToPaneHelp: String {
        t("원격 창이 보고 있는 폴더로 터미널을 cd 합니다.",
          "cd the terminal to the folder the remote pane is showing.")
    }
    static var paneToTerminal: String { t("창을 터미널 위치로", "Move Pane to Terminal") }
    static var paneToTerminalHelp: String {
        t("터미널이 있는 폴더로 원격 창을 옮깁니다.", "Move the remote pane to the terminal's folder.")
    }
    static var closeSession: String { t("세션 닫기", "Close Session") }
    static var sessionEnded: String { t("세션 종료됨", "Session ended") }
    static var reopen: String { t("다시 열기", "Reopen") }
    static var clearSession: String { t("정리", "Clear") }
    static var clearSessionHelp: String {
        t("끝난 세션의 내용을 지우고 전송 탭으로 돌아갑니다.",
          "Discards the ended session and returns to the transfer tab.")
    }
    static var collapsePanel: String { t("패널 접기", "Collapse panel") }
    static var shellDisconnectedBanner: String { t("세션 종료", "session ended") }
    static func shellErrorBanner(_ reason: String) -> String {
        t("연결이 끊어졌습니다: \(reason)", "disconnected: \(reason)")
    }
    static var terminalCwdUnknown: String {
        t("""
          터미널이 현재 폴더를 알려주지 않습니다.

          셸이 창 제목이나 OSC 7으로 자기 위치를 알릴 때만 따라갈 수 있습니다. \
          알아내려고 터미널에 명령을 대신 입력하지는 않습니다.
          """,
          """
          The terminal isn't reporting its current folder.

          It can only be followed when the shell announces where it is, through \
          its window title or OSC 7. No command is typed into your shell to find out.
          """)
    }

    // MARK: - Menus

    static var menuNewConnection: String { t("새 연결…", "New Connection…") }
    static var menuGo: String { t("이동", "Go") }
    static var menuLocalParent: String { t("로컬 상위 폴더", "Local Parent Folder") }
    static var menuRemoteParent: String { t("원격 상위 폴더", "Remote Parent Folder") }
    static func menuRefreshActive(_ pane: String) -> String {
        t("새로 고침 (\(pane))", "Refresh (\(pane))")
    }
    static var menuRefreshBoth: String { t("양쪽 새로 고침", "Refresh Both") }
    static var menuView: String { t("보기", "View") }
    static var menuHelp: String { t("SFTP Manager 도움말", "SFTP Manager Help") }
    static var menuAbout: String { t("SFTP Manager 정보", "About SFTP Manager") }
    static var resizeHandleHelp: String {
        t("끌어서 아래 패널 높이 조절 · 두 번 클릭하면 자동 크기",
          "Drag to resize the panel · double-click to fit")
    }

    // MARK: - Settings

    static var settingsGeneral: String { t("일반", "General") }
    static var settingsFileList: String { t("파일 목록", "File Lists") }
    static var settingsAdvanced: String { t("고급", "Advanced") }
    static var settingsAbout: String { t("정보", "About") }

    static var appearance: String { t("모양", "Appearance") }
    static var themeLabel: String { t("테마", "Theme") }
    static var themeSystem: String { t("시스템 설정 따르기", "Match System") }
    static var themeLight: String { t("밝게", "Light") }
    static var themeDark: String { t("어둡게", "Dark") }
    static var themeFooter: String {
        t("‘시스템 설정 따르기’를 고르면 macOS의 밝게/어둡게 설정을 그대로 씁니다.",
          "“Match System” follows the light/dark setting in macOS.")
    }
    static var languageLabel: String { t("언어", "Language") }
    static var languageFooter: String {
        t("고른 언어가 바로 적용됩니다. 앱을 다시 실행할 필요는 없습니다.",
          "The language changes immediately — no relaunch needed.")
    }

    static var sectionConnection: String { t("연결", "Connection") }
    static var notStored: String { t("저장하지 않음", "Never stored") }
    static var passwordPolicyFooter: String {
        t("비밀번호와 키 암호는 어디에도 기록하지 않고 연결할 때마다 입력받습니다. 개인 키는 암호로 보호된 경우에만 물어봅니다.",
          "Passwords and passphrases are never written anywhere; you enter them on every connection. You're only asked for a passphrase when the key is protected.")
    }

    static var sectionDisplay: String { t("표시", "Display") }
    static var showHiddenDefault: String { t("숨김 파일 표시", "Show hidden files") }
    static var sortKeyLabel: String { t("정렬 기준", "Sort by") }
    static var sortDirectionLabel: String { t("정렬 방향", "Order") }
    static var ascending: String { t("오름차순", "Ascending") }
    static var descending: String { t("내림차순", "Descending") }
    static var displayFooter: String {
        t("두 창에 바로 적용되고 다음 실행에도 유지됩니다. 각 창의 열 머리글로 그때그때 바꿀 수도 있습니다.",
          "Applies to both panes right away and is remembered next launch. Each pane's column headers still override it.")
    }
    static var doubleClickLabel: String { t("로컬 파일 더블클릭", "Double-click a local file") }
    static var doubleClickFooter: String {
        t("폴더는 설정과 무관하게 항상 열립니다. 원격 파일을 더블클릭하면 언제나 내려받습니다.",
          "Folders always open regardless. Double-clicking a remote file always downloads it.")
    }

    static var conflictSettingLabel: String { t("같은 이름이 있을 때", "When a name already exists") }
    static var showTransfersAtLaunchLabel: String {
        t("시작할 때 전송 목록 열어 두기", "Open the transfer list at launch")
    }
    static var notifyOnFinishLabel: String { t("전송이 끝나면 알리기", "Notify when transfers finish") }
    static var transferFooter: String {
        t("‘물어보기’를 고르면 이름이 겹칠 때마다 확인 창이 뜨고, 그 창에서 나머지에도 같은 선택을 적용할 수 있습니다. 알림은 소리와 Dock 아이콘 튀기기로 표시하고, 실패한 항목이 있으면 다른 소리가 납니다.",
          "“Ask” shows a dialog for every clash, where you can apply the same answer to the rest. Notifications are a sound plus a Dock bounce, with a different sound when something failed.")
    }

    static var speed: String { t("속도", "Speed") }
    static var pipelineDepthLabel: String { t("동시 요청 수", "Concurrent requests") }
    static func recommended(_ value: Int) -> String { t("\(value) (권장)", "\(value) (recommended)") }
    static var pipelineFooter: String {
        t("한 번에 서버로 보내는 요청 개수입니다. 값이 클수록 지연이 큰 회선에서 빨라지지만 메모리를 더 씁니다(요청당 약 32KB). 64는 OpenSSH의 sftp 클라이언트와 같은 값입니다. 다음 연결부터 적용됩니다.",
          "How many requests are in flight at once. Higher is faster on high-latency links but uses more memory (about 32 KB per request). 64 matches OpenSSH's own sftp client. Takes effect on the next connection.")
    }

    static var remoteEditingTitle: String { t("원격 파일 편집", "Remote File Editing") }
    static var pollIntervalLabel: String { t("변경 확인 주기", "Check for changes every") }
    static func seconds(_ value: Double) -> String {
        value < 1 ? t("0.5초", "0.5 s") : t("\(Int(value))초", "\(Int(value)) s")
    }
    static var showScratchFolder: String { t("임시 폴더 보기", "Show Scratch Folder") }
    static var cleanScratchFiles: String { t("남은 임시 파일 정리", "Clean Up Leftovers") }
    static var nothingToClean: String { t("정리할 파일이 없습니다.", "Nothing to clean up.") }
    static func cleanedCount(_ n: Int) -> String { t("\(n)개 정리했습니다.", "Cleaned up \(n).") }
    static var remoteEditingFooter: String {
        t("편집기가 파일을 저장한 뒤 이 주기만큼 변화가 멈추면 서버로 올립니다.",
          "Once your editor saves and the file stops changing for this long, it's uploaded.")
    }

    static var sectionFileLocations: String { t("파일 위치", "File Locations") }
    static var hostKeysPath: String { t("호스트 키", "Host keys") }
    static var serverListPath: String { t("서버 목록", "Server list") }
    static var resetSettings: String { t("설정 초기화…", "Reset Settings…") }
    static var resetFooter: String {
        t("저장한 서버와 known_hosts는 그대로 두고, 이 창의 설정만 처음 상태로 되돌립니다.",
          "Leaves your saved servers and known_hosts alone; only the settings in this window go back to their defaults.")
    }
    static var resetConfirmTitle: String {
        t("설정을 처음 상태로 되돌릴까요?", "Reset settings to their defaults?")
    }
    static var reset: String { t("초기화", "Reset") }

    // MARK: - About

    static var madeBy: String { t("만든이", "Made by") }
    static var version: String { t("버전", "Version") }
    static var builtWith: String { t("사용 기술", "Built with") }
    static var aboutTagline: String {
        t("두 창으로 파일을 옮기는 macOS용 SFTP 클라이언트.",
          "A two-pane SFTP client for macOS.")
    }
    static var copyEmail: String { t("메일 주소 복사", "Copy Email Address") }
    static var openHelpFromAbout: String { t("사용법 보기", "Open the Guide") }
}
