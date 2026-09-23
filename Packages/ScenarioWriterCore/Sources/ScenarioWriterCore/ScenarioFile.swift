import Foundation

/// 作品ファイル（.scwd）の中身。UTF-8 の JSON で、Mac 版・Windows 版で共通。
/// 1 ファイル 1 作品。行のスタイルと書式設定も入れてあるので、別のアプリでも同じ見た目で読める。
///
/// 中身の並び（キーは五十音ではなく ABC 順で書き出される）:
/// - format / version / app … 形式の名前と版、書いたアプリ
/// - scenario … 題名・副題・作者・メモ・更新日時・分類
/// - synopsis … あらすじ（改行は "\n"）
/// - characters … 登場人物（id はこのファイルの中だけで使う番号。lines の character が指す）
/// - scenes … 場面（名前・説明・有効・分・秒）と、その中の lines（種別・人物・本文）
/// - styles / textStyles / setting … 行の種別ごとの見た目・固定スタイル・本文の文字数など
/// - thumbnail … 作品画像（PNG の base64。無ければ省略）
public struct ScenarioFile: Codable, Sendable, Equatable {
    public static let formatName = "scwd"
    public static let currentVersion = 1

    public struct Info: Codable, Sendable, Equatable {
        public var title = ""
        public var subtitle = ""
        public var writer = ""
        public var memo = ""
        public var date = ""        // "yyyy-MM-dd HH:mm:ss"
        public var category = 0     // ScenarioCategory
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = c.value(.title, ""); subtitle = c.value(.subtitle, ""); writer = c.value(.writer, "")
            memo = c.value(.memo, ""); date = c.value(.date, ""); category = c.value(.category, 0)
        }
    }

    public struct Character: Codable, Sendable, Equatable {
        public var id: Int64
        public var name = ""
        public var chara = ""       // 人物設定
        public init(id: Int64, name: String = "", chara: String = "") { self.id = id; self.name = name; self.chara = chara }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.value(.id, Int64(0)); name = c.value(.name, ""); chara = c.value(.chara, "")
        }
    }

    public struct Line: Codable, Sendable, Equatable {
        public var type: Int        // styles[].id と結びつく種別番号（1=セリフ 2=ト書 …）
        public var character: Int64?  // characters[].id。人物なしなら省略
        public var text = ""        // 改行は "\n"
        public init(type: Int, character: Int64? = nil, text: String = "") { self.type = type; self.character = character; self.text = text }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = c.value(.type, 1); character = try c.decodeIfPresent(Int64.self, forKey: .character); text = c.value(.text, "")
        }
    }

    public struct Scene: Codable, Sendable, Equatable {
        public var name = ""
        public var description = ""
        public var valid = true
        public var minutes = 0
        public var seconds = 0
        public var lines: [Line] = []
        public init(name: String = "", description: String = "", valid: Bool = true, minutes: Int = 0, seconds: Int = 0, lines: [Line] = []) {
            self.name = name; self.description = description; self.valid = valid; self.minutes = minutes; self.seconds = seconds; self.lines = lines
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.value(.name, ""); description = c.value(.description, ""); valid = c.value(.valid, true)
            minutes = c.value(.minutes, 0); seconds = c.value(.seconds, 0); lines = c.value(.lines, [])
        }
    }

    public struct Style: Codable, Sendable, Equatable {
        public var id: Int          // 種別番号
        public var order = 0
        public var name = ""
        public var size = 12
        public var color = "#000000"
        public var indent = 0
        public var abbr = ""        // 省略文字（NA / M / SE …）
        public var mode = 0         // 1=名前を出す&「」 2=名前を出す 3=名前なし&「」 0=名前なし
        public var marginBefore = 0
        public var marginAfter = 0
        public init(id: Int) { self.id = id }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.value(.id, 0); order = c.value(.order, 0); name = c.value(.name, ""); size = c.value(.size, 12)
            color = c.value(.color, "#000000"); indent = c.value(.indent, 0); abbr = c.value(.abbr, ""); mode = c.value(.mode, 0)
            marginBefore = c.value(.marginBefore, 0); marginAfter = c.value(.marginAfter, 0)
        }
    }

    public struct TextStyleEntry: Codable, Sendable, Equatable {
        public var size = 14
        public var color = "#000000"
        public var indent = 0
        public var marginBefore = 0
        public var marginAfter = 0
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            size = c.value(.size, 14); color = c.value(.color, "#000000"); indent = c.value(.indent, 0)
            marginBefore = c.value(.marginBefore, 0); marginAfter = c.value(.marginAfter, 0)
        }
    }

    public struct Setting: Codable, Sendable, Equatable {
        public var characterLength = 8
        public var bodyLength = 32
        /// 新しい作品は「」で囲まない（β7〜）。読み込みで項目が無いときは、古いファイルの見た目を変えないよう true
        public var kagikakko = false
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            characterLength = c.value(.characterLength, 8); bodyLength = c.value(.bodyLength, 32); kagikakko = c.value(.kagikakko, true)
        }
    }

    public var format = ScenarioFile.formatName
    public var version = ScenarioFile.currentVersion
    public var app = ""
    public var scenario = Info()
    public var synopsis = ""
    public var characters: [Character] = []
    public var scenes: [Scene] = []
    public var styles: [Style] = []
    public var textStyles: [String: TextStyleEntry] = [:]
    public var setting = Setting()
    public var thumbnail: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.value(.format, ""); version = c.value(.version, 1); app = c.value(.app, "")
        scenario = c.value(.scenario, Info()); synopsis = c.value(.synopsis, "")
        characters = c.value(.characters, []); scenes = c.value(.scenes, []); styles = c.value(.styles, [])
        textStyles = c.value(.textStyles, [:]); setting = c.value(.setting, Setting())
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
    }

    // MARK: 読み書き

    public enum FileError: LocalizedError {
        case notScenarioFile
        case newerVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .notScenarioFile: return "ScenarioWriter の作品ファイル（JSON）ではありません"
            case .newerVersion(let v): return "この作品ファイルは新しい形式（版 \(v)）です。アプリを更新してください"
            }
        }
    }

    /// 見やすい JSON（キーは ABC 順、日本語はそのまま）
    public func encode() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> ScenarioFile {
        guard isJSON(data) else { throw FileError.notScenarioFile }
        let f = try JSONDecoder().decode(ScenarioFile.self, from: data)
        guard f.format == formatName else { throw FileError.notScenarioFile }
        guard f.version <= currentVersion else { throw FileError.newerVersion(f.version) }
        return f
    }

    /// 旧形式（SQLite）の作品ファイルか
    public static func isSQLite(_ data: Data) -> Bool {
        data.count >= 16 && data.prefix(15) == Data("SQLite format 3".utf8)
    }

    /// 先頭が "{" なら JSON とみなす（BOM・空白は読み飛ばす）
    public static func isJSON(_ data: Data) -> Bool {
        var i = data.startIndex
        if data.count >= 3, data[i] == 0xEF, data[i + 1] == 0xBB, data[i + 2] == 0xBF { i += 3 }
        while i < data.endIndex, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return i < data.endIndex && data[i] == UInt8(ascii: "{")
    }
}

