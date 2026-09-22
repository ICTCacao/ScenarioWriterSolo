import Foundation

/// 行の種別（USER STYLE）を解決して、画面・出力に共通の「見た目」を返す。
/// Web 版の swPreview_Line / swScenarioDownload*.php の分岐を 1 か所にまとめたもの。
public struct ResolvedStyle: Hashable, Sendable {
    public var name: String
    public var fontSize: Int
    public var color: String
    public var indent: Int
    public var abbreviation: String
    public var showsName: Bool
    public var kagikakko: Bool
    public var marginBefore: Int
    public var marginAfter: Int

    public init(name: String = "", fontSize: Int = 12, color: String = "#000000", indent: Int = 0, abbreviation: String = "", showsName: Bool = false, kagikakko: Bool = false,
                marginBefore: Int = 0, marginAfter: Int = 0) {
        self.name = name; self.fontSize = fontSize; self.color = color; self.indent = indent
        self.abbreviation = abbreviation; self.showsName = showsName; self.kagikakko = kagikakko
        self.marginBefore = marginBefore; self.marginAfter = marginAfter
    }
}

public struct FormattedLine: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var line: ScriptLine
    public var style: ResolvedStyle
    public var characterName: String     // 人物名（表示しないスタイルでも持つ）
    public var label: String             // 画面に出す見出し（人物名＋省略文字）
    public var text: String              // 「」を付けた本文（改行は \n）
}

public enum ScriptFormatter {

    /// スタイル未登録の種別（1〜9）の既定。Web 版のフォールバックと同じ。
    static func fallback(type: Int) -> ResolvedStyle {
        switch type {
        case 1: return ResolvedStyle(name: "セリフ", indent: 0, showsName: true, kagikakko: true)
        case 2: return ResolvedStyle(name: "ト書", color: "#006400", indent: 3)
        case 3: return ResolvedStyle(name: "歌詞", indent: 3, abbreviation: "歌")
        case 4: return ResolvedStyle(name: "ナレーション", indent: 0, abbreviation: "NA", showsName: true, kagikakko: true)
        case 5: return ResolvedStyle(name: "モノローグ", indent: 0, abbreviation: "M", showsName: true, kagikakko: true)
        case 6: return ResolvedStyle(name: "テロップ", indent: 3, abbreviation: "T")
        case 7: return ResolvedStyle(name: "演技指示", indent: 3)
        case 8: return ResolvedStyle(name: "音響指示", indent: 3, abbreviation: "SE")
        case 9: return ResolvedStyle(name: "照明指示", indent: 3, abbreviation: "L")
        default: return ResolvedStyle(name: "種別\(type)")
        }
    }

    public static func resolve(type: Int, styles: [Int: LineStyle], useKagikakko: Bool) -> ResolvedStyle {
        var r: ResolvedStyle
        if let s = styles[type] {
            r = ResolvedStyle(name: s.name, fontSize: s.fontSize > 0 ? s.fontSize : 12, color: s.color.isEmpty ? "#000000" : s.color,
                              indent: max(s.indent, 0), abbreviation: s.abbreviation, showsName: s.showsName, kagikakko: s.usesKagikakko,
                              marginBefore: max(s.marginBefore, 0), marginAfter: max(s.marginAfter, 0))
        } else {
            r = fallback(type: type)
        }
        if !useKagikakko { r.kagikakko = false }
        return r
    }

    public static func format(_ line: ScriptLine, characters: [Int64: CastMember], styles: [Int: LineStyle], useKagikakko: Bool) -> FormattedLine {
        let st = resolve(type: line.type, styles: styles, useKagikakko: useKagikakko)
        let name = line.characterId.flatMap { characters[$0]?.name } ?? ""
        let text = st.kagikakko ? TextFormat.kagikakko(line.text) : line.text
        let label = labelFor(name: name, style: st)
        return FormattedLine(id: line.id, line: line, style: st, characterName: name, label: label, text: text)
    }

    /// 見出し = 人物名 ＋ 省略文字。名前を出さないスタイルでは省略文字だけ。
    public static func labelFor(name: String, style: ResolvedStyle) -> String {
        let n = style.showsName ? name : ""
        switch (n.isEmpty, style.abbreviation.isEmpty) {
        case (true, true): return ""
        case (true, false): return style.abbreviation
        case (false, true): return n
        case (false, false): return n + "　" + style.abbreviation
        }
    }

    public static func format(_ doc: ScenarioDocument, scene: ScriptScene) -> [FormattedLine] {
        let chars = doc.characterById
        let styles = doc.styleByType
        return doc.lines(of: scene).map { format($0, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko) }
    }
}
