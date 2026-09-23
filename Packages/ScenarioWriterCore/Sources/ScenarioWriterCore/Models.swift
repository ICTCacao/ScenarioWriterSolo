import Foundation

// Web 版 ScenarioWriterCafe の SQLite スキーマ（SW_SCENARIO / SW_SCENE / SW_CHARACTER / SW_SCENARIO_LINES /
// SW_SYNOPSIS / SW_USER_OPTION / SW_USER_OPTION_SETTING）と 1:1 に対応するモデル。
// 本文の改行は DB では "<br>"、メモリ上では "\n" で持つ（Web 版と同じ DB ファイルを読み書きできる）。

public struct Scenario: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var userId: Int64
    public var title: String
    public var subtitle: String
    public var writerName: String
    public var memo: String
    public var date: String          // "yyyy-MM-dd HH:mm:ss"
    public var category: Int

    public init(id: Int64 = 0, userId: Int64 = 0, title: String = "", subtitle: String = "", writerName: String = "",
                memo: String = "", date: String = "", category: Int = 0) {
        self.id = id; self.userId = userId; self.title = title; self.subtitle = subtitle
        self.writerName = writerName; self.memo = memo; self.date = date; self.category = category
    }
}

public enum ScenarioCategory: Int, CaseIterable, Identifiable, Sendable {
    case none = 0, stage = 1, musical = 2, highSchool = 3, popular = 4, movie = 5
    case tvDrama = 6, tvProgram = 7, radioDrama = 8, radioProgram = 9, other = 10
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .none: return "---"
        case .stage: return "演劇"
        case .musical: return "ミュージカル"
        case .highSchool: return "高校演劇"
        case .popular: return "大衆演劇"
        case .movie: return "映画"
        case .tvDrama: return "テレビドラマ"
        case .tvProgram: return "テレビ番組"
        case .radioDrama: return "ラジオドラマ"
        case .radioProgram: return "ラジオ番組"
        case .other: return "その他"
        }
    }
    public static func label(for raw: Int) -> String { ScenarioCategory(rawValue: raw)?.label ?? "---" }
}

public struct ScriptScene: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var scenarioId: Int64
    public var orderNo: Double
    public var validCd: Int          // 0=有効 9=無効
    public var name: String
    public var description: String
    public var timeMin: Int
    public var timeSec: Int

    public init(id: Int64 = 0, scenarioId: Int64 = 0, orderNo: Double = 0, validCd: Int = 0, name: String = "",
                description: String = "", timeMin: Int = 0, timeSec: Int = 0) {
        self.id = id; self.scenarioId = scenarioId; self.orderNo = orderNo; self.validCd = validCd
        self.name = name; self.description = description; self.timeMin = timeMin; self.timeSec = timeSec
    }
    public var totalSeconds: Int { timeMin * 60 + timeSec }
}

public struct CastMember: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var scenarioId: Int64
    public var orderNo: Double
    public var name: String
    public var chara: String         // 人物設定

    public init(id: Int64 = 0, scenarioId: Int64 = 0, orderNo: Double = 0, name: String = "", chara: String = "") {
        self.id = id; self.scenarioId = scenarioId; self.orderNo = orderNo; self.name = name; self.chara = chara
    }
}

public struct ScriptLine: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var scenarioId: Int64
    public var sceneId: Int64
    public var orderNo: Double
    public var type: Int             // SW_USER_OPTION.USER_OPTION_STYLE_ID（1=セリフ 2=ト書 …）
    public var characterId: Int64?   // NULL なら人物なし
    public var text: String          // "\n" 区切り

    public init(id: Int64 = 0, scenarioId: Int64 = 0, sceneId: Int64 = 0, orderNo: Double = 0, type: Int = 1,
                characterId: Int64? = nil, text: String = "") {
        self.id = id; self.scenarioId = scenarioId; self.sceneId = sceneId; self.orderNo = orderNo
        self.type = type; self.characterId = characterId; self.text = text
    }
}

/// 行の種別ごとの見た目（USER STYLE）。SW_USER_OPTION の 1 行。
public struct LineStyle: Identifiable, Hashable, Sendable {
    public var id: Int64             // USER_OPTION_ID
    public var userId: Int64
    public var styleId: Int          // 行の SCENARIO_TYPE と結びつく番号
    public var orderNo: Int
    public var name: String
    public var fontSize: Int
    public var color: String         // "#rrggbb"
    public var indent: Int           // 字下げ数
    public var abbreviation: String  // 省略文字（NA / M / SE …）
    public var wordMode: Int         // 1=名前表示&「」 2=名前表示 3=名前非表示&「」 0=名前非表示
    /// 前後の余白（行数。読む・出力で使う。Solo だけの項目で、Web 版の表とは別に持つ）
    public var marginBefore: Int
    public var marginAfter: Int

