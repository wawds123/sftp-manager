import AppKit
import SwiftTerm
import Foundation

/// Headless verification for the parts of the app that don't need a window.
///
/// Usage:
///   swift run SFTPManager --selftest
///   swift run SFTPManager --selftest --host 127.0.0.1 --port 2222 --user me --key ~/.ssh/id_ed25519 [--passphrase secret]
///
/// Without server arguments only the pure-logic checks run; with them the SFTP
/// round-trip (upload, list, download, rename, walk, recursive delete) runs too.
enum SelfTest {
    private nonisolated(unsafe) static var failures = 0
    private nonisolated(unsafe) static var checks = 0

    static func run(arguments: [String]) {
        // Line-buffer stdout so results survive if a check crashes the process.
        setvbuf(stdout, nil, _IOLBF, 0)
        pathChecks()
        sortingChecks()
        activePaneChecks()
        glyphChecks()
        localizationChecks()
        dragPayloadChecks()
        preferenceChecks()
        keyInspectionChecks()
        knownHostsChecks()
        remoteEditChecks()
        shellChecks()

        if let server = ServerArguments(arguments) {
            // The main run loop has to keep turning, not block on a semaphore:
            // the edit watcher is a `Timer` and MainActor work is serviced by
            // the main queue.
            let finished = Flag()
            Task {
                await sftpChecks(server)
                finished.set()
            }
            while !finished.isSet {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        } else {
            note("SFTP 통합 검사 건너뜀 (--host/--user/--key 미지정)")
        }

        print("\n\(checks - failures)/\(checks) 통과")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Assertions

    private static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        checks += 1
        if actual == expected {
            print("  ✓ \(label)")
        } else {
            failures += 1
            print("  ✗ \(label)\n      기대: \(expected)\n      실제: \(actual)")
        }
    }

    private static func expectTrue(_ condition: Bool, _ label: String) {
        expect(condition, true, label)
    }

    private static func section(_ title: String) { print("\n▸ \(title)") }
    private static func note(_ text: String) { print("\n· \(text)") }

    // MARK: - Pure logic

    private static func pathChecks() {
        section("경로 처리")
        expect(PathUtil.normalize("/var//log/./nginx/"), "/var/log/nginx", "중복 슬래시와 . 제거")
        expect(PathUtil.normalize("/var/log/../tmp"), "/var/tmp", ".. 해석")
        expect(PathUtil.normalize("/.."), "/", "루트 위로는 못 올라감")
        expect(PathUtil.join("/", "etc"), "/etc", "루트에 이어붙이기")
        expect(PathUtil.join("/home/jack", "docs"), "/home/jack/docs", "일반 이어붙이기")
        expect(PathUtil.join("/home/jack", "/etc"), "/etc", "절대 경로는 base를 무시")
        expect(PathUtil.parent(of: "/home/jack/docs"), "/home/jack", "상위 경로")
        expect(PathUtil.parent(of: "/home"), "/", "루트 바로 아래의 상위 경로")
        expect(PathUtil.parent(of: "/"), "/", "루트의 상위는 루트")
        expect(PathUtil.lastComponent(of: "/home/jack/a.txt"), "a.txt", "마지막 구성요소")
        expect(PathUtil.breadcrumbs(for: "/a/b").map(\.1), ["/", "/a", "/a/b"], "브레드크럼")
    }

    private static func sortingChecks() {
        section("파일 목록 정렬/필터")
        let items = [
            FileItem(path: "/a/z.txt", name: "z.txt", kind: .file, size: 10, modified: nil, permissions: nil),
            FileItem(path: "/a/.hidden", name: ".hidden", kind: .file, size: 1, modified: nil, permissions: nil),
            FileItem(path: "/a/b", name: "b", kind: .directory, size: 0, modified: nil, permissions: nil),
            FileItem(path: "/a/a.txt", name: "a.txt", kind: .file, size: 99, modified: nil, permissions: nil),
        ]
        // `run` is called from main.swift, i.e. already on the main thread.
        MainActor.assumeIsolated {
            let pane = PaneState(side: .local)
            pane.setItems(items)
            expect(pane.visibleItems.map(\.name), ["b", "a.txt", "z.txt"], "폴더 우선 + 숨김 제외")

            pane.showHidden = true
            expect(pane.visibleItems.map(\.name), ["b", ".hidden", "a.txt", "z.txt"], "숨김 파일 표시")

            pane.showHidden = false
            pane.sortKey = .size
            pane.ascending = false
            expect(pane.visibleItems.map(\.name), ["b", "a.txt", "z.txt"], "크기 내림차순에서도 폴더 우선")

            pane.filter = "z"
            expect(pane.visibleItems.map(\.name), ["z.txt"], "이름 필터")

            pane.filter = ""
            pane.setPath("/home", record: false)
            pane.resetHistory()
            expectTrue(!pane.canGoBack, "히스토리 초기화")
            pane.setPath("/home/docs")
            expect(pane.popBack(), "/home", "뒤로 가기")
            pane.setPath("/home", record: false)
            expect(pane.popForward(), "/home/docs", "앞으로 가기")
        }

        // The owner name only ever comes from the server's `ls -l` line.
        expect(PathUtil.owner(fromLongname: "-rw-r--r--  1 deploy  staff  1234 Sep  3 14:00 a.txt"),
               "deploy", "longname에서 소유자 추출")
        expect(PathUtil.owner(fromLongname: "drwxr-xr-x 12 root root 4096 Jan  2 09:10 srv"),
               "root", "공백 개수가 달라도 추출")
        expect(PathUtil.owner(fromLongname: "lrwxrwxrwx 1 www-data www-data 7 Feb  1 00:00 link -> a"),
               "www-data", "심볼릭 링크 줄")
        expectTrue(PathUtil.owner(fromLongname: "a.txt") == nil, "이름만 있는 줄은 nil")
        expectTrue(PathUtil.owner(fromLongname: "") == nil, "빈 줄은 nil")
        expectTrue(PathUtil.owner(fromLongname: "not-a-mode 1 deploy staff 1 Sep 3 14:00 a") == nil,
                   "권한 모양이 아니면 추측하지 않음")
        expectTrue(PathUtil.owner(fromLongname: "-rw-r--r-- x deploy staff 1 Sep 3 14:00 a") == nil,
                   "링크 수가 숫자가 아니면 추측하지 않음")

        MainActor.assumeIsolated {
            let pane = PaneState(side: .remote)
            pane.setItems([
                FileItem(path: "/a/c", name: "c", kind: .file, size: 0, modified: nil, permissions: nil, owner: "root"),
                FileItem(path: "/a/a", name: "a", kind: .file, size: 0, modified: nil, permissions: nil, owner: "deploy"),
                FileItem(path: "/a/b", name: "b", kind: .file, size: 0, modified: nil, permissions: nil, owner: nil),
            ])
            pane.sortKey = .owner
            pane.ascending = true
            expect(pane.visibleItems.map(\.name), ["b", "a", "c"], "소유자 오름차순 (알 수 없는 소유자가 먼저)")
            pane.ascending = false
            expect(pane.visibleItems.map(\.name), ["c", "a", "b"], "소유자 내림차순")
        }

        let permissioned = FileItem(path: "/a/x", name: "x", kind: .file, size: 0, modified: nil, permissions: 0o754)
        expect(permissioned.permissionString, "rwxr-xr--", "권한 문자열")

        MainActor.assumeIsolated {
            let pane = PaneState(side: .local)
            pane.setItems([
                FileItem(path: "/a/c", name: "c", kind: .file, size: 0, modified: nil, permissions: 0o755),
                FileItem(path: "/a/a", name: "a", kind: .file, size: 0, modified: nil, permissions: 0o600),
                FileItem(path: "/a/b", name: "b", kind: .file, size: 0, modified: nil, permissions: 0o644),
                FileItem(path: "/a/d", name: "d", kind: .file, size: 0, modified: nil, permissions: nil),
            ])
            pane.sortKey = .permissions
            pane.ascending = true
            expect(pane.visibleItems.map(\.name), ["d", "a", "b", "c"], "권한 오름차순 (알 수 없는 권한이 먼저)")
            pane.ascending = false
            expect(pane.visibleItems.map(\.name), ["c", "b", "a", "d"], "권한 내림차순")
        }
    }

    private static func activePaneChecks() {
        section("활성 패널")
        MainActor.assumeIsolated {
            let model = AppModel()
            expect(model.activePane, .local, "기본 활성 패널은 로컬")
            expect(model.pane(model.activePane).side, .local, "활성 패널이 로컬 패널을 가리킴")

            model.activate(.remote)
            expect(model.activePane, .remote, "원격 클릭 후 활성 패널 전환")
            expect(model.pane(model.activePane).side, .remote, "활성 패널이 원격 패널을 가리킴")

            // Re-activating must not churn @Published (it would redraw both panes).
            model.activate(.remote)
            expect(model.activePane, .remote, "같은 패널 재활성화는 무시")

            model.activate(.local)
            expect(model.activePane, .local, "로컬로 되돌아감")
        }
    }

    private static func shellChecks() {
        section("셸 패널 로직")
        expect(ShellQuote.singleQuoted("/var/log"), "'/var/log'", "일반 경로 인용")
        expect(ShellQuote.singleQuoted("/tmp/my files"), "'/tmp/my files'", "공백이 있어도 한 덩어리")
        expect(ShellQuote.singleQuoted("/tmp/it's"), "'/tmp/it'\\''s'", "작은따옴표 이스케이프")
        expect(ShellQuote.singleQuoted("/tmp/$(whoami)"), "'/tmp/$(whoami)'", "명령 치환은 인용 안에서 무력화")

        // OSC 7 reports arrive as file:// URIs, not bare paths.
        expect(HostDirectoryURI.path(from: "file:///srv/app"), "/srv/app", "호스트가 빈 OSC 7 보고")
        expect(HostDirectoryURI.path(from: "file://web-01/srv/app"), "/srv/app", "호스트가 붙은 보고")
        expect(HostDirectoryURI.path(from: "file:///srv/my%20app"), "/srv/my app", "퍼센트 인코딩 해제")
        expect(HostDirectoryURI.path(from: "/srv/app"), "/srv/app", "스킴 없는 절대 경로도 허용")
        expectTrue(HostDirectoryURI.path(from: "file://web-01") == nil, "경로가 없으면 무시")
        expectTrue(HostDirectoryURI.path(from: "relative/path") == nil, "상대 경로는 무시")

        // Most shells put the working directory in the window title instead.
        let home = "/home/deploy"
        expect(ShellTitlePath.path(from: "deploy@web-01:/srv/app/releases/", home: home),
               "/srv/app/releases", "제목에서 경로 추출")
        expect(ShellTitlePath.path(from: "deploy@web-01:~/logs", home: home), "/home/deploy/logs", "제목의 ~ 확장")
        expect(ShellTitlePath.path(from: "deploy@web-01:~", home: home), home, "제목이 ~ 하나뿐")
        expect(ShellTitlePath.path(from: "deploy@web:/srv/a:b/c", home: home), "/srv/a:b/c", "경로에 콜론이 있어도 호스트만 떼어냄")
        expect(ShellTitlePath.path(from: "/srv/app", home: home), "/srv/app", "제목이 경로뿐")
        expectTrue(ShellTitlePath.path(from: "vim /etc/hosts", home: home) == nil, "명령 이름은 경로로 보지 않음")
        expectTrue(ShellTitlePath.path(from: "bash", home: home) == nil, "경로가 없는 제목은 무시")

        // The terminal caches whatever colours it was handed, so it has to
        // re-read them when the theme changes.
        MainActor.assumeIsolated {
            let view = ThemedTerminalView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
            // The emulator's own colours are what actually gets drawn; the
            // NSColor it was handed stays dynamic and would resolve light here.
            view.appearance = NSAppearance(named: .aqua)
            view.applyNativeColors()
            let light = brightness(view.getTerminal().backgroundColor)

            view.appearance = NSAppearance(named: .darkAqua)
            view.applyNativeColors()
            let dark = brightness(view.getTerminal().backgroundColor)
            let darkText = brightness(view.getTerminal().foregroundColor)

            expectTrue(light > 0.5, "밝은 테마에서 터미널 배경도 밝음 (\(light))")
            expectTrue(dark < 0.5, "테마를 바꾸면 터미널 배경도 어두워짐 (\(dark))")
            expectTrue(darkText > dark, "어두운 배경 위의 글자가 더 밝음")
        }

        // The shell never says "the command finished"; silence stands in for it.
        var idle = ShellIdleRefresh(quietPeriod: 0.7)
        let start = Date()
        expectTrue(!idle.consumeRefresh(at: start), "명령을 보내기 전에는 새로 고치지 않음")

        idle.noteSubmit(at: start)
        expectTrue(!idle.consumeRefresh(at: start.addingTimeInterval(0.3)), "출력이 멈추기 전에는 기다림")

        idle.noteOutput(at: start.addingTimeInterval(0.5))
        expectTrue(!idle.consumeRefresh(at: start.addingTimeInterval(1.0)), "출력이 이어지면 타이머가 다시 시작")
        expectTrue(idle.consumeRefresh(at: start.addingTimeInterval(1.3)), "출력이 멎으면 새로 고침")
        expectTrue(!idle.consumeRefresh(at: start.addingTimeInterval(5)), "한 명령에 한 번만 새로 고침")

        MainActor.assumeIsolated {
            let model = AppModel()
            expect(model.bottomTab, .transfers, "아래 패널 기본 탭은 전송")

            // Selecting the tab while disconnected must open the tab and explain
            // itself there, not pop an alert.
            model.showTerminalTab()
            expect(model.bottomTab, .terminal, "연결 전에도 터미널 탭은 열림")
            expectTrue(model.showBottomPanel, "터미널 탭을 고르면 패널이 펼쳐짐")
            expectTrue(model.alertMessage == nil, "탭 전환만으로는 경고를 띄우지 않음")
            expectTrue(model.shell == nil, "연결이 없으면 셸을 만들지 않음")

            // The explicit command (toolbar/menu) still says why it can't run.
            model.openTerminal()
            expectTrue(model.alertMessage != nil, "연결 없이 터미널을 열면 안내")
        }

        // A shell the user ended with `exit` has to stay ended. Switching to the
        // transfer tab and back used to open a brand new channel, and because
        // `updateNSView` cannot swap the view it was handed, that live shell ran
        // behind the dead screen of the session before it.
        MainActor.assumeIsolated {
            let model = AppModel()
            model.previewConnected(UUID(), name: "테스트")
            let shell = ShellSession(previewOutput: "$ ")
            model.shell = shell

            shell.close()
            expectTrue(shell.state.isClosed, "exit 하면 셸이 종료 상태")

            model.bottomTab = .transfers
            model.showTerminalTab()
            expect(model.bottomTab, .terminal, "터미널 탭으로 다시 돌아옴")
            expectTrue(model.shell === shell, "탭을 다시 눌러도 새 셸을 열지 않음")
            expectTrue(model.shell?.state.isClosed == true, "끝난 세션은 끝난 채로 보임")
            expectTrue(model.alertMessage == nil, "돌아오는 것만으로는 경고도 없음")

            // 정리 is the only thing that discards it.
            model.closeTerminal()
            expectTrue(model.shell == nil, "정리하면 끝난 세션이 사라짐")
            expect(model.bottomTab, .transfers, "정리 후에는 전송 탭으로")
        }

        // Nothing may be typed for the user while a full-screen program owns
        // the screen: the keystrokes would go to that program.
        MainActor.assumeIsolated {
            let shell = ShellSession(previewOutput: "$ ")
            expectTrue(shell.isAtPrompt, "보통은 프롬프트 상태")
            shell.view.feed(text: "\u{1b}[?1049h")   // enter the alternate buffer, as vim does
            expectTrue(!shell.isAtPrompt, "전체 화면 프로그램 실행 중에는 입력하지 않음")
            shell.view.feed(text: "\u{1b}[?1049l")   // and back
            expectTrue(shell.isAtPrompt, "프로그램이 끝나면 다시 프롬프트")

            let model = AppModel()
            model.shell = shell
            shell.view.feed(text: "\u{1b}[?1049h")
            model.runInTerminal("cd /tmp")
            expectTrue(model.alertMessage != nil, "그 상태에서 명령을 보내면 안내")
        }

        // The sidebar must not offer "연결" for the server it is already on.
        MainActor.assumeIsolated {
            let model = AppModel()
            var connection = Connection()
            connection.name = "테스트"
            connection.host = "example.invalid"
            model.connections = [connection]
            model.selectedConnectionID = connection.id

            expectTrue(!model.isConnected(to: connection.id), "연결 전에는 연결된 서버가 아님")
            expectTrue(!model.isConnected(to: nil), "선택된 서버가 없으면 연결된 서버도 없음")

            model.previewConnected(connection.id, name: connection.displayName)
            expectTrue(model.isConnected(to: connection.id), "연결 후에는 그 서버가 연결됨")

            // Double-clicking the row it is already on used to reconnect, which
            // dropped the session and asked for the password again.
            model.requestSession(for: connection.id)
            expectTrue(model.status.isConnected, "이미 연결된 서버는 다시 연결하지 않음")
            expectTrue(model.promptRequest == nil, "비밀번호를 다시 묻지 않음")
        }

        // Output with no command behind it (a background job writing) must not
        // trigger a reload on its own.
        idle.noteOutput(at: start.addingTimeInterval(6))
        expectTrue(!idle.consumeRefresh(at: start.addingTimeInterval(10)), "명령 없이 나온 출력은 무시")
    }

    /// Both languages have to be complete, and switching has to actually take.
    ///
    /// Anything enumerable is walked here. The strings that live as individual
    /// `L` members can't be reflected over, so `Scripts/check_l10n.sh` covers
    /// those by grepping the source for stray Korean literals.
    private static func localizationChecks() {
        section("언어")
        let original = Lang.current
        defer { Lang.current = original }

        Lang.current = .korean
        expect(L.cancel, "취소", "한국어 문자열")
        expect(L.conflictRename, "이름 바꿔 저장", "한국어 문자열 (충돌)")
        Lang.current = .english
        expect(L.cancel, "Cancel", "언어를 바꾸면 문자열도 바뀜")
        expect(L.conflictRename, "Keep Both", "영어 문자열 (충돌)")

        // Each option names itself, so the picker stays readable in either mode.
        expect(AppLanguage.korean.label, "한국어", "언어 이름은 그 언어로")
        expect(AppLanguage.english.label, "English", "언어 이름은 그 언어로 (영어)")
        expect(AppLanguage(rawValue: "ko"), .korean, "저장된 값에서 복원")
        expectTrue(AppLanguage(rawValue: "fr") == nil, "모르는 언어 코드는 거부")
        expectTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault),
                   "첫 실행 기본값은 실제 지원 언어")

