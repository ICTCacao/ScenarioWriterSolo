import Foundation

/// テキスト台本（Web 版 swScenarioDownloadText.php の移植）。
/// 登場人物名欄を characterLength 文字、本文を bodyLength 文字で組み、全角空白で揃える。
public enum TextExporter {

    public enum Encoding: String, CaseIterable, Identifiable, Sendable {
        case utf8 = "UTF-8", shiftJIS = "Shift_JIS"
        public var id: String { rawValue }
        var stringEncoding: String.Encoding { self == .utf8 ? .utf8 : .shiftJIS }
    }
    public enum LineEnding: String, CaseIterable, Identifiable, Sendable {
        case lf = "LF", crlf = "CRLF", cr = "CR"
        public var id: String { rawValue }
        var string: String { self == .lf ? "\n" : (self == .crlf ? "\r\n" : "\r") }
    }

    public static func makeText(_ doc: ScenarioDocument) -> String {
        let nameW = max(doc.setting.characterLength, 2)
        let bodyW = max(doc.setting.bodyLength, 4)
        let nameBlank = TextFormat.spaces(nameW)
        let chars = doc.characterById
        let styles = doc.styleByType
        var out = ""

        let title = TextFormat.toFullWidth(doc.scenario.title)
        let subtitle = TextFormat.toFullWidth(doc.scenario.subtitle)
        out += title + (subtitle.isEmpty ? "" : "　" + subtitle) + "\n\n"
        out += "脚本： \(doc.scenario.writerName)\n\n"

        out += "\n\n【シノプシス】\n"
        for l in TextFormat.wrap(TextFormat.toFullWidth(doc.synopsis), width: bodyW) {
            out += nameBlank + l + "\n"
        }

        out += "\n\n【登場人物設定】\n"
        for c in doc.characters {
            let name = TextFormat.toFullWidth(c.name)
            let chara = TextFormat.toFullWidth(c.chara.isEmpty ? c.name : c.chara)
            let head = TextFormat.padRight(name, to: nameW)
            for (i, l) in TextFormat.wrap(chara, width: bodyW).enumerated() {
                if l.isEmpty { out += "\n"; continue }
                out += (i == 0 ? head : nameBlank) + l + "\n"
            }
        }

        for scene in doc.scenes {
            out += "\n\n\n\n\(scene.name)\n\n"
            for l in TextFormat.wrap(TextFormat.toFullWidth(scene.description), width: bodyW) {
                out += l.isEmpty ? "\n" : nameBlank + l + "\n"
            }
            out += "\n\n"
            var prevNoName = false
            for line in doc.lines(of: scene) {
                let f = ScriptFormatter.format(line, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko)
                let st = f.style
                let name = TextFormat.toFullWidth(st.showsName ? f.characterName : "")
                let abbr = TextFormat.toFullWidth(st.abbreviation)
                var head: String
                let noName = name.isEmpty
                if noName {
                    head = abbr.isEmpty ? nameBlank : TextFormat.padLeft(abbr, to: nameW)
                    // 人物名の無い行（ト書など）は前後を 1 行あける
                    if !prevNoName { out += "\n" }
                } else {
                    head = TextFormat.padRight(abbr.isEmpty ? name : name + "　" + abbr, to: nameW)
                }
                let indent = min(st.indent, bodyW - 2)
                let indentStr = TextFormat.spaces(indent)
                let body = TextFormat.toFullWidth(f.text)
                out += String(repeating: "\n", count: st.marginBefore)
                for (i, l) in TextFormat.wrap(body, width: bodyW - indent).enumerated() {
                    if l.isEmpty { out += "\n"; continue }
                    out += (i == 0 ? head : nameBlank) + indentStr + l + "\n"
                }
                out += String(repeating: "\n", count: st.marginAfter)
                if noName { out += "\n" }
                prevNoName = noName
            }
        }
        return out
    }

    public static func makeData(_ doc: ScenarioDocument, encoding: Encoding, lineEnding: LineEnding) -> Data {
        var text = makeText(doc)
        if lineEnding != .lf { text = text.replacingOccurrences(of: "\n", with: lineEnding.string) }
        if let d = text.data(using: encoding.stringEncoding, allowLossyConversion: true) { return d }
        return Data(text.utf8)
    }
}
