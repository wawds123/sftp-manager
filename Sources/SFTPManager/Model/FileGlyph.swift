import SwiftUI

/// Picks the icon and tint for one row in the file lists.
///
/// Kept out of the view so `--selftest` can check that every symbol actually
/// resolves: a misspelled SF Symbol renders as an empty gap, which is easy to
/// miss by eye and impossible to notice on a machine that has the symbol.
enum FileGlyph {
    struct Glyph: Equatable {
        let symbol: String
        let tint: Color
    }

    // MARK: Fallbacks

    static let folder = Glyph(symbol: "folder.fill", tint: .accentColor)
    static let file = Glyph(symbol: "doc", tint: .secondary)
    static let symlink = Glyph(symbol: "arrow.turn.up.right", tint: .teal)
    static let unknown = Glyph(symbol: "questionmark.square", tint: .secondary)

    /// Extension-less names that still say exactly what they are.
    static let names: [String: Glyph] = [
        "makefile": Glyph(symbol: "hammer.fill", tint: .brown),
        "dockerfile": Glyph(symbol: "shippingbox.fill", tint: .cyan),
        "readme": Glyph(symbol: "book.fill", tint: .blue),
        "license": Glyph(symbol: "checkmark.seal.fill", tint: .gray),
        ".gitignore": Glyph(symbol: "arrow.triangle.branch", tint: .orange),
        ".env": Glyph(symbol: "lock.doc.fill", tint: .yellow),
        ".bashrc": Glyph(symbol: "terminal.fill", tint: .green),
        ".bash_profile": Glyph(symbol: "terminal.fill", tint: .green),
        ".zshrc": Glyph(symbol: "terminal.fill", tint: .green),
        ".profile": Glyph(symbol: "terminal.fill", tint: .green),
        ".vimrc": Glyph(symbol: "chevron.left.forwardslash.chevron.right", tint: .green),
    ]

    static let extensions: [String: Glyph] = {
        var table: [String: Glyph] = [:]
        func add(_ glyph: Glyph, _ exts: [String]) {
            for ext in exts { table[ext] = glyph }
        }
        add(Glyph(symbol: "photo", tint: .orange),
            ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tiff", "ico"])
        add(Glyph(symbol: "scribble.variable", tint: .orange), ["svg", "ai", "eps"])
        add(Glyph(symbol: "film", tint: .purple), ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv"])
        add(Glyph(symbol: "music.note", tint: .pink), ["mp3", "wav", "flac", "aac", "m4a", "ogg", "opus"])
        add(Glyph(symbol: "doc.zipper", tint: .brown),
            ["zip", "gz", "tgz", "tar", "bz2", "xz", "7z", "rar", "zst"])
        add(Glyph(symbol: "opticaldisc", tint: .gray), ["iso", "dmg", "img"])
        add(Glyph(symbol: "shippingbox.fill", tint: .brown), ["deb", "rpm", "pkg", "apk", "jar", "war", "whl"])
        add(Glyph(symbol: "doc.richtext", tint: .red), ["pdf"])
        add(Glyph(symbol: "doc.text", tint: .secondary), ["txt", "rtf", "doc", "docx", "odt", "pages"])
        add(Glyph(symbol: "book.fill", tint: .blue), ["md", "markdown", "rst", "adoc", "epub"])
        add(Glyph(symbol: "tablecells", tint: .green), ["csv", "tsv", "xls", "xlsx", "ods", "numbers"])
        add(Glyph(symbol: "rectangle.on.rectangle", tint: .orange), ["ppt", "pptx", "odp", "key"])
        add(Glyph(symbol: "list.bullet.rectangle", tint: .gray), ["log", "out", "err"])
        add(Glyph(symbol: "curlybraces", tint: .teal),
            ["json", "yml", "yaml", "toml", "xml", "plist", "ini", "conf", "cfg", "properties", "env"])
        add(Glyph(symbol: "chevron.left.forwardslash.chevron.right", tint: .blue),
            ["swift", "py", "js", "mjs", "ts", "tsx", "jsx", "go", "rs", "rb", "php", "pl", "lua",
             "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "cs", "scala", "dart", "r"])
        add(Glyph(symbol: "terminal.fill", tint: .green), ["sh", "bash", "zsh", "fish", "bat", "ps1", "command"])
        add(Glyph(symbol: "globe", tint: .cyan), ["html", "htm", "vue", "svelte"])
        add(Glyph(symbol: "paintbrush.fill", tint: .cyan), ["css", "scss", "sass", "less"])
        add(Glyph(symbol: "cylinder.fill", tint: .indigo), ["sql", "db", "sqlite", "sqlite3", "dump"])
        add(Glyph(symbol: "key.fill", tint: .yellow), ["pem", "key", "crt", "cer", "p12", "pfx", "pub", "asc", "gpg"])
        // Not "textformat": that symbol is localised, so it draws Korean
        // glyphs in this app and reads as anything but a font file.
        add(Glyph(symbol: "f.cursive", tint: .gray), ["ttf", "otf", "woff", "woff2", "eot"])
        add(Glyph(symbol: "gearshape.fill", tint: .gray),
            ["service", "socket", "timer", "target", "mount", "rules"])
        add(Glyph(symbol: "cpu", tint: .gray), ["so", "dylib", "dll", "o", "a", "bin", "exe", "wasm"])
        return table
    }()

    static func glyph(for item: FileItem) -> Glyph {
        switch item.kind {
        case .directory:
            // A folder is drawn as a folder, whatever it is called. Naming one
            // `music` or `log` does not make it less of a place to go into, and
            // a row of look-alike glyphs is harder to scan than one shape that
            // always means "you can open this".
            return folder
        case .symlink:
            return symlink
        case .other:
            return unknown
        case .file:
            let lowercased = item.name.lowercased()
            if let byExtension = extensions[item.ext] { return byExtension }
            // "Makefile", "README.md" already matched above; this catches the
            // extension-less ones and dotfiles, where `ext` is empty.
            if let byName = names[lowercased] { return byName }
            if let stem = lowercased.split(separator: ".").first,
               let byStem = names[String(stem)] {
                return byStem
            }
            return file
        }
    }

    /// Every symbol the table can produce, for the availability check.
    static var allSymbols: [String] {
        var symbols = [folder, file, symlink, unknown].map(\.symbol)
        symbols += names.values.map(\.symbol)
        symbols += extensions.values.map(\.symbol)
        return Array(Set(symbols)).sorted()
    }
}
