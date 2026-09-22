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

    public static func make(_ doc: ScenarioDocument, template: Template, cover: CoverInfo, userName: String) throws -> Data {
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
        let document = try buildDocumentXML(doc, template: template, cover: cover)
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

    static func buildDocumentXML(_ doc: ScenarioDocument, template: Template, cover: CoverInfo) throws -> String {
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

        let sceneSnippet = try snippet(template, "scene")
        let lineSnippet = try snippet(template, "line")
        let togakiSnippet = try snippet(template, "togaki")
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
                xml += String(repeating: "<w:p/>", count: f.style.marginBefore)
                defer { xml += String(repeating: "<w:p/>", count: f.style.marginAfter) }
                if f.style.indent > 0 {
                    // ト書など: 見出しを右寄せ（Web 版は全角空白 10 個を前置して末尾 N 文字）
                    let head = TextFormat.padLeft(label, to: nameW)
                    xml += fill(togakiSnippet, ["CHARACTER_DIV": wt(head), "LINE": wt(body)])
                } else {
                    xml += fill(lineSnippet, ["CHARACTER_DIV": wt(label), "LINE": wt(body)])
                }
            }
        }
        xml += try snippet(template, "bodyEnd")
        return xml
    }
}