        // A label left untranslated shows Korean in the English interface.
        func hangul(_ text: String) -> Bool {
            text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value)
                || (0x1100...0x11FF).contains($0.value)
                || (0x3130...0x318F).contains($0.value) }
        }

        Lang.current = .english
        var untranslated: [String] = []
        untranslated += AppTheme.allCases.map(\.label).filter(hangul)
        untranslated += SortKey.allCases.map(\.label).filter(hangul)
        untranslated += ConflictPolicy.allCases.map(\.label).filter(hangul)
        untranslated += LocalDoubleClickAction.allCases.map(\.label).filter(hangul)
        untranslated += [PaneSide.local, .remote].map(\.title).filter(hangul)
        untranslated += [BottomTab.transfers, .terminal].map(\.label).filter(hangul)
        untranslated += [TransferDirection.upload, .download].map(\.label).filter(hangul)
        expect(untranslated, [], "영어 모드에서 한글이 남은 enum 레이블 없음")

        // The Help window is data, so all of it can be walked.
        for language in AppLanguage.allCases {
            Lang.current = language
            let topics = HelpBook.topics
            expectTrue(topics.count >= 5, "\(language.label): 도움말 주제가 충분함 (\(topics.count))")
            expect(Set(topics.map(\.id)).count, topics.count, "\(language.label): 주제 id 중복 없음")
            expectTrue(topics.allSatisfy { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty },
                       "\(language.label): 빈 제목 없음")
            expectTrue(topics.allSatisfy { !$0.entries.isEmpty }, "\(language.label): 빈 주제 없음")
            let entries = topics.flatMap(\.entries)
            expectTrue(entries.allSatisfy { !$0.detail.trimmingCharacters(in: .whitespaces).isEmpty },
                       "\(language.label): 빈 설명 없음")
            expectTrue(entries.allSatisfy { $0.term.map { !$0.isEmpty } ?? true },
                       "\(language.label): 빈 소제목 없음")
        }

        // Same walk, but checking the English column is actually English.
        Lang.current = .english
        let englishText = HelpBook.topics.flatMap { [$0.title] + $0.entries.flatMap { [$0.term ?? "", $0.detail] } }
        expect(englishText.filter(hangul), [], "영어 도움말에 한글이 남지 않음")

        // Shortcut chips are the same glyphs in both languages, so they are
        // compared across the switch rather than translated.
        Lang.current = .korean
        let koreanKeys = HelpBook.topics.flatMap { $0.entries.compactMap(\.shortcut) }
        Lang.current = .english
        let englishKeys = HelpBook.topics.flatMap { $0.entries.compactMap(\.shortcut) }
        expect(koreanKeys, englishKeys, "단축키 표기는 언어와 무관")
        expectTrue(!koreanKeys.isEmpty, "단축키가 실제로 실려 있음 (\(koreanKeys.count)개)")

        // A misspelled SF Symbol leaves a blank gap in the topic list.
        let symbols = HelpBook.topics.map(\.symbol)
        let missing = symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        expect(missing, [], "도움말 아이콘이 모두 존재함 (\(symbols.count)개)")

        // The author is shown in the app and written into Info.plist; they are
        // the same person in both places.
        expect(AboutView.authorName, "jackson", "만든이 이름")
        expect(AboutView.authorEmail, "wawds123@gmail.com", "만든이 메일")
        if let plist = try? String(contentsOfFile: "Resources/Info.plist", encoding: .utf8) {
            expectTrue(plist.contains(AboutView.authorEmail), "Info.plist에도 같은 만든이")
            expectTrue(plist.contains("MIT"), "Info.plist 저작권 줄이 LICENSE와 같은 라이선스")
        }
    }

    private static func glyphChecks() {
        section("파일 아이콘")

        func glyph(_ name: String, _ kind: FileItem.Kind = .file) -> FileGlyph.Glyph {
            FileGlyph.glyph(for: FileItem(path: "/a/" + name, name: name, kind: kind,
                                          size: 0, modified: nil, permissions: nil))
        }

        expect(glyph("notes.md").symbol, "book.fill", "확장자로 문서 아이콘")
        expect(glyph("NOTES.MD").symbol, "book.fill", "확장자는 대소문자 무시")
        expect(glyph("server.log").symbol, "list.bullet.rectangle", "로그 파일")
        expect(glyph("id_ed25519.pub").symbol, "key.fill", "공개 키")
        expect(glyph("deploy.sh").symbol, "terminal.fill", "셸 스크립트")
        expect(glyph("Makefile").symbol, "hammer.fill", "확장자 없는 이름")
        expect(glyph(".zshrc").symbol, "terminal.fill", "점으로 시작하는 설정 파일")
        expect(glyph("README.md").symbol, "book.fill", "확장자가 이름보다 우선")
        expect(glyph("mystery.qqq").symbol, FileGlyph.file.symbol, "모르는 확장자는 기본 아이콘")
        // A directory keeps the folder glyph even when its name matches one of
        // the file tables — the icon says "you can go in here", nothing else.
        expect(glyph("Downloads", .directory).symbol, FileGlyph.folder.symbol, "이름이 알려져도 폴더는 폴더")
        expect(glyph(".git", .directory).symbol, FileGlyph.folder.symbol, "점으로 시작하는 폴더도 폴더")
        expect(glyph("server.log", .directory).symbol, FileGlyph.folder.symbol, "확장자가 붙은 폴더도 폴더")
        expect(glyph("whatever", .directory).symbol, FileGlyph.folder.symbol, "그 밖의 폴더")
        expect(glyph("link", .symlink).symbol, FileGlyph.symlink.symbol, "심볼릭 링크")

        // A misspelled SF Symbol draws nothing at all, and only on machines that
        // lack it — so every name in the table is resolved here.
        let missing = FileGlyph.allSymbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        expect(missing, [], "모든 SF Symbol이 실제로 존재함 (\(FileGlyph.allSymbols.count)개)")
    }

    private static func dragPayloadChecks() {
        section("경로 주입 방어")
        // Directory-entry names are whatever the server sends.
        expectTrue(PathUtil.isSafeComponent("report.pdf"), "보통 이름은 통과")
        expectTrue(PathUtil.isSafeComponent("..hidden"), "점 두 개로 시작하는 이름은 정상")
        expectTrue(!PathUtil.isSafeComponent(".."), "상위 디렉터리 이름 거부")
        expectTrue(!PathUtil.isSafeComponent("."), "현재 디렉터리 이름 거부")
        expectTrue(!PathUtil.isSafeComponent(""), "빈 이름 거부")
        expectTrue(!PathUtil.isSafeComponent("a/b"), "슬래시가 든 이름 거부")
        expectTrue(!PathUtil.isSafeComponent("/etc/passwd"), "절대 경로 이름 거부")
        expectTrue(!PathUtil.isSafeComponent("evil\u{0}.txt"), "널 바이트가 든 이름 거부")

        // ...and the download path is built so that even a bad one cannot escape.
        expect(PathUtil.containedJoin("/Users/me/Downloads", "a/b.txt"), "/Users/me/Downloads/a/b.txt",
               "정상적인 하위 경로")
        expectTrue(PathUtil.containedJoin("/Users/me/Downloads", "../../evil") == nil,
                   "상위로 빠져나가는 경로 거부")
        expectTrue(PathUtil.containedJoin("/Users/me/Downloads", "a/../../../evil") == nil,
                   "중간에 빠져나가는 경로 거부")
        expectTrue(PathUtil.containedJoin("/Users/me/Downloads", "/etc/cron.d/x") == nil,
                   "절대 경로 거부")
        expectTrue(PathUtil.containedJoin("/Users/me/Downloads", "..") == nil, "대상 폴더 자기 자신 거부")
        expect(PathUtil.containedJoin("/Users/me/Downloads", "a/../b"), "/Users/me/Downloads/b",
               "안에서 도는 .. 는 허용")
        expect(PathUtil.containedJoin("/", "etc/x"), "/etc/x", "루트가 대상일 때")
        expectTrue(PathUtil.containedJoin("/Users/me/Down", "../Downloads/x") == nil,
                   "이름이 겹치는 이웃 폴더로 새지 않음")

        MainActor.assumeIsolated {
            let model = AppModel()
            model.createDirectory(.local, named: "../escape")
            expectTrue(model.alertMessage != nil, "새 폴더 이름에 경로를 넣으면 거부")

            let file = FileItem(path: "/tmp/a.txt", name: "a.txt", kind: .file,
                                size: 0, modified: nil, permissions: nil)
            model.alertMessage = nil
            model.rename(.local, item: file, to: "../../b.txt")
            expectTrue(model.alertMessage != nil, "이름 바꾸기로 다른 폴더에 쓰지 못함")
        }

        // The shell is only ever handed quoted paths, so a name cannot become a
        // command no matter what the server calls it.
        expect(ShellQuote.singleQuoted("/srv/$(id)`id`;rm -rf ~"), "'/srv/$(id)`id`;rm -rf ~'",
               "셸 메타문자는 인용 안에서 무력")

        section("이름 충돌")
        expect(AppModel.uniqueName(for: "report.pdf", taken: []), "report.pdf", "겹치지 않으면 그대로")
        expect(AppModel.uniqueName(for: "report.pdf", taken: ["report.pdf"]), "report 2.pdf", "겹치면 번호를 붙임")
        expect(AppModel.uniqueName(for: "report.pdf", taken: ["report.pdf", "report 2.pdf"]),
               "report 3.pdf", "번호도 겹치면 다음 번호")
        expect(AppModel.uniqueName(for: "Makefile", taken: ["Makefile"]), "Makefile 2", "확장자가 없는 이름")
        expect(AppModel.uniqueName(for: "backup.tar.gz", taken: ["backup.tar.gz"]), "backup.tar 2.gz",
               "마지막 확장자만 확장자로 봄")
        expect(AppModel.uniqueName(for: ".zshrc", taken: [".zshrc"]), ".zshrc 2", "점으로 시작하는 이름")

        section("드래그 페이로드")
        let encoded = DragPayload.encode(side: .remote, paths: ["/srv/a", "/srv/b"])
        let decoded = DragPayload.decode(encoded)
        expect(decoded?.side, .remote, "출처 창 복원")
        expect(decoded?.paths, ["/srv/a", "/srv/b"], "경로 목록 복원")
        expectTrue(DragPayload.decode("hello world") == nil, "관계없는 텍스트는 거부")
    }

    /// The connect flow only asks for a passphrase when the key really has one,
    /// so the header parsing has to be right for both shapes.
    private static func keyInspectionChecks() {
        section("개인 키 암호 여부 판별")
        let directory = NSTemporaryDirectory() + "sftp-keys-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let plain = directory + "/plain_ed25519"
        let locked = directory + "/locked_ed25519"
        let lockedRSA = directory + "/locked_rsa"
        guard generateKey(at: plain, type: "ed25519", passphrase: ""),
              generateKey(at: locked, type: "ed25519", passphrase: "hunter2"),
              generateKey(at: lockedRSA, type: "rsa", passphrase: "hunter2") else {
            note("ssh-keygen을 실행할 수 없어 건너뜀")
            return
        }

        expect(OpenSSHKeyInspector.isEncrypted(atPath: plain), false, "암호 없는 ED25519 키")
        expect(OpenSSHKeyInspector.isEncrypted(atPath: locked), true, "암호로 보호된 ED25519 키")
        expect(OpenSSHKeyInspector.isEncrypted(atPath: lockedRSA), true, "암호로 보호된 RSA 키")
        expect(OpenSSHKeyInspector.isEncrypted(atPath: directory + "/does-not-exist"), false, "없는 파일")
        expect(OpenSSHKeyInspector.isEncrypted("이건 키가 아닙니다"), false, "키가 아닌 텍스트")
    }

    private static func generateKey(at path: String, type: String, passphrase: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-q", "-t", type, "-f", path, "-N", passphrase, "-C", "selftest"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// known_hosts parsing has to match OpenSSH exactly — a wrong match here is
    /// either a lockout or a silently accepted man-in-the-middle.
    private static func knownHostsChecks() {
        section("known_hosts 처리")

        expect(KnownHosts.hostPattern(host: "example.com", port: 22), "example.com", "기본 포트는 그대로")
        expect(KnownHosts.hostPattern(host: "example.com", port: 2222), "[example.com]:2222", "비표준 포트는 대괄호")

        expectTrue(KnownHosts.matches(hostField: "example.com", target: "example.com"), "정확히 일치")
        expectTrue(!KnownHosts.matches(hostField: "example.com", target: "other.com"), "다른 호스트는 불일치")
        expectTrue(KnownHosts.matches(hostField: "a.com,b.com,c.com", target: "b.com"), "쉼표로 나열된 호스트")
        expectTrue(KnownHosts.matches(hostField: "*.example.com", target: "srv.example.com"), "와일드카드")
        expectTrue(!KnownHosts.matches(hostField: "*.example.com", target: "example.com"), "와일드카드는 상위 도메인 제외")
        expectTrue(!KnownHosts.matches(hostField: "*.example.com,!bad.example.com", target: "bad.example.com"), "부정 패턴이 우선")
        expectTrue(KnownHosts.matches(hostField: "[example.com]:2222", target: "[example.com]:2222"), "포트 포함 일치")

        // Hashed entries, as produced by `ssh-keygen -H` / HashKnownHosts yes.
        if let hashed = hashedHostField(for: "example.com") {
            expectTrue(KnownHosts.matches(hostField: hashed, target: "example.com"), "해시된 호스트 일치")
            expectTrue(!KnownHosts.matches(hostField: hashed, target: "evil.com"), "해시된 호스트 불일치")
        } else {
            note("해시 항목 생성 실패 — 건너뜀")
        }

        let sample = """
        # a comment
        example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrJk8Aa7WMHOX0K5vJqE9k3l8mEXAMPLEKEYDATA00 user@host
        @revoked bad.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrJk8Aa7WMHOX0K5vJqE9k3l8mEXAMPLEKEYDATA01

        @cert-authority *.corp.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrJk8Aa7WMHOX0K5vJqE9k3l8mEXAMPLEKEYDATA02
        """
        let parsed = KnownHosts.parse(sample)
        expect(parsed.count, 3, "주석과 빈 줄을 건너뜀")
        expect(parsed.first?.hostField, "example.com", "호스트 필드")
        expect(parsed.first?.keyType, "ssh-ed25519", "키 종류")
        expectTrue(parsed.first?.base64Key.hasPrefix("AAAAC3") == true, "키 본문에서 주석 제거")
        expectTrue(parsed[1].isRevoked, "@revoked 인식")
        expectTrue(parsed[2].isCertAuthority, "@cert-authority 인식")
        expect(KnownHosts.entries(matching: "srv.corp.com", port: 22, in: parsed).count, 0, "CA 항목은 호스트 키로 쓰지 않음")
    }

    /// Builds an OpenSSH hashed host field by asking ssh-keygen to hash a file.
    private static func hashedHostField(for host: String) -> String? {
        let path = NSTemporaryDirectory() + "kh-\(UUID().uuidString)"
        let line = "\(host) ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrJk8Aa7WMHOX0K5vJqE9k3l8mEXAMPLEKEYDATA00\n"
        guard (try? line.write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".old")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-H", "-f", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard let hashed = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return KnownHosts.parse(hashed).first?.hostField
    }

    /// The save-detection rule: never upload a half-written file, always upload
    /// once writing has stopped, and survive editors that save by renaming.
    private static func remoteEditChecks() {
        section("원격 파일 편집 감지")
        let downloaded = FileSignature(modified: Date(timeIntervalSince1970: 1000), size: 100)
        var edit = RemoteEdit(
            remotePath: "/etc/app.conf",
            localPath: "/tmp/app.conf",
            name: "app.conf",
            scratchDirectory: "/tmp",
            lastSeen: downloaded,
            uploaded: downloaded,
            status: .watching
        )

        expect(edit.pollAction(current: downloaded), .record, "저장 전에는 업로드하지 않음")

        // The editor writes: first poll sees a new signature, but writing may
        // still be in progress, so only record it.
        let writing = FileSignature(modified: Date(timeIntervalSince1970: 2000), size: 40)
        expect(edit.pollAction(current: writing), .record, "쓰는 중에는 기록만")
        edit.lastSeen = writing

        // Still growing — not stable yet.
        let growing = FileSignature(modified: Date(timeIntervalSince1970: 2001), size: 90)
        expect(edit.pollAction(current: growing), .record, "크기가 계속 변하면 기다림")
        edit.lastSeen = growing

        // Unchanged since the previous poll: the save has finished.
        expect(edit.pollAction(current: growing), .upload, "변화가 멈추면 업로드")

        // Mid atomic save the file can be missing for a moment.
        expect(edit.pollAction(current: nil), .ignore, "파일이 잠시 사라져도 무시")

        // After a successful upload, the same signature must not upload again.
        edit.uploaded = growing
        edit.lastSeen = growing
        expect(edit.pollAction(current: growing), .record, "업로드한 내용은 다시 올리지 않음")

        // Nothing happens while an upload is already in flight or after failure.
        edit.status = .uploading
        expect(edit.pollAction(current: writing), .ignore, "업로드 중에는 겹쳐 올리지 않음")
        edit.status = .failed("권한 없음")
        expect(edit.pollAction(current: writing), .ignore, "실패 상태에서는 자동 재시도 안 함")
    }

    private static func preferenceChecks() {
        section("설정 저장과 복원")
        MainActor.assumeIsolated {
            let defaults = UserDefaults.standard
            let keys = [
                PreferenceKey.theme, PreferenceKey.showHidden, PreferenceKey.sortKey,
                PreferenceKey.sortAscending, PreferenceKey.conflictPolicy, PreferenceKey.doubleClick,
                PreferenceKey.notifyOnFinish, PreferenceKey.showTransfersAtLaunch,
                PreferenceKey.pipelineDepth,
                PreferenceKey.editPollInterval, PreferenceKey.panelHeight,
                PreferenceKey.language,
            ]
            // The user's real settings live here — put every key back afterwards.
            let saved = keys.map { ($0, defaults.object(forKey: $0)) }
            defer {
                for (key, value) in saved {
                    if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
                }
            }
            for key in keys { defaults.removeObject(forKey: key) }

            let fresh = AppModel()
            // With nothing stored, the Mac's own language decides.
            expect(fresh.language, AppLanguage.systemDefault, "첫 실행은 시스템 언어를 따름")
            expect(Lang.current, fresh.language, "읽어들인 언어가 곧바로 반영됨")
            expect(fresh.localDoubleClickAction, .upload, "더블클릭 기본값은 업로드")
            expect(fresh.theme, .system, "테마 기본값은 시스템")
            expect(fresh.conflictPolicy, .ask, "충돌 기본값은 물어보기")
            expect(fresh.pipelineDepth, SFTPSession.defaultPipelineDepth, "동시 요청 기본값")
            expect(fresh.editPollInterval, 1.0, "편집 확인 주기 기본값")
            expectTrue(fresh.showTransfersAtLaunch, "전송 목록은 기본적으로 열린 채 시작")
            expectTrue(fresh.showBottomPanel, "시작 직후 전송 목록이 보임")

            let changed = AppModel()
            changed.theme = .dark
            changed.localDoubleClickAction = .openInDefaultApp
            changed.conflictPolicy = .skip
            changed.showHiddenByDefault = true
            changed.defaultSortKey = .modified
            changed.defaultSortAscending = false
            changed.pipelineDepth = 128
            changed.editPollInterval = 2
            changed.showTransfersAtLaunch = false
            changed.language = .english
            expect(Lang.current, .english, "언어를 바꾸면 즉시 적용")

            expectTrue(changed.local.showHidden, "숨김 설정이 로컬 창에 즉시 적용")
            expect(changed.remote.sortKey, .modified, "정렬 기준이 원격 창에 즉시 적용")
            expectTrue(!changed.remote.ascending, "정렬 방향이 원격 창에 즉시 적용")

            let reloaded = AppModel()
            expect(reloaded.theme, .dark, "테마가 다시 실행해도 유지")
            expect(reloaded.localDoubleClickAction, .openInDefaultApp, "더블클릭 동작 유지")
            expect(reloaded.conflictPolicy, .skip, "충돌 정책 유지")
            expect(reloaded.pipelineDepth, 128, "동시 요청 수 유지")
            expect(reloaded.editPollInterval, 2, "편집 확인 주기 유지")
            expectTrue(!reloaded.showTransfersAtLaunch, "전송 목록 자동 열기 해제 유지")
            expect(reloaded.language, .english, "언어가 다시 실행해도 유지")
            expectTrue(!reloaded.showBottomPanel, "해제하면 시작 시 전송 목록이 접힘")
            expectTrue(reloaded.local.showHidden, "숨김 설정이 시작 시 적용")

            reloaded.resetPreferences()
            expect(reloaded.theme, .system, "초기화 후 테마")
            expect(reloaded.pipelineDepth, SFTPSession.defaultPipelineDepth, "초기화 후 동시 요청 수")
            expectTrue(reloaded.showTransfersAtLaunch, "초기화 후 전송 목록 자동 열기")
            // Reset must not strand the interface in a language the user may
            // not read, so this is the one setting it leaves alone.
            expect(reloaded.language, .english, "초기화해도 언어는 그대로")
            expect(AppModel().language, .english, "초기화 후 다시 실행해도 언어 유지")
            expectTrue(AppModel().conflictPolicy == .ask, "초기화가 저장소에도 반영됨")

            // Routing: a local file with the default setting goes to the
            // transfer queue, which reports that no server is connected yet.
            let transferModel = AppModel()
            transferModel.localDoubleClickAction = .upload
            let file = FileItem(path: "/tmp/a.txt", name: "a.txt", kind: .file, size: 1, modified: nil, permissions: nil)
            transferModel.open(file, in: .local)
            expectTrue(transferModel.alertMessage != nil, "연결 전 더블클릭은 전송을 시도하고 안내를 남김")

            // Folders still navigate regardless of the setting.
            let folderModel = AppModel()
            let folder = FileItem(path: "/tmp", name: "tmp", kind: .directory, size: 0, modified: nil, permissions: nil)
            folderModel.open(folder, in: .local)
            expect(folderModel.local.path, "/tmp", "폴더는 설정과 무관하게 이동")
        }
    }

    // MARK: - SFTP round trip

    private struct ServerArguments {
        let host: String
        let port: Int
        let user: String
        let keyPath: String
        let passphrase: String?
        /// Megabytes to push through for the throughput measurement; nil skips it.
        let benchmarkMB: Int?

        init?(_ arguments: [String]) {
            func value(_ flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                return arguments[index + 1]
            }
            guard let host = value("--host"), let key = value("--key") else { return nil }
            self.host = host
            self.keyPath = key
            self.port = Int(value("--port") ?? "22") ?? 22
            self.user = value("--user") ?? NSUserName()
            self.passphrase = value("--passphrase")
            self.benchmarkMB = value("--bench-mb").flatMap(Int.init)
        }
    }

    private static func sftpChecks(_ server: ServerArguments) async {
        section("SFTP 왕복 (\(server.user)@\(server.host):\(server.port))")

        var connection = Connection()
        connection.host = server.host
        connection.port = server.port
        connection.username = server.user
        connection.authMethod = .privateKey
        connection.privateKeyPath = server.keyPath

        if OpenSSHKeyInspector.isEncrypted(atPath: server.keyPath) {
            expectTrue(server.passphrase != nil, "암호로 보호된 키에는 --passphrase가 필요함")
        }

        // Runs against an isolated known_hosts so the user's real file is never
        // touched; returns the path holding the server's genuine key.
        let knownHosts = await hostKeyChecks(server, connection: connection)

        let session: SFTPSession
        do {
            session = try await SFTPSession.connect(connection, secret: server.passphrase, knownHostsPath: knownHosts)
        } catch {
            checks += 1
            failures += 1
            print("  ✗ 연결\n      \(AppModel.describe(error))")
            return
        }
        expectTrue(!session.homePath.isEmpty, "홈 디렉터리 확인 (\(session.homePath))")

        let root = PathUtil.join(session.homePath, "sftpmanager-selftest-\(UUID().uuidString.prefix(8))")
        do {
            try await session.makeDirectory(root)

            // 200KB exercises the multi-chunk path (32,000 bytes per request).
            let payload = Data((0..<(200 * 1024)).map { UInt8($0 % 251) })
            let localSource = NSTemporaryDirectory() + "sftp-src-\(UUID().uuidString).bin"
            try payload.write(to: URL(fileURLWithPath: localSource))
            defer { try? FileManager.default.removeItem(atPath: localSource) }

            let remoteFile = PathUtil.join(root, "payload.bin")
            let progress = ProgressRecorder()
            try await session.upload(localPath: localSource, to: remoteFile) { progress.record($0) }
            expect(progress.last, UInt64(payload.count), "업로드 진행률이 전체 크기에 도달")
            expectTrue(progress.count > 1, "업로드가 여러 청크로 분할됨 (\(progress.count)회 보고)")

            let listing = try await session.list(root)
            expect(listing.count, 1, "디렉터리 목록 항목 수")
            expect(listing.first?.name, "payload.bin", "목록의 파일 이름")
            expect(listing.first?.kind, .file, "목록의 파일 종류")
            expect(listing.first?.size, UInt64(payload.count), "목록의 파일 크기")
            expect(listing.first?.owner, server.user, "목록의 소유자")

            let localDestination = NSTemporaryDirectory() + "sftp-dst-\(UUID().uuidString).bin"
            defer { try? FileManager.default.removeItem(atPath: localDestination) }
            try await session.download(remotePath: remoteFile, to: localDestination) { _ in }
            let roundTripped = try Data(contentsOf: URL(fileURLWithPath: localDestination))
            expectTrue(roundTripped == payload, "다운로드한 내용이 원본과 바이트 단위로 일치")

            let renamed = PathUtil.join(root, "renamed.bin")
            try await session.rename(from: remoteFile, to: renamed)
            let nested = PathUtil.join(root, "nested")
            try await session.makeDirectory(nested)
            try await session.upload(localPath: localSource, to: PathUtil.join(nested, "inner.bin")) { _ in }

            let walked = try await session.walk(root).sorted { $0.relativePath < $1.relativePath }
            expect(walked.map(\.relativePath), ["nested", "nested/inner.bin", "renamed.bin"], "재귀 탐색 결과")
            expect(walked.first?.isDirectory, true, "탐색 결과의 디렉터리 판별")

            let isDirectory = await session.isDirectory(nested)
            expectTrue(isDirectory, "isDirectory 판별")


            await editIntegrationChecks(session: session, root: root)
            await shellIntegrationChecks(session: session, root: root)
            await conflictIntegrationChecks(session: session, root: root)

            if let megabytes = server.benchmarkMB {
                try await benchmark(session: session, root: root, megabytes: megabytes)
            }

            try await session.removeRecursively(root)
            let afterDelete = try? await session.list(root)
            expectTrue(afterDelete == nil, "재귀 삭제 후 디렉터리 없음")
        } catch {
            checks += 1
            failures += 1
            print("  ✗ SFTP 작업 실패\n      \(AppModel.describe(error))")
            try? await session.removeRecursively(root)
        }

        await session.disconnect()
    }

    /// Opens a real PTY on the same connection the file checks used, which is
    /// the whole point of the shell panel: one connection, two channels.
    @MainActor
    private static func shellIntegrationChecks(session: SFTPSession, root: String) async {
        section("원격 셸 (PTY)")
        let directory = PathUtil.join(root, "shell")
        let marker = "cwd-" + (directory as NSString).lastPathComponent
        do {
            try await session.makeDirectory(directory)
        } catch {
            checks += 1; failures += 1
            print("  ✗ 셸 검사용 디렉터리 생성 실패: \(AppModel.describe(error))")
            return
        }

        let handle = await session.clientHandle()
        let home = await session.homePath
        let shell = ShellSession(handle: handle, home: home, startIn: directory)

        guard await waitUntil(seconds: 15, { shell.state == .running }) else {
            checks += 1; failures += 1
            print("  ✗ 셸이 열리지 않음 (\(shell.state))")
            shell.close()
            return
        }
        expect(shell.state, .running, "같은 연결에 PTY 셸 채널 열기")

        let refreshed = Flag()
        shell.onCommandFinished = { refreshed.set() }
        // `touch cwd-<dir>` proves both that the command ran and that the shell
        // started in the folder the remote pane was showing.
        shell.run("touch \"cwd-$(basename \"$PWD\")\"")

        if await waitUntil(seconds: 20, { refreshed.isSet }) {
            expectTrue(true, "명령이 끝나면 목록 새로 고침 신호")
        } else {
            checks += 1; failures += 1
            print("  ✗ 명령이 끝났는데 새로 고침 신호가 오지 않음")
        }

        let names = ((try? await session.list(directory)) ?? []).map(\.name)
        expectTrue(names.contains(marker), "터미널로 보낸 명령이 서버에서 실행됨")
        expectTrue(names.contains(marker), "셸이 원격 창 경로에서 시작 (\(marker))")

        // Where the shell says it is, without anything having been typed into it.
        expect(shell.currentDirectory, directory, "셸 위치를 명령 없이 파악")

        // A half-typed line used to be run together with whatever the buttons
        // sent, e.g. `echo BROKENtouch guard-ok`.
        shell.send(source: shell.view, data: Array("echo BROKEN".utf8)[...])
        try? await Task.sleep(nanoseconds: 400_000_000)
        shell.run("touch guard-ok")
        var guarded = false
        for _ in 0..<40 {
            let files = ((try? await session.list(directory)) ?? []).map(\.name)
            if files.contains("guard-ok") { guarded = true; break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        expectTrue(guarded, "입력하다 만 줄이 있어도 명령이 그대로 실행됨")
        let leftovers = ((try? await session.list(directory)) ?? []).map(\.name)
        expectTrue(!leftovers.contains { $0.contains("BROKEN") }, "입력하다 만 줄이 명령에 섞이지 않음")

        let screen = shell.view.getTerminal().getBufferAsData()
        expectTrue(String(decoding: screen, as: UTF8.self).contains("basename"),
                   "셸 출력이 터미널 화면에 도달")

        shell.close()
        expectTrue(shell.state.isClosed, "세션 닫기")

        // Typing `exit` ends the shell from the far side. The panel has to
        // notice, because a session that still looks alive offers buttons that
        // write into a channel that is gone.
        let exited = ShellSession(handle: handle, home: home, startIn: directory)
        if await waitUntil(seconds: 15, { exited.state == .running }) {
            exited.run("exit")
            expectTrue(await waitUntil(seconds: 15, { exited.state.isClosed }),
                       "셸에서 exit 하면 세션도 끝난 것으로 표시")
            expectTrue(!exited.isAtPrompt, "끝난 세션에는 명령을 보내지 않음")
        } else {
            checks += 1; failures += 1
            print("  ✗ exit 검사용 셸이 열리지 않음 (\(exited.state))")
        }
        exited.close()

        // A command issued while the channel is still opening must survive the
        // wait rather than be dropped.
        let queued = ShellSession(handle: handle, home: home, startIn: directory, then: "touch queued-ok")
        let listed = await waitUntil(seconds: 20) {
            // `list` is async; poll a cached flag instead from the outer scope.
            queued.state.isClosed || queued.state == .running
        }
        expectTrue(listed, "채널이 열리는 동안 보낸 명령도 세션과 함께 시작")
        var appeared = false
        for _ in 0..<40 {
            let files = ((try? await session.list(directory)) ?? []).map(\.name)
            if files.contains("queued-ok") { appeared = true; break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        expectTrue(appeared, "열리는 중에 보낸 명령이 실행됨")
        queued.close()
    }

    private static func brightness(_ color: SwiftTerm.Color) -> Double {
        Double(max(color.red, max(color.green, color.blue))) / Double(UInt16.max)
    }

    /// Drives the real "already exists" sheet against the live server.
    @MainActor
    private static func conflictIntegrationChecks(session: SFTPSession, root: String) async {
        section("이름 충돌 확인 창")
        let directory = PathUtil.join(root, "conflict")
        let name = "clash.bin"
        let localPath = NSTemporaryDirectory() + "sftp-clash-\(UUID().uuidString).bin"
        defer { try? FileManager.default.removeItem(atPath: localPath) }

        let payload = Data(repeating: 7, count: 4096)
        do {
            try await session.makeDirectory(directory)
            try payload.write(to: URL(fileURLWithPath: localPath))
            // Something is already on the server under that name.
            try await session.upload(localPath: localPath, to: PathUtil.join(directory, name)) { _ in }
        } catch {
            checks += 1; failures += 1
            print("  ✗ 준비 실패: \(AppModel.describe(error))")
            return
        }

        let defaults = UserDefaults.standard
        let savedPolicy = defaults.object(forKey: PreferenceKey.conflictPolicy)
        defer {
            if let savedPolicy { defaults.set(savedPolicy, forKey: PreferenceKey.conflictPolicy) }
            else { defaults.removeObject(forKey: PreferenceKey.conflictPolicy) }
        }

        let model = AppModel()
        model.conflictPolicy = .ask
        model.session = session
        model.previewConnected(UUID(), name: "selftest")
        let local = FileItem(path: localPath, name: name, kind: .file,
                             size: UInt64(payload.count), modified: nil, permissions: nil)

        func remoteNames() async -> [String] {
            ((try? await session.list(directory)) ?? []).map(\.name).sorted()
        }

        // 1. Skipping leaves both sides alone.
        model.startTransfer(direction: .upload, items: [local], into: directory)
        guard await waitUntil(seconds: 10, { model.conflictRequest != nil }) else {
            checks += 1; failures += 1
            print("  ✗ 이름이 겹치는데 확인 창이 뜨지 않음")
            return
        }
        expect(model.conflictRequest?.name, name, "충돌한 이름을 보여줌")
        expect(model.conflictRequest?.remaining, 0, "뒤에 남은 충돌 개수")
        expect(model.conflictRequest?.renamedTo, "clash 2.bin", "바꿔 저장할 이름 제안")
        expect(model.conflictRequest?.existing?.size, UInt64(payload.count), "이미 있는 파일 크기를 함께 보여줌")

        model.conflictRequest?.respond(.skip, false)
        _ = await waitUntil(seconds: 5, { model.conflictRequest == nil })
        expect(await remoteNames(), [name], "건너뛰면 아무것도 올리지 않음")
        expectTrue(model.transfers.isEmpty, "건너뛴 항목은 큐에도 안 들어감")

        // 2. Renaming keeps both copies.
        model.startTransfer(direction: .upload, items: [local], into: directory)
        guard await waitUntil(seconds: 10, { model.conflictRequest != nil }) else {
            checks += 1; failures += 1
            print("  ✗ 두 번째 확인 창이 뜨지 않음")
            return
        }
        model.conflictRequest?.respond(.rename, false)
        _ = await waitUntil(seconds: 20) { model.transfers.first?.state == .completed }
        expect(await remoteNames(), ["clash 2.bin", name], "이름 바꿔 저장하면 둘 다 남음")

        // 3. Cancelling queues nothing at all.
        model.transfers.removeAll()
        model.startTransfer(direction: .upload, items: [local], into: directory)
        guard await waitUntil(seconds: 10, { model.conflictRequest != nil }) else {
            checks += 1; failures += 1
            print("  ✗ 세 번째 확인 창이 뜨지 않음")
            return
        }
        model.conflictRequest?.respond(.cancel, false)
        _ = await waitUntil(seconds: 5, { model.conflictRequest == nil })
        expectTrue(model.transfers.isEmpty, "취소하면 큐가 비어 있음")

        // 4. A policy other than "ask" never opens the sheet.
        model.conflictPolicy = .skip
        model.startTransfer(direction: .upload, items: [local], into: directory)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        expectTrue(model.conflictRequest == nil, "‘물어보기’가 아니면 창을 띄우지 않음")
        expect(await remoteNames(), ["clash 2.bin", name], "건너뛰기 정책은 그대로 동작")
    }

    /// Polls `condition` on the main actor until it holds or the deadline passes.
    @MainActor
    private static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// Exercises the whole host-key path: unknown → trusted → changed.
    private static func hostKeyChecks(_ server: ServerArguments, connection: Connection) async -> String {
        section("호스트 키 검증")
        let directory = NSTemporaryDirectory() + "kh-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/known_hosts"
        FileManager.default.createFile(atPath: path, contents: Data())

        // 1. Empty known_hosts: the connection must be refused, not accepted.
        var discovered: HostKeyError?
        do {
            let session = try await SFTPSession.connect(connection, secret: server.passphrase, knownHostsPath: path)
            await session.disconnect()
            checks += 1; failures += 1
            print("  ✗ 알 수 없는 호스트 키인데도 연결됨")
        } catch let error as HostKeyError {
            discovered = error
            expect(error.kind, .unknown, "모르는 호스트는 거부")
            expectTrue(error.fingerprint.hasPrefix("SHA256:"), "지문 형식 (\(error.fingerprint))")
        } catch {
            checks += 1; failures += 1
            print("  ✗ 예상과 다른 오류: \(AppModel.describe(error))")
        }
        guard let discovered else { return path }

        // 2. Cross-check the fingerprint against OpenSSH's own tools.
        let reference = opensshFingerprints(host: server.host, port: server.port)
        if reference.isEmpty {
            note("ssh-keyscan을 쓸 수 없어 지문 대조는 건너뜀")
        } else {
            expectTrue(reference.contains(discovered.fingerprint), "지문이 ssh-keygen 결과와 일치")
        }

        // 3. Trusting the key lets the connection through.
        try? KnownHosts.append(line: discovered.knownHostsLine, path: path)
        do {
            let session = try await SFTPSession.connect(connection, secret: server.passphrase, knownHostsPath: path)
            await session.disconnect()
            checks += 1
            print("  ✓ known_hosts에 등록 후 연결 성공")
        } catch {
            checks += 1; failures += 1
            print("  ✗ 등록 후에도 연결 실패: \(AppModel.describe(error))")
        }

        // 4. A different key of the same type must be reported as changed.
        let decoy = directory + "/decoy"
        FileManager.default.createFile(atPath: decoy, contents: Data())
        if generateKey(at: directory + "/other", type: "ed25519", passphrase: ""),
           let otherPub = try? String(contentsOfFile: directory + "/other.pub", encoding: .utf8) {
            let fields = otherPub.split(separator: " ")
            let bogus = "\(KnownHosts.hostPattern(host: server.host, port: server.port)) \(fields[0]) \(fields[1])"
            try? bogus.write(toFile: decoy, atomically: true, encoding: .utf8)
            do {
                let session = try await SFTPSession.connect(connection, secret: server.passphrase, knownHostsPath: decoy)
                await session.disconnect()
                checks += 1; failures += 1
                print("  ✗ 키가 바뀌었는데도 연결됨")
            } catch let error as HostKeyError {
                expect(error.kind, .changed, "키가 바뀌면 경고")
                expect(error.knownFingerprints.count, 1, "이전 지문을 함께 보고")
            } catch {
                checks += 1; failures += 1
                print("  ✗ 예상과 다른 오류: \(AppModel.describe(error))")
            }
        } else {
            note("대조용 키 생성 실패 — 변경 감지 검사는 건너뜀")
        }

        return path
    }

    /// Drives the real watcher: a scratch file is saved, and the change has to
    /// reach the server on its own.
    private static func editIntegrationChecks(session: SFTPSession, root: String) async {
        section("원격 파일 편집 왕복")
        let remotePath = PathUtil.join(root, "app.conf")
        let scratch = NSTemporaryDirectory() + "edit-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        let localPath = scratch + "/app.conf"
        defer { try? FileManager.default.removeItem(atPath: scratch) }

        do {
            try "original\n".write(toFile: localPath, atomically: true, encoding: .utf8)
            try await session.upload(localPath: localPath, to: remotePath) { _ in }
        } catch {
            checks += 1; failures += 1
            print("  ✗ 편집 대상 파일 준비 실패: \(AppModel.describe(error))")
            return
        }

        let model = await MainActor.run { AppModel() }
        await MainActor.run {
            model.session = session
            var edit = RemoteEdit(
                remotePath: remotePath,
                localPath: localPath,
                name: "app.conf",
                scratchDirectory: scratch
            )
            edit.lastSeen = FileSignature.read(localPath)
            edit.uploaded = edit.lastSeen
            edit.status = .watching
            model.edits = [edit]
            model.startEditWatcher()
        }

        // Stand in for the editor writing the file.
        try? "edited by the editor\n".write(toFile: localPath, atomically: true, encoding: .utf8)

        var uploaded = false
        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if await MainActor.run(body: { model.edits.first?.uploadCount ?? 0 }) > 0 {
                uploaded = true
                break
            }
        }
        expectTrue(uploaded, "저장을 감지해 자동으로 업로드")

        let verify = scratch + "/verify"
        try? await session.download(remotePath: remotePath, to: verify) { _ in }
        let content = (try? String(contentsOfFile: verify, encoding: .utf8)) ?? ""
        expect(content, "edited by the editor\n", "서버 파일이 편집 결과로 갱신됨")

        let status = await MainActor.run { model.edits.first?.status }
        expect(status, .watching, "업로드 후 다시 감시 상태")

        await MainActor.run { model.stopAllEditing() }
        let cleaned = await MainActor.run { model.edits.isEmpty }
        expectTrue(cleaned && !FileManager.default.fileExists(atPath: scratch), "편집 종료 시 임시 파일 정리")
    }

    /// A flag the async checks can set and the main run loop can watch.
    /// A mutable cell for values a callback writes on the main actor.
    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// `ssh-keyscan` + `ssh-keygen -lf`, i.e. the fingerprints OpenSSH itself reports.
    private static func opensshFingerprints(host: String, port: Int) -> [String] {
        let scanned = NSTemporaryDirectory() + "scan-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scanned) }
        guard run("/usr/bin/ssh-keyscan", ["-p", String(port), host], toFile: scanned) else { return [] }
        guard let listing = runCapturing("/usr/bin/ssh-keygen", ["-lf", scanned]) else { return [] }
        return listing
            .split(separator: "\n")
            .compactMap { line in
                line.split(separator: " ").first(where: { $0.hasPrefix("SHA256:") }).map(String.init)
            }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String], toFile path: String) -> Bool {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else { return false }
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func runCapturing(_ tool: String, _ arguments: [String]) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func benchmark(session: SFTPSession, root: String, megabytes: Int) async throws {
        section("전송 속도 (\(megabytes) MB)")
        let bytes = megabytes * 1024 * 1024
        let source = NSTemporaryDirectory() + "sftp-bench-\(UUID().uuidString).bin"
        let destination = NSTemporaryDirectory() + "sftp-bench-out-\(UUID().uuidString).bin"
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        // Incompressible-ish filler so nothing downstream can cheat with compression.
        var filler = Data(count: bytes)
        filler.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt64.self).baseAddress else { return }
            var seed: UInt64 = 0x2545F4914F6CDD1D
            for index in 0..<(raw.count / 8) {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                base[index] = seed
            }
        }
        try filler.write(to: URL(fileURLWithPath: source))

        let remote = PathUtil.join(root, "bench.bin")
        let uploadStart = Date()
        try await session.upload(localPath: source, to: remote) { _ in }
        let uploadSeconds = Date().timeIntervalSince(uploadStart)

        let downloadStart = Date()
        try await session.download(remotePath: remote, to: destination) { _ in }
        let downloadSeconds = Date().timeIntervalSince(downloadStart)

        try await session.removeFile(remote)

        func rate(_ seconds: TimeInterval) -> String {
            String(format: "%.1f MB/s (%.2fs)", Double(megabytes) / seconds, seconds)
        }
        print("  · 업로드   \(rate(uploadSeconds))")
        print("  · 다운로드 \(rate(downloadSeconds))")

        let roundTripped = try Data(contentsOf: URL(fileURLWithPath: destination))
        expectTrue(roundTripped == filler, "\(megabytes) MB 왕복 후 내용 일치")
    }

    /// Progress callbacks arrive off the main actor, so the counters are locked.
    private final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [UInt64] = []

        func record(_ bytes: UInt64) {
            lock.lock(); values.append(bytes); lock.unlock()
        }

        var last: UInt64? {
            lock.lock(); defer { lock.unlock() }
            return values.last
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return values.count
        }
    }
}
