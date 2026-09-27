import Foundation

/// Word（.docx）台本。Web 版の Scenario_Template（deerstudio 配布の脚本テンプレート）をそのまま同梱し、
/// document.xml / core.xml / header・footer を差し替えて ZIP に固める（swScenarioDownloadDocx.php の移植）。
public enum DocxExporter {

    public enum Template: String, CaseIterable, Identifiable, Sendable {
        case a4PortraitVertical = "A4TP"     // A4縦 縦書き
        case a4PortraitHorizontal = "A4YP"   // A4縦 横書き
        case a4LandscapeVertical = "A4TL"    // A4横 縦書き
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .a4PortraitVertical: return "A4縦 縦書き"
            case .a4PortraitHorizontal: return "A4縦 横書き"
            case .a4LandscapeVertical: return "A4横 縦書き"
            }
        }
    }

    /// 本文ページの書き込み欄（Word テンプレートの台詞の上の余白と区切りの罫）。
    /// 縦書きは段の上 / 下、横書きは行頭側（左）/ 行末側（右）に取る
    public enum MemoArea: String, CaseIterable, Identifiable, Sendable {
        case none, top, bottom
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .none: return "なし"
            case .top: return "上"
            case .bottom: return "下"
            }
        }
    }

    /// 表紙に入れる情報（Web 版ダウンロード画面の入力欄）
    public struct CoverInfo: Sendable {
        public var writerName: String
        public var writerId: String      // 脚本協会登録番号など
        public var version: String       // 草稿バージョンなど
        public var date: Date?           // 和暦で出す
        public var address: String
        public var phone: String
        public var email: String
        public init(writerName: String = "", writerId: String = "", version: String = "", date: Date? = Date(),
                    address: String = "", phone: String = "", email: String = "") {
            self.writerName = writerName; self.writerId = writerId; self.version = version; self.date = date
            self.address = address; self.phone = phone; self.email = email
        }
    }

    public struct ExportError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    static var resourceRoot: URL {
        get throws {
            guard let base = Bundle.module.resourceURL?.appendingPathComponent("Resources", isDirectory: true),
                  FileManager.default.fileExists(atPath: base.path) else {
                throw ExportError(message: "テンプレートの資源が見つかりません")
            }
            return base
        }
    }

    static func snippet(_ template: Template, _ name: String) throws -> String {
        let url = try resourceRoot.appendingPathComponent("docx/\(template.rawValue)/snippets/\(name).xml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 本文用: XML エスケープし、改行を <w:br/> にする（<w:t> の中に置く前提）
    static func wt(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { TextFormat.xmlEscape(String($0)) }.joined(separator: "</w:t><w:br/><w:t xml:space=\"preserve\">")
    }

    static func fill(_ snippet: String, _ values: [String: String]) -> String {
        var s = snippet
        for (k, v) in values { s = s.replacingOccurrences(of: "{{\(k)}}", with: v) }
        // 値を入れた <w:t> は空白を保持する
        return s.replacingOccurrences(of: "<w:t>", with: "<w:t xml:space=\"preserve\">")
    }

    public static func make(_ doc: ScenarioDocument, template: Template, cover: CoverInfo, userName: String, memo: MemoArea = .top) throws -> Data {
        let root = try resourceRoot.appendingPathComponent("docx/\(template.rawValue)/template", isDirectory: true)
        let fm = FileManager.default
        // 相対パスで列挙する（/tmp と /private/tmp のようにシンボリックリンクで絶対パスが食い違っても ZIP 内のパスが崩れない）
        guard let en = fm.enumerator(atPath: root.path) else { throw ExportError(message: "テンプレートが読めません") }
        var files: [(String, Data)] = []
        while let rel = en.nextObject() as? String {
            let url = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue, !rel.hasSuffix(".DS_Store") else { continue }
            files.append((rel, try Data(contentsOf: url)))
        }

        let title = doc.scenario.title
        let titleX = TextFormat.xmlEscape(title)
        let userX = TextFormat.xmlEscape(userName.isEmpty ? "ScenarioWriterSolo" : userName)
        var out = ZipWriter()
        let document = try buildDocumentXML(doc, template: template, cover: cover, memo: memo)
        // ZIP の先頭は [Content_Types].xml にする
        files.sort { a, b in
            if a.0 == "[Content_Types].xml" { return b.0 != "[Content_Types].xml" }
            if b.0 == "[Content_Types].xml" { return false }
            return a.0 < b.0
        }
        for (rel, data) in files {
            var d = data
            switch rel {
            case "word/document.xml":
                d = Data(document.utf8)
            case "docProps/core.xml", "word/header1.xml", "word/footer2.xml":
                if var s = String(data: data, encoding: .utf8) {
                    s = s.replacingOccurrences(of: "{{USER_NAME}}", with: userX).replacingOccurrences(of: "{{TITLE}}", with: titleX)
                    d = Data(s.utf8)
                }
            default: break
            }
            out.add(path: rel, data: d)
        }
        return out.finish()
    }

    static func buildDocumentXML(_ doc: ScenarioDocument, template: Template, cover: CoverInfo, memo: MemoArea = .top) throws -> String {
        let chars = doc.characterById
        let styles = doc.styleByType
        let nameW = max(doc.setting.characterLength, 2)
        var xml = try snippet(template, "header")

        let dateStr = cover.date.map { TextFormat.wareki($0) } ?? ""
        xml += fill(try snippet(template, "cover"), [
            "TITLE": wt(doc.scenario.title), "SUBTITLE": wt(doc.scenario.subtitle), "DATE": wt(dateStr), "VERSION": wt(cover.version),
            "WRITER_NAME": wt(cover.writerName.isEmpty ? doc.scenario.writerName : cover.writerName), "WRITER_ID": wt(cover.writerId),
            "ADDRESS": wt(cover.address), "PHONE": wt(cover.phone), "EMAIL": wt(cover.email),
        ])

        xml += fill(try snippet(template, "characterListTitle"), ["TITLE": wt(doc.scenario.title)])
        let charSnippet = try snippet(template, "characterList")
        for c in doc.characters {
            xml += fill(charSnippet, ["CHARACTER_NAME": wt(c.name), "CHARACTER_CHARA": wt(c.chara.isEmpty ? c.name : c.chara)])
        }

        xml += fill(try snippet(template, "synopsis"), ["TITLE": wt(doc.scenario.title), "SYNOPSIS": wt(TextFormat.toFullWidth(doc.synopsis))])

        let sceneSnippet = applyMemo(try snippet(template, "scene"), template: template, memo: memo)
        let lineSnippet = applyMemo(try snippet(template, "line"), template: template, memo: memo)
        let togakiSnippet = applyMemo(try snippet(template, "togaki"), template: template, memo: memo)
        // 前後の余白は、罫線などの段落書式が続くように「台詞と同じ書式の空行」で入れる（<w:p/> だと罫線が途切れる）
        let blank = fill(lineSnippet, ["CHARACTER_DIV": "", "LINE": ""])
        for scene in doc.scenes {
            xml += fill(sceneSnippet, ["SCENE_NAME": wt(scene.name), "SCENE_DESC": wt(scene.description)])
            for line in doc.lines(of: scene) {
                let f = ScriptFormatter.format(line, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko)
                let name = TextFormat.toFullWidth(f.style.showsName ? f.characterName : "")
                let abbr = TextFormat.toFullWidth(f.style.abbreviation)
                let label: String
                switch (name.isEmpty, abbr.isEmpty) {
                case (true, true): label = ""
                case (true, false): label = abbr
                case (false, true): label = name
                case (false, false): label = name + "　" + abbr
                }
                let body = TextFormat.toFullWidth(f.text, asciiSymbols: true)
                xml += String(repeating: blank, count: f.style.marginBefore)
                defer { xml += String(repeating: blank, count: f.style.marginAfter) }
                if f.style.indent > 0 {
                    // ト書など: 見出しを右寄せ（Web 版は全角空白 10 個を前置して末尾 N 文字）
                    let head = TextFormat.padLeft(label, to: nameW)
                    xml += fill(togakiSnippet, ["CHARACTER_DIV": wt(head), "LINE": wt(body)])
                } else {
                    xml += fill(lineSnippet, ["CHARACTER_DIV": wt(label), "LINE": wt(body)])
                }
            }
        }
        xml += applyMemoPageBorder(try snippet(template, "bodyEnd"), memo: memo)
        return xml
    }

    // MARK: - 書き込み欄

    /// 段落の字下げ（twip）。テンプレートの段落スタイルの既定値と、断片に直接書いた値を合わせたもの
    struct Indent { var left = 0, right = 0, hanging = 0, firstLine = 0 }

    /// 書き込み欄をずらす段落スタイルの既定（styles.xml の値）と、行頭側の罫の有無
    static func memoStyles(_ t: Template) -> [String: (indent: Indent, bordered: Bool)] {
        switch t {
        case .a4PortraitVertical:
            return ["af0": (Indent(left: 4001, right: 150, hanging: 2801), true),       // 台詞
                    "afa": (Indent(left: 2550, right: 150, hanging: 1350), true),       // ト書き（台詞を継ぐ）
                    "af4": (Indent(left: 1200, right: 150, firstLine: 100), false)]     // 場面説明（罫なし）
        case .a4PortraitHorizontal, .a4LandscapeVertical:
            return ["a5": (Indent(left: 2698, hanging: 1560), true),                    // 台詞
                    "a4": (Indent(left: 3408, hanging: 2270), true)]                    // ト書き・アクション（台詞を継ぐ）
        }
    }

    /// 書き込み欄の長さ（twip）。テンプレートの台詞の 1 行目が始まる位置（左字下げ − ぶら下げ）
    static func memoTwips(_ t: Template) -> Int { t == .a4PortraitVertical ? 2880 : 1138 }

    /// 行頭側の罫（縦書きでは上の横線）の太さ・あき
    static func memoBorder(_ t: Template) -> String {
        t == .a4PortraitVertical ? #"w:val="single" w:sz="4" w:space="4" w:color="auto""# : #"w:val="single" w:sz="8" w:space="4" w:color="auto""#
    }

    /// テンプレートは書き込み欄が「上」（行頭側。横書きは左）。「下」なら台詞・ト書き・場面説明の段落を欄の長さだけ行頭へ寄せ、
    /// 行末側の字下げを同じだけ増やして罫を行末側へ移す。「なし」なら行頭へ寄せて罫を外す。
    /// 字下げは *Chars（字数指定）がスタイルに残っていると twip より優先されるので、0 にして twip で書く
    static func applyMemo(_ snippet: String, template: Template, memo: MemoArea) -> String {
        guard memo != .top else { return snippet }
        let styles = memoStyles(template)
        let shift = memoTwips(template)
        var out = snippet
        for m in matches(#"<w:pPr>(.*?)</w:pPr>"#, in: snippet).reversed() {
            var inner = (snippet as NSString).substring(with: m.range(at: 1))
            guard let styleID = firstGroup(#"<w:pStyle w:val="([^"]+)"/>"#, in: inner), let st = styles[styleID] else { continue }
            var ind = st.indent
            if let direct = firstGroup(#"<w:ind ([^>]*)/>"#, in: inner) {
                func attr(_ name: String) -> Int? { firstGroup(#"w:\#(name)="(-?[0-9]+)""#, in: direct).flatMap { Int($0) } }
                if let v = attr("left") { ind.left = v }
                if let v = attr("right") { ind.right = v }
                if let v = attr("hanging") { ind.hanging = v; ind.firstLine = 0 }
                if let v = attr("firstLine") { ind.firstLine = v; ind.hanging = 0 }
            }
            ind.left -= shift
            if memo == .bottom { ind.right += shift }
            var indXML = #"<w:ind w:leftChars="0" w:left="\#(ind.left)" w:rightChars="0" w:right="\#(ind.right)""#
            if ind.hanging > 0 { indXML += #" w:hangingChars="0" w:hanging="\#(ind.hanging)""# }
            if ind.firstLine > 0 { indXML += #" w:firstLineChars="0" w:firstLine="\#(ind.firstLine)""# }
            indXML += "/>"
            let hadBorder = inner.contains("<w:pBdr>")
            inner = replacing(#"<w:ind [^>]*/>"#, in: inner, with: "")
            inner = replacing(#"<w:pBdr>.*?</w:pBdr>"#, in: inner, with: "")
            // 並び順（pStyle → pBdr → … → spacing → ind → … → rPr）を守って差し込む
            if st.bordered || hadBorder, let ps = inner.range(of: "<w:pStyle"), let e = inner.range(of: "/>", range: ps.lowerBound..<inner.endIndex) {
                let bdr = memo == .bottom ? #"<w:pBdr><w:left w:val="nil"/><w:right \#(memoBorder(template))/></w:pBdr>"# : #"<w:pBdr><w:left w:val="nil"/></w:pBdr>"#
                inner.insert(contentsOf: bdr, at: e.upperBound)
            }
            if let rp = inner.range(of: "<w:rPr>") { inner.insert(contentsOf: indXML, at: rp.lowerBound) } else { inner += indXML }
            out = (out as NSString).replacingCharacters(in: m.range(at: 1), with: inner)
        }
        return out
    }

    /// A4縦 縦書きの本文ページの罫（ページ罫線の上辺）は、書き込み欄が「上」のときだけ残す
    /// （下辺へ移すとページ番号と重なるので、「下」「なし」では外す）
    static func applyMemoPageBorder(_ bodyEnd: String, memo: MemoArea) -> String {
        memo == .top ? bodyEnd : replacing(#"<w:pgBorders>.*?</w:pgBorders>\s*"#, in: bodyEnd, with: "")
    }

    static func matches(_ pattern: String, in s: String) -> [NSTextCheckingResult] {
        let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    static func firstGroup(_ pattern: String, in s: String) -> String? {
        guard let m = matches(pattern, in: s).first, m.numberOfRanges > 1 else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }

    static func replacing(_ pattern: String, in s: String, with template: String) -> String {
        let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
