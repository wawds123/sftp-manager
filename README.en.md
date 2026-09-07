<div align="center">

<img src="docs/icon.png" width="120" alt="SFTP Manager">

# SFTP Manager

**A native SFTP file transfer app for macOS**
This Mac on the left, your server on the right. Move files between the two.

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.x-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Self-test](https://img.shields.io/badge/self--test-262%20passing-brightgreen)
![UI](https://img.shields.io/badge/UI-English%20·%20한국어-8A2BE2)

**English** · [한국어](README.md)

[**Build it yourself →**](#build) · Command Line Tools only, no Xcode

</div>

---

## Contents

| | |
|---|---|
| [✨ Features](#features) | [⌨️ Shortcuts](#shortcuts) |
| [📦 Dependencies](#dependencies) | [🧰 Building it yourself](#build) |
| [✅ Verification](#verification) | [⚡ Transfer performance](#performance) |
| [🛡️ Security design](#security-design) | [⚠️ Known limitations](#limitations) |
| [🗺️ Layout](#layout) | [📄 License](#license) |

---

<a id="features"></a>

## ✨ Features

### 🗂️ Two-pane browser

- **Split view** — local on the left, remote on the right. Each pane has back / forward / parent / home,
  direct path entry, and a name filter
- **Columns** — name · size · modified · owner · permissions
  <sup>The remote owner's name is read from the `ls -l` line the server sends with each entry (SFTP itself
  only guarantees a numeric uid). Failing that it shows the uid, and failing that, `—`.</sup>
- **Sorting** — by any column, folders first. Click a header to sort, click again to reverse
- **Right-click empty space** — a menu for the current folder: new folder, refresh, open in Finder,
  upload/download the selection, copy path, go up/home, toggle hidden files, select all
- **File operations** — new folder, rename, delete (recursive on the remote side), copy path, show in Finder

### ⇅ Transfers

- **How to send** — the buttons (`⌘→` / `⌘←`), dragging between the panes, or dragging straight from
  Finder onto the remote pane
- **Whole folders** — the subtree is mirrored as-is
- **Transfer queue** — progress and speed, cancel one or all, retry what failed
- **Pipelining** — 64 requests in flight and a 2 MB SSH channel window, to hide round-trip latency
  → [Transfer performance](#performance)
- **When a name clashes** — the default is **Ask**. Both files' size and date are shown side by side:

  | Choice | Result |
  |---|---|
  | Overwrite | Replaces the existing file |
  | Keep Both | Saves it as `report 2.pdf` |
  | Skip | Passes over that one item |
  | Cancel | Stops without queueing anything |

  If several names clash, `Apply to the remaining N` answers the rest in one go.
  To always do the same thing, pin a policy from the toolbar or Settings.

- **Double-click** — a local file **uploads by default**. To switch it to `Open with Default App`, use the
  `…` menu in the local pane or the menu bar's `Transfers › Double-click a local file`. Folders always
  navigate regardless, and both actions stay in the right-click menu.

### 📝 Editing remote files

Right-click a remote file → `Open in Editor`. A scratch copy is downloaded and handed to your default
editor, and **every save uploads it again.** Open files are managed from the `Editing` menu in the
toolbar; stopping deletes the scratch copy.

### 💻 Terminal

The `Terminal` toolbar button or `View › Terminal` (`⌥⌘S`) opens a shell in the bottom panel.
It is a **second channel on the very SSH connection the file panes use**, which means:

- no second password prompt, and no second host key check
- the server does not see a second login
- it closes with the connection

It starts in the folder the remote pane is showing, and reloads the remote listing once a command
finishes and the output falls quiet.

<details>
<summary><b>Keeping the two in sync — and what this deliberately does not do</b></summary>

<br>

Two buttons line up the pane and the shell.

| Button | What it does |
|---|---|
| `Move Terminal to Pane` | `cd`s the shell to the folder the remote pane is showing |
| `Move Pane to Terminal` | Moves the remote pane to where the shell is |

The second one only uses a location the shell **volunteered** — an OSC 7 report, or failing that the
`user@host:path` in its window title. No command is ever typed into your terminal to find out. If your
shell sends OSC 7, the remote pane follows every `cd` on its own.

When the app does send something to the shell (the `cd` on startup, the buttons above) it **first clears
whatever you had half-typed.** Otherwise it would be prefixed onto the command and run as one line. The
cleared text goes to the shell's kill ring, so `Ctrl-Y` brings it back — and while a full-screen program
like `vim` or `less` owns the screen, nothing is sent at all and the app says so.

Typing `exit` ends the shell but leaves the screen in place; `Reopen` starts a new one. Switching tabs
never opens a channel behind your back.

The terminal follows the app theme. Switch to dark and an already-open shell changes its background and
text colour with it.

</details>

### 🌐 Language and help

- **English / Korean** — picked on the first Settings tab. **It changes immediately; no relaunch.**
  With nothing stored yet, a first launch follows the language macOS is set to.
- **Help (`⌘?`)** — `Help › SFTP Manager Help`. Seven topics in both languages: getting started,
  browsing, transfers, editing remote files, terminal, shortcuts, and security.

### ⚙️ Settings (`⌘,`)

| Tab | Contents |
|---|---|
| General | Language, theme (system / light / dark), password policy |
| File Lists | Hidden files, default sort column and direction, local double-click action |
| Transfers | Default answer to a name clash, open the queue at launch, notify on finish, concurrent requests |
| Advanced | Edit polling interval, known_hosts and server-list paths, scratch cleanup, reset settings |
| About | Author, version, what it is built with |

The bottom panel is shared by the `Transfers` and `Terminal` tabs. Drag the handle to resize it, or
double-click to fit the contents. The height you choose is remembered.

<a id="security"></a>

### 🔐 Security

- **Passwords are never stored** — you enter one on each connection and it stays in memory only. Nothing
  is written anywhere, Keychain included. For a private key only the **path** is saved, and you are asked
  for a passphrase only when the key file is actually encrypted (read from the cipher field in the OpenSSH
  key header). Credentials an older version put in the Keychain are deleted once, on first launch.
- **Host key verification** — servers are checked against `~/.ssh/known_hosts`, the same file `ssh` uses.
  A new server shows its SHA256 fingerprint for approval, a changed key raises a warning next to the old
  fingerprint, and a `@revoked` key is refused. This happens during key exchange, so **nothing is sent to
  the server before you approve.**
- **Server profiles** — name · host · port · user · start folders
- **Authentication** — password, ED25519 private key, RSA private key

The defensive design is spelled out under [🛡️ Security design](#security-design).

---

<a id="shortcuts"></a>

## ⌨️ Shortcuts

| | | | |
|---|---|---|---|
| `⌘N` | New connection | `⌘R` | Refresh the clicked pane |
| `⌘,` | Settings | `⇧⌘R` | Refresh both panes |
| `⌘?` | Help | `⌘↑` | Local parent folder |
| `⌘→` | Upload | `⇧⌘↑` | Remote parent folder |
| `⌘←` | Download | `⌥⌘T` | Show/hide the transfer list |
| | | `⌥⌘S` | Show/hide the terminal |

`⌘R` refreshes **only the pane you last clicked** — the highlighted border shows which one.

---

<a id="dependencies"></a>

## 📦 Dependencies

| Package | License | Used for |
|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH connection, SFTP, PTY channel |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | ANSI/vt100 emulation in the terminal panel |

Everything else (swift-nio, swift-crypto, swift-log, swift-collections, BigInt and so on) is pulled in by
those two.

> [!NOTE]
> The SSH transport does not come from `apple/swift-nio-ssh` but from the
> [`Wellz26/swift-nio-ssh`](https://github.com/Wellz26/swift-nio-ssh) fork. That is not this app's choice —
> **Citadel 0.12.1 declares it in its own `Package.swift`** (the fork adds certificate authentication and
> Mac Catalyst support). It is worth stating plainly in an SSH client. The exact version and commit are
> pinned in `Package.resolved`.

---

<a id="build"></a>

## 🧰 Building it yourself

**Building from source is the intended way to install this.** There is a
[release build](https://github.com/wawds123/sftp-manager/releases) for convenience, but it is ad-hoc
signed rather than notarized, so macOS quarantines it on download and you have to clear that by hand.
Building takes one command and produces a bundle macOS is happy with.

### What you need

| | |
|---|---|
| macOS | 15 or later — the PTY API the remote shell uses starts there |
| Swift | 6.x, which ships with the Command Line Tools. **Xcode is not required** |

If `swift --version` does not answer, install the Command Line Tools:

```bash
xcode-select --install
```

### Build and run

```bash
git clone https://github.com/wawds123/sftp-manager.git
cd sftp-manager

./Scripts/make_icon.sh     # draws Resources/AppIcon.icns (once)
./Scripts/make_app.sh      # produces build/SFTPManager.app
open build/SFTPManager.app
```

The first build fetches the dependencies and compiles them, so give it a few minutes; later builds are
incremental. `.build/` grows to a few GB and is ignored by git — delete it any time to reclaim the space.

To move it out of the source tree: `mv build/SFTPManager.app /Applications/`.

Because you signed it locally, there is no quarantine flag and nothing to clear.

### Options

```bash
./Scripts/make_app.sh --universal   # arm64 + x86_64 in one bundle
./Scripts/make_app.sh debug         # debug build, symbols kept
```

A release build is stripped before signing, which roughly halves it (18.8 MB → 9.0 MB per slice).
`--universal` builds the second architecture with an explicit target triple and joins the slices with
`lipo`, because `swift build --arch a --arch b` needs Xcode's build system.

### Working on it

`swift run SFTPManager` runs straight from the build directory, which is quicker for iterating. Prefer
the bundle from `make_app.sh` for actual use: it gets a Dock icon and a stable code-signing identity.

See [✅ Verification](#verification) for the self-test, the translation check, and the offscreen
snapshot renderer — all of which run without Xcode.

---

<a id="verification"></a>

## ✅ Verification

There is no XCTest in a Command Line Tools install, so this repo uses a **runnable self-test** instead.

```bash
# pure logic — path handling, sorting/filtering/history, shell logic, translations, drag payloads
swift run SFTPManager --selftest

# against a real server, all the way through an SFTP round trip
#   upload → list → download (compared byte for byte) → rename → recursive walk → recursive delete
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519

# throughput (transfers the given size each way and prints MB/s)
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --bench-mb 64

# a passphrase-protected key
swift run SFTPManager --selftest \
    --host 127.0.0.1 --port 2222 --user "$USER" --key ~/.ssh/id_ed25519 --passphrase '...'
```

**Missing translations are caught statically too** — the check fails on any Korean string still hard-coded
into a view or a model.

```bash
./Scripts/check_l10n.sh
```

`--selftest` walks everything enumerable (enum labels, the whole help book); this script covers the
remaining `L` entries by searching the source.

<details>
<summary><b>Checking what the UI renders — offscreen snapshots</b> (no screen-recording permission needed)</summary>

<br>

```bash
swift run SFTPManager --snapshot /tmp/ui.png                       # the whole window
swift run SFTPManager --snapshot /tmp/sidebar.png --view sidebar
swift run SFTPManager --snapshot /tmp/settings.png --view settings --tab advanced

# fixed sample data — reads neither your home directory nor your saved servers
swift run SFTPManager --snapshot /tmp/demo.png --demo

# the help and about windows, in a chosen language and topic
swift run SFTPManager --snapshot /tmp/help.png  --view help --lang en --topic terminal
swift run SFTPManager --snapshot /tmp/about.png --view about --lang ko

# transfer list layout (N sample rows, given window size)
swift run SFTPManager --snapshot /tmp/queue.png --view transfers --rows 12 --size 1100x620
```

Snapshots are drawn into a fixed-size container and clipped — the same condition as a real window, so
layout that overflows shows up as overflow.

> A `NavigationSplitView` sidebar lives on a vibrancy layer and comes out empty in a whole-window
> snapshot. Use `--view sidebar` to check it.

</details>

---

<a id="performance"></a>

## ⚡ Transfer performance

Transfers work the way the OpenSSH client's do.

| Condition | Before | Now |
|---|---:|---:|
| 40 ms RTT · 8 MB upload | 0.7 MB/s | **24.5 MB/s** |
| 40 ms RTT · 8 MB download | 0.7 MB/s | **16.0 MB/s** |
| Loopback · 64 MB upload | 237.8 MB/s | **473.7 MB/s** |
| Loopback · 64 MB download | 248.6 MB/s | **344.6 MB/s** |

<sup>Under the same conditions <code>scp</code> manages 8.8 MB/s and 202.5 MB/s respectively</sup>

<details>
<summary><b>The two reasons it used to be slow</b></summary>

<br>

**1. Requests went out one at a time, each waiting for its reply.**
Waiting for a round trip every 32 KB caps the rate at `32 KB / RTT` (0.8 MB/s at 40 ms RTT).
Now 64 requests are in flight and replies are handled as they land.

**2. The SSH channel's receive window was 128 KB.**
swift-nio-ssh takes a child channel's receive window from `maximumPacketSize` (128 KB by default), so
however much was requested, the server could only send 128 KB per round trip. It is raised to 2 MB, the
same as OpenSSH. **That is why downloads were so much slower than uploads.**

Progress callbacks are also coalesced into 100 ms buckets before hopping to the main actor — thousands of
actor hops per second cost more than the transfer did.

</details>

---

<a id="security-design"></a>

## 🛡️ Security design

> [!IMPORTANT]
> Built on the assumption that **nothing the server sends can be trusted.** A filename is a value the
> server chooses.

- **Paths handed to the shell are always quoted** — a `cd` sent to the terminal is wrapped in single
  quotes, with any `'` escaped the POSIX way by closing and reopening (`'\''`). A server can name a file
  `$(...)` or `;rm -rf ~` and it will not become a command.
- **A name from the server is treated as one component** — names containing `/`, `.`, `..` or a NUL byte
  are not legal directory entries, so they are dropped from the listing.
- **A download can never land outside the target folder** — even when a whole folder is transferred, every
  path is checked to be inside the folder you picked, and anything that escapes is **left in the queue as
  a failure** rather than silently skipped. The scratch copy made when opening a remote file in an editor
  goes through the same check.
- **A name field is not a path** — new folder and rename reject any value containing `/`.
- Host key verification and the never-store-passwords policy are described under [🔐 Security](#security).

---

<a id="limitations"></a>

## ⚠️ Known limitations

- **RSA keys** — the backend (Citadel) only signs with the legacy `ssh-rsa` algorithm, which OpenSSH 8.8
  and later reject by default, so **ED25519 keys are recommended**. If you must use RSA, the server needs
  `PubkeyAcceptedAlgorithms +ssh-rsa` in `sshd_config`. The app detects this case and says so in the error.
- **Encrypted private keys** — passphrases are handled for ED25519 and RSA OpenSSH keys only. ECDSA keys
  are not supported.
- **Local-to-local copying** is not supported.
- **What the language switch covers** — every screen the app draws itself changes immediately, but the menu
  items macOS supplies (`Quit`, `Hide`, `Services`, and the Edit and Window menus) follow the system
  language. That is the cost of using an in-app string table instead of `.lproj` bundles — in exchange,
  the switch needs no relaunch.
- **Re-entering the password** — nothing is stored, so you type it on every connection. It is not cached
  during a session either.
- **The remote shell** — if the server blocks shells (`ForceCommand internal-sftp` and the like) the
  terminal will not open. `Move Pane to Terminal` cannot work where the shell never announces its location
  (a minimal prompt with no title and no OSC 7), and it explains why. SSH does not report that a command
  finished, so 0.7 seconds of silence is taken to mean it has.
- **The queue transfers one file at a time.** A single file moves at the rates above, but a folder full of
  very small files is still slow, because each one needs its own open/close round trip.

---

<a id="layout"></a>

## 🗺️ Layout

```
Sources/SFTPManager/
├─ main.swift                 entry point — GUI / --selftest / --snapshot
├─ SFTPManagerApp.swift       App definition, menu commands, help and about windows, AppDelegate
├─ SelfTest.swift             headless verification
├─ Snapshot.swift             offscreen UI rendering
├─ Model/
│  ├─ FileItem.swift          the entry both panes share + path utilities (containment checks)
│  ├─ FileGlyph.swift         icon and tint tables by extension, name and folder
│  ├─ Localization.swift      the English/Korean string table and the language switch
│  └─ Connection.swift        server profiles + on-disk storage (with schema migration)
├─ Core/
│  ├─ SFTPSession.swift       the Citadel-backed SSH/SFTP actor (listing, transfers, recursive delete, walk)
│  ├─ ShellSession.swift      the PTY shell on that same connection (SwiftTerm wiring, idle-based refresh)
│  ├─ LocalFileSystem.swift   local file operations
│  ├─ KnownHosts.swift        known_hosts parsing, matching (hashed entries included), fingerprints, writing
│  ├─ HostKeyValidator.swift  host key verification during key exchange, and why one is refused
│  ├─ OpenSSHKeyInspector.swift  reads the key header to tell whether a private key is encrypted
│  ├─ Keychain.swift          clears credentials an older version stored (nothing is stored now)
│  ├─ RemoteEdit.swift        remote files open for editing, and the save-detection rule
│  ├─ PaneState.swift         one pane's state (path, listing, selection, sorting, history)
│  ├─ Transfer.swift          the transfer item model
│  ├─ Preferences.swift       reading and writing settings, applying the theme
│  ├─ AppModel.swift          app-wide state, connection management, file operations
│  ├─ AppModel+Transfers.swift  queue expansion, progress, conflict policy
│  └─ AppModel+Editing.swift  download, watch, automatic re-upload
└─ Views/                     SwiftUI screens
   ├─ HelpBook.swift          help content (both languages, as data only)
   ├─ HelpView.swift          the help window
   └─ AboutView.swift         author, version, what it is built with

Scripts/
├─ make_app.sh                assembles the .app bundle + ad-hoc signature
├─ check_l10n.sh              finds hard-coded Korean strings
├─ make_icon.sh               generates the icon
└─ DrawIcon.swift             CoreGraphics icon drawing
```

---

<a id="license"></a>

## 📄 License

MIT — see [LICENSE](LICENSE).

<a id="author"></a>

## 👤 Author

**jackson** &lt;wawds123@gmail.com&gt;

In the app: `SFTP Manager › About SFTP Manager`, or `Settings › About`.