    public init(id: Int64 = 0, userId: Int64 = 0, styleId: Int = 0, orderNo: Int = 0, name: String = "", fontSize: Int = 12,
                color: String = "#000000", indent: Int = 0, abbreviation: String = "", wordMode: Int = 0,
                marginBefore: Int = 0, marginAfter: Int = 0) {
        self.id = id; self.userId = userId; self.styleId = styleId; self.orderNo = orderNo; self.name = name
        self.fontSize = fontSize; self.color = color; self.indent = indent; self.abbreviation = abbreviation; self.wordMode = wordMode
        self.marginBefore = marginBefore; self.marginAfter = marginAfter
    }
    public var showsName: Bool { wordMode == 1 || wordMode == 2 }
    public var usesKagikakko: Bool { wordMode == 1 || wordMode == 3 }

    public static func wordMode(showsName: Bool, kagikakko: Bool) -> Int {
        switch (showsName, kagikakko) {
        case (true, true): return 1
        case (true, false): return 2
        case (false, true): return 3
        case (false, false): return 0
        }
    }
    public static let wordModeLabels: [Int: String] = [
        1: "登場人物名を出す・台詞を「」で囲む",
        2: "登場人物名を出す・「」で囲まない",
        3: "登場人物名を出さない・台詞を「」で囲む",
        0: "登場人物名を出さない・「」で囲まない",
    ]
}

/// USER OPTION 設定（SW_USER_OPTION_SETTING）。
/// 固定スタイル（削除できない）の種類: シノプシス・場面説明・登場人物（人物設定）
public enum TextStyleKind: String, CaseIterable, Sendable {
    case synopsis
    case sceneDescription = "scene"
    case character

    public var label: String {
        switch self {
        case .synopsis: return "シノプシス"
        case .sceneDescription: return "場面説明"
        case .character: return "登場人物"
        }
    }
}

/// シノプシス・場面説明・登場人物の見た目。行のスタイル（LineStyle）と違って消せず、名前も固定。
/// Solo だけの表 SW_SOLO_TEXT_STYLE に持つ（Web 版の表には触らない）
public struct TextStyle: Identifiable, Hashable, Sendable {
    public var kind: TextStyleKind
    public var fontSize: Int
    public var color: String
    public var indent: Int
    public var marginBefore: Int
    public var marginAfter: Int
    public var id: TextStyleKind { kind }

    public init(kind: TextStyleKind, fontSize: Int = 14, color: String = "#000000", indent: Int = 0, marginBefore: Int = 0, marginAfter: Int = 0) {
        self.kind = kind; self.fontSize = fontSize; self.color = color; self.indent = indent
        self.marginBefore = marginBefore; self.marginAfter = marginAfter
    }

    /// 既定値。場面説明は台本の慣習どおり緑
    public static func `default`(_ kind: TextStyleKind) -> TextStyle {
        switch kind {
        case .synopsis: return TextStyle(kind: kind, fontSize: 14, color: "#000000")
        case .sceneDescription: return TextStyle(kind: kind, fontSize: 14, color: "#006400")
        case .character: return TextStyle(kind: kind, fontSize: 14, color: "#000000")
        }
    }
    public static var defaults: [TextStyle] { TextStyleKind.allCases.map(TextStyle.default) }
}

public struct OptionSetting: Hashable, Sendable {
    public var characterLength: Int  // テキスト出力の登場人物名欄の文字数
    public var bodyLength: Int       // テキスト出力の本文 1 行の文字数
    public var useKagikakko: Bool

    public init(characterLength: Int = 8, bodyLength: Int = 32, useKagikakko: Bool = false) {
        self.characterLength = characterLength; self.bodyLength = bodyLength; self.useKagikakko = useKagikakko
    }
}

/// 出力（読む・テキスト・Word・HTML）に渡す 1 作品分のまとまり。
public struct ScenarioDocument: Sendable {
    public var scenario: Scenario
    public var synopsis: String
    public var characters: [CastMember]
    public var scenes: [ScriptScene]
    public var linesByScene: [Int64: [ScriptLine]]
    public var styles: [LineStyle]
    public var setting: OptionSetting
    public var textStyles: [TextStyle]

    public init(scenario: Scenario, synopsis: String, characters: [CastMember], scenes: [ScriptScene],
                linesByScene: [Int64: [ScriptLine]], styles: [LineStyle], setting: OptionSetting, textStyles: [TextStyle] = []) {
        self.scenario = scenario; self.synopsis = synopsis; self.characters = characters; self.scenes = scenes
        self.linesByScene = linesByScene; self.styles = styles; self.setting = setting; self.textStyles = textStyles
    }
    public func textStyle(_ kind: TextStyleKind) -> TextStyle { textStyles.first { $0.kind == kind } ?? .default(kind) }
    public var characterById: [Int64: CastMember] { Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) }) }
    public var styleByType: [Int: LineStyle] {
        var d: [Int: LineStyle] = [:]
        for s in styles where d[s.styleId] == nil { d[s.styleId] = s }
        return d
    }
    public func lines(of scene: ScriptScene) -> [ScriptLine] { linesByScene[scene.id] ?? [] }
}

public enum DBText {
    /// DB の "<br>" → "\n"
    public static func fromDB(_ s: String?) -> String {
        guard let s = s else { return "" }
        return s.replacingOccurrences(of: "<br>", with: "\n")
    }
    /// "\r\n" / "\r" / "\n" → DB の "<br>"
    public static func toDB(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