extension KeyedDecodingContainer {
    /// 無い・null・型違いのキーは既定値にする（別のアプリが書いたファイルにも寛容に）
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - DB との相互変換

extension ScenarioStore {
    /// 更新日時を指定の値にする（ファイルから読んだときに、書いてあった日時を保つ）
    public func setScenarioDate(id: Int64, date: String) throws {
        guard !date.isEmpty else { return }
        try db.run("UPDATE SW_SCENARIO SET SCENARIO_DATE = ? WHERE SCENARIO_ID = ?", [.text(date), .int(id)])
    }

    /// 1 作品を作品ファイルの形にする
    public func exportFile(scenarioId: Int64, app: String) throws -> ScenarioFile {
        guard let sc = try scenario(id: scenarioId) else { throw SQLiteError(code: 0, message: "シナリオがありません") }
        var f = ScenarioFile()
        f.app = app
        f.scenario.title = sc.title; f.scenario.subtitle = sc.subtitle; f.scenario.writer = sc.writerName
        f.scenario.memo = sc.memo; f.scenario.date = sc.date; f.scenario.category = sc.category
        f.synopsis = try synopsis(scenarioId: scenarioId)
        f.characters = try characters(scenarioId: scenarioId).map { ScenarioFile.Character(id: $0.id, name: $0.name, chara: $0.chara) }
        var byScene: [Int64: [ScriptLine]] = [:]
        for l in try allLines(scenarioId: scenarioId) { byScene[l.sceneId, default: []].append(l) }
        f.scenes = try scenes(scenarioId: scenarioId).map { s in
            ScenarioFile.Scene(name: s.name, description: s.description, valid: s.validCd == 0, minutes: s.timeMin, seconds: s.timeSec,
                               lines: (byScene[s.id] ?? []).map { ScenarioFile.Line(type: $0.type, character: $0.characterId, text: $0.text) })
        }
        f.styles = try styles().map { s in
            var st = ScenarioFile.Style(id: s.styleId)
            st.order = s.orderNo; st.name = s.name; st.size = s.fontSize; st.color = s.color; st.indent = s.indent
            st.abbr = s.abbreviation; st.mode = s.wordMode; st.marginBefore = s.marginBefore; st.marginAfter = s.marginAfter
            return st
        }
        for t in try textStyles() {
            var e = ScenarioFile.TextStyleEntry()
            e.size = t.fontSize; e.color = t.color; e.indent = t.indent; e.marginBefore = t.marginBefore; e.marginAfter = t.marginAfter
            f.textStyles[t.kind.rawValue] = e
        }
        let st = try setting()
        f.setting.characterLength = st.characterLength; f.setting.bodyLength = st.bodyLength; f.setting.kagikakko = st.useKagikakko
        f.thumbnail = try thumbnail(scenarioId: scenarioId)?.base64EncodedString()
        return f
    }

    /// 作品ファイルの中身をこの DB に入れる（スタイル・書式も写す）。作った作品の ID を返す
    @discardableResult
    public func importFile(_ f: ScenarioFile) throws -> Int64 {
        try db.transaction {
            if !f.styles.isEmpty {
                let styles = f.styles.map { s in
                    LineStyle(styleId: s.id, orderNo: s.order, name: s.name, fontSize: s.size, color: s.color, indent: s.indent,
                              abbreviation: s.abbr, wordMode: s.mode, marginBefore: s.marginBefore, marginAfter: s.marginAfter)
                }
                let texts = TextStyleKind.allCases.map { k -> TextStyle in
                    guard let e = f.textStyles[k.rawValue] else { return .default(k) }
                    return TextStyle(kind: k, fontSize: e.size, color: e.color, indent: e.indent, marginBefore: e.marginBefore, marginAfter: e.marginAfter)
                }
                try replaceStyles(styles, textStyles: texts,
                                  setting: OptionSetting(characterLength: f.setting.characterLength, bodyLength: f.setting.bodyLength, useKagikakko: f.setting.kagikakko))
            }
            let id = try insertScenario(Scenario(title: f.scenario.title, subtitle: f.scenario.subtitle, writerName: f.scenario.writer,
                                                 memo: f.scenario.memo, category: f.scenario.category))
            try setScenarioDate(id: id, date: f.scenario.date)
            try saveSynopsis(scenarioId: id, text: f.synopsis)
            // 登場人物: ファイルの id → DB の id
            var charMap: [Int64: Int64] = [:]
            var order = 0.0
            for c in f.characters {
                order += 100
                let nid = try insertCharacter(CastMember(scenarioId: id, orderNo: order, name: c.name, chara: c.chara))
                charMap[c.id] = nid
            }
            order = 0
            for s in f.scenes {
                order += 100
                let sid = try insertScene(ScriptScene(scenarioId: id, orderNo: order, validCd: s.valid ? 0 : 9, name: s.name,
                                                      description: s.description, timeMin: s.minutes, timeSec: s.seconds))
                var lineOrder = 0.0
                for l in s.lines {
                    lineOrder += 100
                    let charVal: SQLiteDatabase.SQLiteValue? = l.character.flatMap { charMap[$0] }.map { .int($0) }
                    try db.run("INSERT INTO SW_SCENARIO_LINES (SCENARIO_ID, SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_TYPE, CHARACTER_ID, SCENARIO_LINES) VALUES (?, ?, ?, ?, ?, ?)",
                               [.int(id), .int(sid), .real(lineOrder), .i(l.type), charVal, .text(DBText.toDB(l.text))])
                }
            }
            if let b64 = f.thumbnail, let png = Data(base64Encoded: b64) { try setThumbnail(scenarioId: id, png: png) }
            try setScenarioDate(id: id, date: f.scenario.date)
            return id
        }
    }
}
