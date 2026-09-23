import Foundation

/// 作品データの読み書き。Web 版 ScenarioWriterCafe と同じ SQLite スキーマを使う（sw_config/swdata.sqlite と互換）。
/// ひとり用なので、SW_USER の先頭ユーザーを「自分」として扱う。
public final class ScenarioStore {
    public let db: SQLiteDatabase
    public let url: URL
    public private(set) var userId: Int64 = 0

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: url.path)
        // 作品ファイルは直接は開かず、アプリのコンテナ内の作業用コピーを開く（⌘S で本ファイルへ書き戻す）ので、通常のジャーナルでよい
        try db.exec("PRAGMA journal_mode=DELETE")
        try db.exec("PRAGMA synchronous=FULL")
        try db.exec("PRAGMA foreign_keys=OFF")
        try createSchemaIfNeeded()
        try ensureUser()
    }

    // MARK: - スキーマ（Web 版 sw_config/scwSchema.sqlite.sql と同じ表・列）

    static let schemaSQL: [String] = [
        """
        CREATE TABLE IF NOT EXISTS SW_CHARACTER (
          CHARACTER_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          SCENARIO_ID INTEGER DEFAULT NULL,
          CHARACTER_ORDER_NO REAL DEFAULT NULL,
          CHARACTER_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          CHARACTER_CHARA TEXT,
          COPY_SOURCE_ID INTEGER DEFAULT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_CHARACTER_KEY_SCENARIO_ID ON SW_CHARACTER (SCENARIO_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_CONTACT (
          CONTACT_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          CONTACT_MAILAD VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          CONTACT_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          CONTACT_SUBJECT VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          CONTACT_BODY TEXT,
          CONTACT_REPLY TEXT,
          CONTACT_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS SW_SCENARIO (
          SCENARIO_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          USER_ID INTEGER DEFAULT NULL,
          SCENARIO_TITLE VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          SCENARIO_SUBTITLE VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          SCENARIO_WRITER_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          SCENARIO_MEMO TEXT,
          SCENARIO_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime')),
          SCENARIO_CATEGORY INTEGER DEFAULT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_SCENARIO_KEY_USER_ID ON SW_SCENARIO (USER_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_SCENARIO_LINES (
          SCENARIO_LINES_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          SCENARIO_ID INTEGER DEFAULT NULL,
          SCENE_ID INTEGER DEFAULT NULL,
          SCENARIO_LINES_ORDER_NO REAL DEFAULT NULL,
          SCENARIO_TYPE INTEGER DEFAULT NULL,
          CHARACTER_ID INTEGER DEFAULT NULL,
          SCENARIO_LINES TEXT
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_SCENARIO_LINES_KEY_SCENARIO_ID ON SW_SCENARIO_LINES (SCENARIO_ID)",
        "CREATE INDEX IF NOT EXISTS SW_SCENARIO_LINES_KEY_SCENE_ID ON SW_SCENARIO_LINES (SCENE_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_SCENE (
          SCENE_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          SCENARIO_ID INTEGER DEFAULT NULL,
          SCENE_ORDER_NO REAL DEFAULT NULL,
          SCENE_VALID_CD INTEGER DEFAULT NULL,
          SCENE_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          SCENE_DESCRIPTION TEXT,
          SCENE_TIME_MIN INTEGER DEFAULT NULL,
          SCENE_TIME_SEC INTEGER DEFAULT NULL,
          COPY_SOURCE_ID INTEGER DEFAULT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_SCENE_KEY_SCENARIO_ID ON SW_SCENE (SCENARIO_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_SYNOPSIS (
          SYNOPSIS_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          SCENARIO_ID INTEGER DEFAULT NULL,
          SYNOPSIS TEXT,
          UPDATE_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_SYNOPSIS_KEY_SCENARIO_ID ON SW_SYNOPSIS (SCENARIO_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_USER (
          USER_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          USER_MAILAD VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          USER_PASSWD VARCHAR(256) DEFAULT NULL,
          USER_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          USER_MAX_SCENARIO INTEGER DEFAULT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS SW_USER_LOGIN_INFO (
          USER_LOGIN_ID VARCHAR(32) NOT NULL PRIMARY KEY,
          USER_ID VARCHAR(256) DEFAULT NULL,
          USER_LOGIN_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS SW_USER_OPTION (
          USER_OPTION_ID INTEGER PRIMARY KEY AUTOINCREMENT,
          USER_ID INTEGER DEFAULT NULL,
          USER_OPTION_STYLE_ID INTEGER DEFAULT NULL,
          USER_OPTION_STYLE_ORDER_NO INTEGER DEFAULT NULL,
          USER_OPTION_STYLE_NAME VARCHAR(256) COLLATE NOCASE DEFAULT NULL,
          USER_OPTION_STYLE_FONT_SIZE INTEGER DEFAULT NULL,
          USER_OPTION_STYLE_COLOR VARCHAR(24) COLLATE NOCASE DEFAULT NULL,
          USER_OPTION_STYLE_INDENT INTEGER DEFAULT NULL,
          USER_OPTION_STYLE_STR VARCHAR(24) COLLATE NOCASE DEFAULT NULL,
          USER_OPTION_STYLE_WORD INTEGER DEFAULT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_USER_OPTION_KEY_USER_ID ON SW_USER_OPTION (USER_ID)",
        """
        CREATE TABLE IF NOT EXISTS SW_USER_OPTION_SETTING (
          USER_ID INTEGER NOT NULL PRIMARY KEY,
          CHARACTER_LENGTH INTEGER DEFAULT NULL,
          BODY_LENGTH INTEGER DEFAULT NULL,
          USE_KAGIKAKKO INTEGER NOT NULL DEFAULT 1
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS SW_PREVIEW (
          SCENARIO_ID INTEGER NOT NULL PRIMARY KEY,
          PREVIEW_KEY VARCHAR(64) NOT NULL,
          PREVIEW_VALID INTEGER NOT NULL DEFAULT 0,
          UPDATE_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        )
        """,
        "CREATE INDEX IF NOT EXISTS SW_PREVIEW_KEY_PREVIEW_KEY ON SW_PREVIEW (PREVIEW_KEY)",
        // Solo だけが使う: 作品画像（Web 版は img/thumb/ に置くが、作品ファイルに同梱したいので表に持つ）
        """
        CREATE TABLE IF NOT EXISTS SW_SOLO_THUMB (
          SCENARIO_ID INTEGER NOT NULL PRIMARY KEY,
          PNG BLOB,
          UPDATE_DATE TEXT NOT NULL DEFAULT (datetime('now','localtime'))
        )
        """,
    ]

    /// 作品ファイルの拡張子
    public static let workFileExtension = "scwd"

    /// Solo だけのスタイル項目（前後の余白）。Web 版の SW_USER_OPTION には列を足さず、別表に持つ
    static let marginTableSQL = """
        CREATE TABLE IF NOT EXISTS SW_SOLO_STYLE_MARGIN (
          USER_ID INTEGER NOT NULL,
          STYLE_ID INTEGER NOT NULL,
          MARGIN_BEFORE INTEGER NOT NULL DEFAULT 0,
          MARGIN_AFTER INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (USER_ID, STYLE_ID)
        )
        """

    /// Solo だけの固定スタイル（シノプシス・場面説明・登場人物）。KIND は TextStyleKind.rawValue
    static let textStyleTableSQL = """
        CREATE TABLE IF NOT EXISTS SW_SOLO_TEXT_STYLE (
          USER_ID INTEGER NOT NULL,
          KIND TEXT NOT NULL,
          FONT_SIZE INTEGER NOT NULL DEFAULT 14,
          COLOR TEXT NOT NULL DEFAULT '#000000',
          INDENT INTEGER NOT NULL DEFAULT 0,
          MARGIN_BEFORE INTEGER NOT NULL DEFAULT 0,
          MARGIN_AFTER INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (USER_ID, KIND)
        )
        """

    /// 既定の USER STYLE。作者（ICTCacao）が実運用で整えたもの（2026-09-22「きつね」の設定）。
    /// Web 版のテンプレート（USER_ID=0、21 種・サイズ 12）とは違い、13 種・サイズ 14・前後の余白付き。
    /// (styleId, orderNo, name, fontSize, color, indent, abbreviation, wordMode, marginBefore, marginAfter)
    public static let defaultStyles: [(Int, Int, String, Int, String, Int, String, Int, Int, Int)] = [
        (1, 100, "セリフ", 14, "#000000", 0, "", 1, 0, 0),
        (2, 200, "ト書", 14, "#006400", 3, "", 0, 1, 1),
        (3, 300, "歌詞", 14, "#ff4500", 4, "Song", 0, 2, 2),
        (4, 400, "ナレーション", 14, "#000000", 0, "NA", 1, 1, 1),
        (5, 500, "モノローグ", 14, "#000000", 0, "M", 1, 1, 1),
        (6, 600, "テロップ", 14, "#ff4500", 4, "T", 0, 1, 1),
        (7, 700, "演技指示", 14, "#8b0000", 4, "", 0, 2, 2),
        (8, 800, "音響指示", 14, "#8b0000", 4, "SE", 0, 2, 2),
        (9, 900, "照明指示", 14, "#8b0000", 4, "L", 0, 2, 2),
        (10, 1000, "フェードイン", 14, "#000000", 4, "(F.I)", 0, 1, 1),
        (11, 1100, "フェードアウト", 14, "#000000", 4, "(F.O)", 0, 1, 1),
        (12, 1200, "カットイン", 14, "#000000", 4, "(C.I)", 0, 1, 1),
        (13, 1300, "カットアウト", 14, "#000000", 4, "(C.O)", 0, 1, 1),
    ]

    private func createSchemaIfNeeded() throws {
        for sql in Self.schemaSQL { try db.exec(sql) }
        try db.exec(Self.marginTableSQL)
        try db.exec(Self.textStyleTableSQL)
        // 古い Web 版 DB には USE_KAGIKAKKO 列が無いことがある
        if try !db.columnExists(table: "SW_USER_OPTION_SETTING", column: "USE_KAGIKAKKO") {
            try db.exec("ALTER TABLE SW_USER_OPTION_SETTING ADD COLUMN USE_KAGIKAKKO INTEGER NOT NULL DEFAULT 1")
        }
    }

    private func ensureUser() throws {
        if let uid = try db.scalarInt("SELECT MIN(USER_ID) FROM SW_USER WHERE USER_ID > 0"), uid > 0 {
            userId = uid
        } else {
            try db.run("INSERT INTO SW_USER (USER_MAILAD, USER_PASSWD, USER_NAME, USER_MAX_SCENARIO) VALUES (?, '', ?, 9999)",
                       [.text("local@scenariowritersolo"), .text("ローカルユーザー")])
            userId = db.lastInsertRowId
        }
        if try db.scalarInt("SELECT COUNT(*) FROM SW_USER_OPTION_SETTING WHERE USER_ID = ?", [.int(userId)]) == 0 {
            // 台詞を「」で囲むのは既定でオフ（β7〜）
            try db.run("INSERT INTO SW_USER_OPTION_SETTING (USER_ID, CHARACTER_LENGTH, BODY_LENGTH, USE_KAGIKAKKO) VALUES (?, 8, 32, 0)", [.int(userId)])
        }
        if try db.scalarInt("SELECT COUNT(*) FROM SW_USER_OPTION WHERE USER_ID = ?", [.int(userId)]) == 0 {
            try resetStylesToDefault()
        }
    }

    public var userName: String {
        (try? db.query("SELECT USER_NAME FROM SW_USER WHERE USER_ID = ?", [.int(userId)]).first?.text("USER_NAME")) ?? ""
    }
    public func setUserName(_ name: String) throws {
        try db.run("UPDATE SW_USER SET USER_NAME = ? WHERE USER_ID = ?", [.text(name), .int(userId)])
    }

    static func now() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - シナリオ

    public func scenarios() throws -> [Scenario] {
        try db.query("SELECT * FROM SW_SCENARIO WHERE USER_ID = ? ORDER BY SCENARIO_DATE DESC, SCENARIO_ID DESC", [.int(userId)]).map(Self.scenario)
    }

    public func scenario(id: Int64) throws -> Scenario? {
        try db.query("SELECT * FROM SW_SCENARIO WHERE SCENARIO_ID = ?", [.int(id)]).first.map(Self.scenario)
    }

    static func scenario(_ r: SQLiteDatabase.Row) -> Scenario {
        Scenario(id: r.int("SCENARIO_ID") ?? 0, userId: r.int("USER_ID") ?? 0,
                 title: r.text("SCENARIO_TITLE") ?? "", subtitle: r.text("SCENARIO_SUBTITLE") ?? "",
                 writerName: r.text("SCENARIO_WRITER_NAME") ?? "", memo: DBText.fromDB(r.text("SCENARIO_MEMO")),
                 date: r.text("SCENARIO_DATE") ?? "", category: r.intValue("SCENARIO_CATEGORY"))
    }

    @discardableResult
    public func insertScenario(_ s: Scenario) throws -> Int64 {
        try db.run("""
            INSERT INTO SW_SCENARIO (USER_ID, SCENARIO_TITLE, SCENARIO_SUBTITLE, SCENARIO_WRITER_NAME, SCENARIO_MEMO, SCENARIO_DATE, SCENARIO_CATEGORY)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [.int(userId), .text(s.title), .text(s.subtitle), .text(s.writerName), .text(DBText.toDB(s.memo)), .text(Self.now()), .i(s.category)])
        return db.lastInsertRowId
    }

    public func updateScenario(_ s: Scenario) throws {
        try db.run("""
            UPDATE SW_SCENARIO SET SCENARIO_TITLE = ?, SCENARIO_SUBTITLE = ?, SCENARIO_WRITER_NAME = ?, SCENARIO_MEMO = ?, SCENARIO_DATE = ?, SCENARIO_CATEGORY = ?
            WHERE SCENARIO_ID = ?
            """, [.text(s.title), .text(s.subtitle), .text(s.writerName), .text(DBText.toDB(s.memo)), .text(Self.now()), .i(s.category), .int(s.id)])
    }

    /// 更新日時だけを今にする（台詞を直したときなど）
    public func touchScenario(id: Int64) throws {
        try db.run("UPDATE SW_SCENARIO SET SCENARIO_DATE = ? WHERE SCENARIO_ID = ?", [.text(Self.now()), .int(id)])
    }

    public func deleteScenario(id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_SCENE WHERE SCENARIO_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_CHARACTER WHERE SCENARIO_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_SYNOPSIS WHERE SCENARIO_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_PREVIEW WHERE SCENARIO_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_SCENARIO WHERE SCENARIO_ID = ?", [.int(id)])
        }
    }

    /// 新規作成。幕×場の場面と、空の登場人物枠をまとめて作る（Web 版「新規シナリオ」と同じ）。
    @discardableResult
    public func createScenario(_ s: Scenario, acts: Int, scenesPerAct: Int, actFormat: (String, String) = ("第", "幕"),
                               sceneFormat: (String, String) = ("　", "場"), characterCount: Int, characterPrefix: String = "登場人物") throws -> Int64 {
        try db.transaction {
            let id = try insertScenario(s)
            var order = 0.0
            for act in 1...max(acts, 1) where acts > 0 {
                for sc in 1...max(scenesPerAct, 1) where scenesPerAct > 0 {
                    order += 100
                    let name = acts > 1 || actFormat.0.isEmpty == false
                        ? "\(actFormat.0)\(act)\(actFormat.1)\(sceneFormat.0)\(sc)\(sceneFormat.1)"
                        : "\(sceneFormat.0)\(sc)\(sceneFormat.1)"
                    try db.run("INSERT INTO SW_SCENE (SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC) VALUES (?, ?, 0, ?, '', 0, 0)",
                               [.int(id), .real(order), .text(name)])
                }
            }
            order = 0
            for c in 1...max(characterCount, 1) where characterCount > 0 {
                order += 100
                try db.run("INSERT INTO SW_CHARACTER (SCENARIO_ID, CHARACTER_ORDER_NO, CHARACTER_NAME, CHARACTER_CHARA) VALUES (?, ?, ?, '')",
                           [.int(id), .real(order), .text("\(characterPrefix)\(c)")])
            }
            try db.run("INSERT INTO SW_SYNOPSIS (SCENARIO_ID, SYNOPSIS, UPDATE_DATE) VALUES (?, '', ?)", [.int(id), .text(Self.now())])
            return id
        }
    }

    /// 複写（Web 版「シナリオ複写」）。同じ DB の中に「〜のコピー」を作る
    @discardableResult
    public func copyScenario(id: Int64) throws -> Int64 {
        try importScenario(from: db, scenarioId: id, titleSuffix: "のコピー")
    }

    /// 別の DB（または自分自身）から 1 作品を丸ごと複製する。場面・登場人物・台詞・シノプシス・作品画像を写し、参照 ID を張り替える。
    @discardableResult
    public func importScenario(from src: SQLiteDatabase, scenarioId oldId: Int64, titleSuffix: String = "") throws -> Int64 {
        guard let sr = try src.query("SELECT * FROM SW_SCENARIO WHERE SCENARIO_ID = ?", [.int(oldId)]).first else {
            throw SQLiteError(code: 0, message: "シナリオがありません")
        }
        return try db.transaction {
            var s = Self.scenario(sr)
            s.title += titleSuffix
            try db.run("""
                INSERT INTO SW_SCENARIO (USER_ID, SCENARIO_TITLE, SCENARIO_SUBTITLE, SCENARIO_WRITER_NAME, SCENARIO_MEMO, SCENARIO_DATE, SCENARIO_CATEGORY)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, [.int(userId), .text(s.title), .text(s.subtitle), .text(s.writerName), .text(DBText.toDB(s.memo)),
                      .text(titleSuffix.isEmpty && !s.date.isEmpty ? s.date : Self.now()), .i(s.category)])
            let newId = db.lastInsertRowId
            var sceneMap: [Int64: Int64] = [:]
            for r in try src.query("SELECT * FROM SW_SCENE WHERE SCENARIO_ID = ? ORDER BY SCENE_ORDER_NO, SCENE_ID", [.int(oldId)]) {
                let sc = Self.scene(r)
                try db.run("INSERT INTO SW_SCENE (SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC, COPY_SOURCE_ID) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                           [.int(newId), .real(sc.orderNo), .i(sc.validCd), .text(sc.name), .text(DBText.toDB(sc.description)), .i(sc.timeMin), .i(sc.timeSec), .int(sc.id)])
                sceneMap[sc.id] = db.lastInsertRowId
            }
            var charMap: [Int64: Int64] = [:]
            for r in try src.query("SELECT * FROM SW_CHARACTER WHERE SCENARIO_ID = ? ORDER BY CHARACTER_ORDER_NO, CHARACTER_ID", [.int(oldId)]) {
                let c = Self.character(r)
                try db.run("INSERT INTO SW_CHARACTER (SCENARIO_ID, CHARACTER_ORDER_NO, CHARACTER_NAME, CHARACTER_CHARA, COPY_SOURCE_ID) VALUES (?, ?, ?, ?, ?)",
                           [.int(newId), .real(c.orderNo), .text(c.name), .text(DBText.toDB(c.chara)), .int(c.id)])
                charMap[c.id] = db.lastInsertRowId
            }
            let syn = DBText.fromDB(try src.query("SELECT SYNOPSIS FROM SW_SYNOPSIS WHERE SCENARIO_ID = ? ORDER BY SYNOPSIS_ID LIMIT 1", [.int(oldId)]).first?.text("SYNOPSIS"))
            try db.run("INSERT INTO SW_SYNOPSIS (SCENARIO_ID, SYNOPSIS, UPDATE_DATE) VALUES (?, ?, ?)", [.int(newId), .text(DBText.toDB(syn)), .text(Self.now())])
            for r in try src.query("SELECT * FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ? ORDER BY SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_LINES_ID", [.int(oldId)]) {
                let l = Self.line(r)
                guard let ns = sceneMap[l.sceneId] else { continue }
                let cv: SQLiteDatabase.SQLiteValue? = l.characterId.flatMap { charMap[$0] }.map { .int($0) }
                try db.run("INSERT INTO SW_SCENARIO_LINES (SCENARIO_ID, SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_TYPE, CHARACTER_ID, SCENARIO_LINES) VALUES (?, ?, ?, ?, ?, ?)",
                           [.int(newId), .int(ns), .real(l.orderNo), .i(l.type), cv, .text(DBText.toDB(l.text))])
            }
            if try src.tableExists("SW_SOLO_THUMB"),
               let png = try src.query("SELECT PNG FROM SW_SOLO_THUMB WHERE SCENARIO_ID = ?", [.int(oldId)]).first?.blob("PNG") {
                try setThumbnail(scenarioId: newId, png: png)
            }
            return newId
        }
    }

    public func scenarioCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM SW_SCENARIO") ?? 0) }
    public func firstScenarioId() throws -> Int64? { try db.scalarInt("SELECT MIN(SCENARIO_ID) FROM SW_SCENARIO").flatMap { $0 > 0 ? $0 : nil } }

    // MARK: - 作品画像

    public func thumbnail(scenarioId: Int64) throws -> Data? {
        try db.query("SELECT PNG FROM SW_SOLO_THUMB WHERE SCENARIO_ID = ?", [.int(scenarioId)]).first?.blob("PNG")
    }

    public func setThumbnail(scenarioId: Int64, png: Data?) throws {
        if let png {
            try db.run("INSERT OR REPLACE INTO SW_SOLO_THUMB (SCENARIO_ID, PNG, UPDATE_DATE) VALUES (?, ?, ?)", [.int(scenarioId), .blob(png), .text(Self.now())])
        } else {
            try db.run("DELETE FROM SW_SOLO_THUMB WHERE SCENARIO_ID = ?", [.int(scenarioId)])
        }
    }

    // MARK: - シノプシス

    public func synopsis(scenarioId: Int64) throws -> String {
        DBText.fromDB(try db.query("SELECT SYNOPSIS FROM SW_SYNOPSIS WHERE SCENARIO_ID = ? ORDER BY SYNOPSIS_ID LIMIT 1", [.int(scenarioId)]).first?.text("SYNOPSIS"))
    }

    public func saveSynopsis(scenarioId: Int64, text: String) throws {
        if let sid = try db.scalarInt("SELECT SYNOPSIS_ID FROM SW_SYNOPSIS WHERE SCENARIO_ID = ? ORDER BY SYNOPSIS_ID LIMIT 1", [.int(scenarioId)]) {
            try db.run("UPDATE SW_SYNOPSIS SET SYNOPSIS = ?, UPDATE_DATE = ? WHERE SYNOPSIS_ID = ?", [.text(DBText.toDB(text)), .text(Self.now()), .int(sid)])
        } else {
            try db.run("INSERT INTO SW_SYNOPSIS (SCENARIO_ID, SYNOPSIS, UPDATE_DATE) VALUES (?, ?, ?)", [.int(scenarioId), .text(DBText.toDB(text)), .text(Self.now())])
        }
    }

    // MARK: - 場面

    public func scenes(scenarioId: Int64) throws -> [ScriptScene] {
        try db.query("SELECT * FROM SW_SCENE WHERE SCENARIO_ID = ? ORDER BY SCENE_ORDER_NO, SCENE_ID", [.int(scenarioId)]).map(Self.scene)
    }

    static func scene(_ r: SQLiteDatabase.Row) -> ScriptScene {
        ScriptScene(id: r.int("SCENE_ID") ?? 0, scenarioId: r.int("SCENARIO_ID") ?? 0, orderNo: r.double("SCENE_ORDER_NO") ?? 0,
              validCd: r.intValue("SCENE_VALID_CD"), name: r.text("SCENE_NAME") ?? "",
              description: DBText.fromDB(r.text("SCENE_DESCRIPTION")), timeMin: r.intValue("SCENE_TIME_MIN"), timeSec: r.intValue("SCENE_TIME_SEC"))
    }

    /// 末尾に追加（orderNo は最大+100）
    @discardableResult
    public func insertScene(_ s: ScriptScene) throws -> Int64 {
        let maxNo = try db.query("SELECT MAX(SCENE_ORDER_NO) AS M FROM SW_SCENE WHERE SCENARIO_ID = ?", [.int(s.scenarioId)]).first?.double("M") ?? 0
        let order = s.orderNo > 0 ? s.orderNo : maxNo + 100
        try db.run("INSERT INTO SW_SCENE (SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC) VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [.int(s.scenarioId), .real(order), .i(s.validCd), .text(s.name), .text(DBText.toDB(s.description)), .i(s.timeMin), .i(s.timeSec)])
        let id = db.lastInsertRowId
        try renumberScenes(scenarioId: s.scenarioId)
        return id
    }

    /// 「○幕 ○場」をまとめて追加
    public func insertScenesInBulk(scenarioId: Int64, acts: Int, scenesPerAct: Int, actFormat: (String, String), sceneFormat: (String, String)) throws {
        try db.transaction {
            var maxNo = try db.query("SELECT MAX(SCENE_ORDER_NO) AS M FROM SW_SCENE WHERE SCENARIO_ID = ?", [.int(scenarioId)]).first?.double("M") ?? 0
            for act in 1...max(acts, 1) where acts > 0 {
                for sc in 1...max(scenesPerAct, 1) where scenesPerAct > 0 {
                    maxNo += 100
                    let name = "\(actFormat.0)\(act)\(actFormat.1)\(sceneFormat.0)\(sc)\(sceneFormat.1)"
                    try db.run("INSERT INTO SW_SCENE (SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC) VALUES (?, ?, 0, ?, '', 0, 0)",
                               [.int(scenarioId), .real(maxNo), .text(name)])
                }
            }
        }
    }

    /// 削除した場面を同じ ID で戻す（Undo 用）
    public func insertScene(restoring s: ScriptScene) throws {
        try db.run("INSERT INTO SW_SCENE (SCENE_ID, SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                   [.int(s.id), .int(s.scenarioId), .real(s.orderNo), .i(s.validCd), .text(s.name), .text(DBText.toDB(s.description)), .i(s.timeMin), .i(s.timeSec)])
    }

    public func updateScene(_ s: ScriptScene) throws {
        try db.run("UPDATE SW_SCENE SET SCENE_ORDER_NO = ?, SCENE_VALID_CD = ?, SCENE_NAME = ?, SCENE_DESCRIPTION = ?, SCENE_TIME_MIN = ?, SCENE_TIME_SEC = ? WHERE SCENE_ID = ?",
                   [.real(s.orderNo), .i(s.validCd), .text(s.name), .text(DBText.toDB(s.description)), .i(s.timeMin), .i(s.timeSec), .int(s.id)])
    }

    /// 場面とその台詞を削除
    public func deleteScene(id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM SW_SCENARIO_LINES WHERE SCENE_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_SCENE WHERE SCENE_ID = ?", [.int(id)])
        }
    }

    /// 並んだ順の ID を渡すと 100,200,... を振り直す
    public func reorderScenes(scenarioId: Int64, ids: [Int64]) throws {
        try db.transaction {
            var n = 0.0
            for id in ids {
                n += 100
                try db.run("UPDATE SW_SCENE SET SCENE_ORDER_NO = ? WHERE SCENE_ID = ? AND SCENARIO_ID = ?", [.real(n), .int(id), .int(scenarioId)])
            }
        }
    }

    public func renumberScenes(scenarioId: Int64) throws {
        try reorderScenes(scenarioId: scenarioId, ids: try scenes(scenarioId: scenarioId).map(\.id))
    }

    public func moveScene(id: Int64, scenarioId: Int64, up: Bool) throws {
        var ids = try scenes(scenarioId: scenarioId).map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        try reorderScenes(scenarioId: scenarioId, ids: ids)
    }

    // MARK: - 登場人物

    public func characters(scenarioId: Int64) throws -> [CastMember] {
        try db.query("SELECT * FROM SW_CHARACTER WHERE SCENARIO_ID = ? ORDER BY CHARACTER_ORDER_NO, CHARACTER_ID", [.int(scenarioId)]).map(Self.character)
    }

    static func character(_ r: SQLiteDatabase.Row) -> CastMember {
        CastMember(id: r.int("CHARACTER_ID") ?? 0, scenarioId: r.int("SCENARIO_ID") ?? 0, orderNo: r.double("CHARACTER_ORDER_NO") ?? 0,
                  name: r.text("CHARACTER_NAME") ?? "", chara: DBText.fromDB(r.text("CHARACTER_CHARA")))
    }

    @discardableResult
    public func insertCharacter(_ c: CastMember) throws -> Int64 {
        let maxNo = try db.query("SELECT MAX(CHARACTER_ORDER_NO) AS M FROM SW_CHARACTER WHERE SCENARIO_ID = ?", [.int(c.scenarioId)]).first?.double("M") ?? 0
        let order = c.orderNo > 0 ? c.orderNo : maxNo + 100
        try db.run("INSERT INTO SW_CHARACTER (SCENARIO_ID, CHARACTER_ORDER_NO, CHARACTER_NAME, CHARACTER_CHARA) VALUES (?, ?, ?, ?)",
                   [.int(c.scenarioId), .real(order), .text(c.name), .text(DBText.toDB(c.chara))])
        let id = db.lastInsertRowId
        try renumberCharacters(scenarioId: c.scenarioId)
        return id
    }

    /// 削除した登場人物を同じ ID で戻す（Undo 用）
    public func insertCharacter(restoring c: CastMember) throws {
        try db.run("INSERT INTO SW_CHARACTER (CHARACTER_ID, SCENARIO_ID, CHARACTER_ORDER_NO, CHARACTER_NAME, CHARACTER_CHARA) VALUES (?, ?, ?, ?, ?)",
                   [.int(c.id), .int(c.scenarioId), .real(c.orderNo), .text(c.name), .text(DBText.toDB(c.chara))])
    }

    /// 行の登場人物だけを差し替える（Undo 用）
    public func setCharacter(_ characterId: Int64?, forLines ids: [Int64]) throws {
        let cv: SQLiteDatabase.SQLiteValue? = characterId.map { .int($0) }
        for id in ids { try db.run("UPDATE SW_SCENARIO_LINES SET CHARACTER_ID = ? WHERE SCENARIO_LINES_ID = ?", [cv, .int(id)]) }
    }

    public func updateCharacter(_ c: CastMember) throws {
        try db.run("UPDATE SW_CHARACTER SET CHARACTER_ORDER_NO = ?, CHARACTER_NAME = ?, CHARACTER_CHARA = ? WHERE CHARACTER_ID = ?",
                   [.real(c.orderNo), .text(c.name), .text(DBText.toDB(c.chara)), .int(c.id)])
    }

    /// 人物を削除。使っている台詞は「名前なし」になる
    public func deleteCharacter(id: Int64) throws {
        try db.transaction {
            try db.run("UPDATE SW_SCENARIO_LINES SET CHARACTER_ID = NULL WHERE CHARACTER_ID = ?", [.int(id)])
            try db.run("DELETE FROM SW_CHARACTER WHERE CHARACTER_ID = ?", [.int(id)])
        }
    }

    public func reorderCharacters(scenarioId: Int64, ids: [Int64]) throws {
        try db.transaction {
            var n = 0.0
            for id in ids {
                n += 100
                try db.run("UPDATE SW_CHARACTER SET CHARACTER_ORDER_NO = ? WHERE CHARACTER_ID = ? AND SCENARIO_ID = ?", [.real(n), .int(id), .int(scenarioId)])
            }
        }
    }

    public func renumberCharacters(scenarioId: Int64) throws {
        try reorderCharacters(scenarioId: scenarioId, ids: try characters(scenarioId: scenarioId).map(\.id))
    }

    public func moveCharacter(id: Int64, scenarioId: Int64, up: Bool) throws {
        var ids = try characters(scenarioId: scenarioId).map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        try reorderCharacters(scenarioId: scenarioId, ids: ids)
    }

    // MARK: - 台詞（行）

    public func lines(sceneId: Int64) throws -> [ScriptLine] {
        try db.query("SELECT * FROM SW_SCENARIO_LINES WHERE SCENE_ID = ? ORDER BY SCENARIO_LINES_ORDER_NO, SCENARIO_LINES_ID", [.int(sceneId)]).map(Self.line)
    }

    public func allLines(scenarioId: Int64) throws -> [ScriptLine] {
        try db.query("SELECT * FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ? ORDER BY SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_LINES_ID", [.int(scenarioId)]).map(Self.line)
    }

    /// 場面ごとの行数（サイドバー表示用）
    public func lineCounts(scenarioId: Int64) throws -> [Int64: Int] {
        var d: [Int64: Int] = [:]
        for r in try db.query("SELECT SCENE_ID, COUNT(*) AS N FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ? GROUP BY SCENE_ID", [.int(scenarioId)]) {
            if let sid = r.int("SCENE_ID") { d[sid] = r.intValue("N") }
        }
        return d
    }

    public func line(id: Int64) throws -> ScriptLine? {
        try db.query("SELECT * FROM SW_SCENARIO_LINES WHERE SCENARIO_LINES_ID = ?", [.int(id)]).first.map(Self.line)
    }

    static func line(_ r: SQLiteDatabase.Row) -> ScriptLine {
        ScriptLine(id: r.int("SCENARIO_LINES_ID") ?? 0, scenarioId: r.int("SCENARIO_ID") ?? 0, sceneId: r.int("SCENE_ID") ?? 0,
                   orderNo: r.double("SCENARIO_LINES_ORDER_NO") ?? 0, type: r.intValue("SCENARIO_TYPE", 1),
                   characterId: r.int("CHARACTER_ID").flatMap { $0 > 0 ? $0 : nil }, text: DBText.fromDB(r.text("SCENARIO_LINES")))
    }

    /// 行を追加。`afterLineId` の直後（nil なら末尾）に入れて振り直す。
    @discardableResult
    public func insertLine(_ l: ScriptLine, after afterLineId: Int64?) throws -> Int64 {
        try db.transaction {
            var order: Double
            if let a = afterLineId, let after = try line(id: a) {
                order = after.orderNo + 1
            } else if afterLineId == nil {
                order = (try db.query("SELECT MAX(SCENARIO_LINES_ORDER_NO) AS M FROM SW_SCENARIO_LINES WHERE SCENE_ID = ?", [.int(l.sceneId)]).first?.double("M") ?? 0) + 100
            } else {
                order = 0.5 // 先頭
            }
            if afterLineId == 0 { order = 0.5 }
            let charVal: SQLiteDatabase.SQLiteValue? = l.characterId.map { .int($0) }
            try db.run("INSERT INTO SW_SCENARIO_LINES (SCENARIO_ID, SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_TYPE, CHARACTER_ID, SCENARIO_LINES) VALUES (?, ?, ?, ?, ?, ?)",
                       [.int(l.scenarioId), .int(l.sceneId), .real(order), .i(l.type), charVal, .text(DBText.toDB(l.text))])
            let id = db.lastInsertRowId
            try renumberLines(sceneId: l.sceneId)
            try touchScenario(id: l.scenarioId)
            return id
        }
    }

    /// 削除した行を同じ ID・並び順で戻す（Undo 用）。並び順の振り直しはしない
    public func insertLine(restoring l: ScriptLine) throws {
        let charVal: SQLiteDatabase.SQLiteValue? = l.characterId.map { .int($0) }
        try db.run("INSERT INTO SW_SCENARIO_LINES (SCENARIO_LINES_ID, SCENARIO_ID, SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_TYPE, CHARACTER_ID, SCENARIO_LINES) VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [.int(l.id), .int(l.scenarioId), .int(l.sceneId), .real(l.orderNo), .i(l.type), charVal, .text(DBText.toDB(l.text))])
        try touchScenario(id: l.scenarioId)
    }

    public func updateLine(_ l: ScriptLine) throws {
        let charVal: SQLiteDatabase.SQLiteValue? = l.characterId.map { .int($0) }
        try db.run("UPDATE SW_SCENARIO_LINES SET SCENARIO_TYPE = ?, CHARACTER_ID = ?, SCENARIO_LINES = ? WHERE SCENARIO_LINES_ID = ?",
                   [.i(l.type), charVal, .text(DBText.toDB(l.text)), .int(l.id)])
        try touchScenario(id: l.scenarioId)
    }

    public func deleteLine(id: Int64) throws {
        guard let l = try line(id: id) else { return }
        try db.run("DELETE FROM SW_SCENARIO_LINES WHERE SCENARIO_LINES_ID = ?", [.int(id)])
        try renumberLines(sceneId: l.sceneId)
        try touchScenario(id: l.scenarioId)
    }

    public func reorderLines(sceneId: Int64, ids: [Int64]) throws {
        try db.transaction {
            var n = 0.0
            for id in ids {
                n += 100
                try db.run("UPDATE SW_SCENARIO_LINES SET SCENARIO_LINES_ORDER_NO = ? WHERE SCENARIO_LINES_ID = ? AND SCENE_ID = ?", [.real(n), .int(id), .int(sceneId)])
            }
        }
    }

    public func renumberLines(sceneId: Int64) throws {
        try reorderLines(sceneId: sceneId, ids: try lines(sceneId: sceneId).map(\.id))
    }

    public func moveLine(id: Int64, up: Bool) throws {
        guard let l = try line(id: id) else { return }
        var ids = try lines(sceneId: l.sceneId).map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        try reorderLines(sceneId: l.sceneId, ids: ids)
    }

    /// 行を別の場面の末尾へ移す
    public func moveLine(id: Int64, toScene sceneId: Int64) throws {
        guard let l = try line(id: id), l.sceneId != sceneId else { return }
        let maxNo = try db.query("SELECT MAX(SCENARIO_LINES_ORDER_NO) AS M FROM SW_SCENARIO_LINES WHERE SCENE_ID = ?", [.int(sceneId)]).first?.double("M") ?? 0
        try db.run("UPDATE SW_SCENARIO_LINES SET SCENE_ID = ?, SCENARIO_LINES_ORDER_NO = ? WHERE SCENARIO_LINES_ID = ?", [.int(sceneId), .real(maxNo + 100), .int(id)])
        try renumberLines(sceneId: l.sceneId)
    }

    public struct SearchHit: Identifiable, Hashable, Sendable {
        public var id: Int64 { line.id }
        public var line: ScriptLine
        public var sceneName: String
    }

    /// 作品全体の台詞から検索（大文字小文字を区別しない部分一致）
    public func searchLines(scenarioId: Int64, query: String) throws -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let esc = q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        let dbq = DBText.toDB(esc)
        return try db.query("""
            SELECT L.*, S.SCENE_NAME, S.SCENE_ORDER_NO FROM SW_SCENARIO_LINES L
              LEFT JOIN SW_SCENE S ON S.SCENE_ID = L.SCENE_ID
              WHERE L.SCENARIO_ID = ? AND L.SCENARIO_LINES LIKE ? ESCAPE '\\'
              ORDER BY S.SCENE_ORDER_NO, L.SCENARIO_LINES_ORDER_NO
            """, [.int(scenarioId), .text("%\(dbq)%")]).map { SearchHit(line: Self.line($0), sceneName: $0.text("SCENE_NAME") ?? "") }
    }

    /// 作品全体で置換。置換した行数を返す
    @discardableResult
    public func replaceInLines(scenarioId: Int64, search: String, replacement: String) throws -> Int {
        guard !search.isEmpty else { return 0 }
        var count = 0
        try db.transaction {
            for l in try allLines(scenarioId: scenarioId) where l.text.contains(search) {
                var nl = l
                nl.text = l.text.replacingOccurrences(of: search, with: replacement)
                try db.run("UPDATE SW_SCENARIO_LINES SET SCENARIO_LINES = ? WHERE SCENARIO_LINES_ID = ?", [.text(DBText.toDB(nl.text)), .int(l.id)])
                count += 1
            }
            if count > 0 { try touchScenario(id: scenarioId) }
        }
        return count
    }

    // MARK: - スタイル・オプション

    public func styles() throws -> [LineStyle] {
        try db.query("""
            SELECT O.*, M.MARGIN_BEFORE, M.MARGIN_AFTER FROM SW_USER_OPTION O
              LEFT JOIN SW_SOLO_STYLE_MARGIN M ON M.USER_ID = O.USER_ID AND M.STYLE_ID = O.USER_OPTION_STYLE_ID
              WHERE O.USER_ID = ? ORDER BY O.USER_OPTION_STYLE_ORDER_NO, O.USER_OPTION_STYLE_ID
            """, [.int(userId)]).map(Self.style)
    }

    private func saveMargins(_ s: LineStyle, styleId: Int) throws {
        if s.marginBefore == 0 && s.marginAfter == 0 {
            try db.run("DELETE FROM SW_SOLO_STYLE_MARGIN WHERE USER_ID = ? AND STYLE_ID = ?", [.int(userId), .i(styleId)])
        } else {
            try db.run("INSERT OR REPLACE INTO SW_SOLO_STYLE_MARGIN (USER_ID, STYLE_ID, MARGIN_BEFORE, MARGIN_AFTER) VALUES (?, ?, ?, ?)",
                       [.int(userId), .i(styleId), .i(max(s.marginBefore, 0)), .i(max(s.marginAfter, 0))])
        }
    }

    static func style(_ r: SQLiteDatabase.Row) -> LineStyle {
        LineStyle(id: r.int("USER_OPTION_ID") ?? 0, userId: r.int("USER_ID") ?? 0, styleId: r.intValue("USER_OPTION_STYLE_ID"),
                  orderNo: r.intValue("USER_OPTION_STYLE_ORDER_NO"), name: r.text("USER_OPTION_STYLE_NAME") ?? "",
                  fontSize: r.intValue("USER_OPTION_STYLE_FONT_SIZE", 12), color: r.text("USER_OPTION_STYLE_COLOR") ?? "#000000",
                  indent: r.intValue("USER_OPTION_STYLE_INDENT"), abbreviation: r.text("USER_OPTION_STYLE_STR") ?? "",
                  wordMode: r.intValue("USER_OPTION_STYLE_WORD"),
                  marginBefore: r.intValue("MARGIN_BEFORE"), marginAfter: r.intValue("MARGIN_AFTER"))
    }

    @discardableResult
    public func insertStyle(_ s: LineStyle) throws -> Int64 {
        let maxId = try db.scalarInt("SELECT MAX(USER_OPTION_STYLE_ID) FROM SW_USER_OPTION WHERE USER_ID = ?", [.int(userId)]) ?? 0
        let maxOrder = try db.scalarInt("SELECT MAX(USER_OPTION_STYLE_ORDER_NO) FROM SW_USER_OPTION WHERE USER_ID = ?", [.int(userId)]) ?? 0
        let styleId = s.styleId > 0 ? s.styleId : Int(maxId) + 1
        let order = s.orderNo > 0 ? s.orderNo : Int(maxOrder) + 100
        try db.run("""
            INSERT INTO SW_USER_OPTION (USER_ID, USER_OPTION_STYLE_ID, USER_OPTION_STYLE_ORDER_NO, USER_OPTION_STYLE_NAME, USER_OPTION_STYLE_FONT_SIZE,
              USER_OPTION_STYLE_COLOR, USER_OPTION_STYLE_INDENT, USER_OPTION_STYLE_STR, USER_OPTION_STYLE_WORD) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.int(userId), .i(styleId), .i(order), .text(s.name), .i(s.fontSize), .text(s.color), .i(s.indent), .text(s.abbreviation), .i(s.wordMode)])
        let id = db.lastInsertRowId
        try saveMargins(s, styleId: styleId)
        return id
    }

    public func updateStyle(_ s: LineStyle) throws {
        try db.run("""
            UPDATE SW_USER_OPTION SET USER_OPTION_STYLE_ORDER_NO = ?, USER_OPTION_STYLE_NAME = ?, USER_OPTION_STYLE_FONT_SIZE = ?, USER_OPTION_STYLE_COLOR = ?,
              USER_OPTION_STYLE_INDENT = ?, USER_OPTION_STYLE_STR = ?, USER_OPTION_STYLE_WORD = ? WHERE USER_OPTION_ID = ?
            """, [.i(s.orderNo), .text(s.name), .i(s.fontSize), .text(s.color), .i(s.indent), .text(s.abbreviation), .i(s.wordMode), .int(s.id)])
        try saveMargins(s, styleId: s.styleId)
    }

    public func deleteStyle(id: Int64) throws {
        if let sid = try db.scalarInt("SELECT USER_OPTION_STYLE_ID FROM SW_USER_OPTION WHERE USER_OPTION_ID = ?", [.int(id)]) {
            try db.run("DELETE FROM SW_SOLO_STYLE_MARGIN WHERE USER_ID = ? AND STYLE_ID = ?", [.int(userId), .int(sid)])
        }
        try db.run("DELETE FROM SW_USER_OPTION WHERE USER_OPTION_ID = ?", [.int(id)])
    }

    // MARK: 固定スタイル（シノプシス・場面説明・登場人物）

    static func textStyle(_ r: SQLiteDatabase.Row) -> TextStyle? {
        guard let kind = TextStyleKind(rawValue: r.text("KIND") ?? "") else { return nil }
        return TextStyle(kind: kind, fontSize: r.intValue("FONT_SIZE", 14), color: r.text("COLOR") ?? "#000000",
                         indent: r.intValue("INDENT"), marginBefore: r.intValue("MARGIN_BEFORE"), marginAfter: r.intValue("MARGIN_AFTER"))
    }

    /// 固定スタイルを種類の順に全部返す（保存していない種類は既定値）
    public func textStyles() throws -> [TextStyle] {
        let saved = try db.query("SELECT * FROM SW_SOLO_TEXT_STYLE WHERE USER_ID = ?", [.int(userId)]).compactMap(Self.textStyle)
        return TextStyleKind.allCases.map { k in saved.first { $0.kind == k } ?? .default(k) }
    }

    public func saveTextStyle(_ t: TextStyle) throws {
        try db.run("INSERT OR REPLACE INTO SW_SOLO_TEXT_STYLE (USER_ID, KIND, FONT_SIZE, COLOR, INDENT, MARGIN_BEFORE, MARGIN_AFTER) VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [.int(userId), .text(t.kind.rawValue), .i(t.fontSize), .text(t.color), .i(max(t.indent, 0)), .i(max(t.marginBefore, 0)), .i(max(t.marginAfter, 0))])
    }

    public func replaceTextStyles(_ ts: [TextStyle]) throws {
        try db.transaction {
            try db.run("DELETE FROM SW_SOLO_TEXT_STYLE WHERE USER_ID = ?", [.int(userId)])
            for t in ts { try saveTextStyle(t) }
        }
    }

    /// 既定スタイルに戻す（自分のスタイルを全部消して既定を入れる。固定スタイルも既定に戻す）
    public func resetStylesToDefault() throws {
        try db.transaction {
            try db.run("DELETE FROM SW_USER_OPTION WHERE USER_ID = ?", [.int(userId)])
            try db.run("DELETE FROM SW_SOLO_STYLE_MARGIN WHERE USER_ID = ?", [.int(userId)])
            try db.run("DELETE FROM SW_SOLO_TEXT_STYLE WHERE USER_ID = ?", [.int(userId)])
            for d in Self.defaultStyles {
                try db.run("""
                    INSERT INTO SW_USER_OPTION (USER_ID, USER_OPTION_STYLE_ID, USER_OPTION_STYLE_ORDER_NO, USER_OPTION_STYLE_NAME, USER_OPTION_STYLE_FONT_SIZE,
                      USER_OPTION_STYLE_COLOR, USER_OPTION_STYLE_INDENT, USER_OPTION_STYLE_STR, USER_OPTION_STYLE_WORD) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.int(userId), .i(d.0), .i(d.1), .text(d.2), .i(d.3), .text(d.4), .i(d.5), .text(d.6), .i(d.7)])
                if d.8 > 0 || d.9 > 0 {
                    try db.run("INSERT OR REPLACE INTO SW_SOLO_STYLE_MARGIN (USER_ID, STYLE_ID, MARGIN_BEFORE, MARGIN_AFTER) VALUES (?, ?, ?, ?)",
                               [.int(userId), .i(d.0), .i(d.8), .i(d.9)])
                }
            }
        }
    }

    /// スタイルと書式設定をまるごと置き換える（作品ファイルに共通設定を写すときに使う）
    public func replaceStyles(_ styles: [LineStyle], textStyles: [TextStyle]? = nil, setting: OptionSetting) throws {
        try db.transaction {
            if let textStyles { try replaceTextStyles(textStyles) }
            try db.run("DELETE FROM SW_USER_OPTION WHERE USER_ID = ?", [.int(userId)])
            try db.run("DELETE FROM SW_SOLO_STYLE_MARGIN WHERE USER_ID = ?", [.int(userId)])
            for st in styles {
                try db.run("""
                    INSERT INTO SW_USER_OPTION (USER_ID, USER_OPTION_STYLE_ID, USER_OPTION_STYLE_ORDER_NO, USER_OPTION_STYLE_NAME, USER_OPTION_STYLE_FONT_SIZE,
                      USER_OPTION_STYLE_COLOR, USER_OPTION_STYLE_INDENT, USER_OPTION_STYLE_STR, USER_OPTION_STYLE_WORD) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.int(userId), .i(st.styleId), .i(st.orderNo), .text(st.name), .i(st.fontSize), .text(st.color), .i(st.indent), .text(st.abbreviation), .i(st.wordMode)])
                try saveMargins(st, styleId: st.styleId)
            }
            try saveSetting(setting)
        }
    }

    public func setting() throws -> OptionSetting {
        guard let r = try db.query("SELECT * FROM SW_USER_OPTION_SETTING WHERE USER_ID = ?", [.int(userId)]).first else { return OptionSetting() }
        return OptionSetting(characterLength: r.intValue("CHARACTER_LENGTH", 8), bodyLength: r.intValue("BODY_LENGTH", 32), useKagikakko: r.intValue("USE_KAGIKAKKO", 1) != 0)
    }

    public func saveSetting(_ s: OptionSetting) throws {
        try db.run("INSERT OR REPLACE INTO SW_USER_OPTION_SETTING (USER_ID, CHARACTER_LENGTH, BODY_LENGTH, USE_KAGIKAKKO) VALUES (?, ?, ?, ?)",
                   [.int(userId), .i(s.characterLength), .i(s.bodyLength), .i(s.useKagikakko ? 1 : 0)])
    }

    // MARK: - 1 作品まとめて読む（出力用）

    public func document(scenarioId: Int64) throws -> ScenarioDocument? {
        guard let sc = try scenario(id: scenarioId) else { return nil }
        let scenes = try self.scenes(scenarioId: scenarioId)
        var byScene: [Int64: [ScriptLine]] = [:]
        for l in try allLines(scenarioId: scenarioId) { byScene[l.sceneId, default: []].append(l) }
        return ScenarioDocument(scenario: sc, synopsis: try synopsis(scenarioId: scenarioId), characters: try characters(scenarioId: scenarioId),
                                scenes: scenes, linesByScene: byScene, styles: try styles(), setting: try setting(), textStyles: try textStyles())
    }

    // MARK: - 取り込み（Web 版の swdata.sqlite / 別のバックアップから）

    /// フォルダ（sw_config）が渡されたら中の swdata.sqlite（無ければ最初の *.sqlite）を使う
    static func resolveDatabaseFile(_ url: URL) throws -> URL {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { throw SQLiteError(code: 0, message: "ファイルがありません: \(url.path)") }
        guard isDir.boolValue else { return url }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if names.contains("swdata.sqlite") { return url.appendingPathComponent("swdata.sqlite") }
        if let n = names.sorted().first(where: { $0.hasSuffix(".sqlite") || $0.hasSuffix("." + workFileExtension) }) { return url.appendingPathComponent(n) }
        throw SQLiteError(code: 0, message: "このフォルダに .sqlite ファイルがありません")
    }

    /// 取り込み元（Web 版の swdata.sqlite / sw_config フォルダ / Solo の作品ファイル）を一時フォルダへ複製して開く。
    /// Web 版の DB は WAL モードで直近の更新が -wal に残っていることがあるので、-wal / -shm も一緒に複製して通常モードで開く。
    /// 返ってきた cleanup を最後に呼ぶ。
    public static func openSource(_ url: URL) throws -> (db: SQLiteDatabase, cleanup: () -> Void) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let mainURL = try resolveDatabaseFile(url)
        let copy = tmp.appendingPathComponent("import.sqlite")
        try FileManager.default.copyItem(at: mainURL, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: mainURL.path + suffix)
            if FileManager.default.isReadableFile(atPath: side.path) {
                try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        let db = try SQLiteDatabase(path: copy.path)
        guard try db.tableExists("SW_SCENARIO") else {
            try? FileManager.default.removeItem(at: tmp)
            throw SQLiteError(code: 0, message: "ScenarioWriterCafe のデータベースではありません（SW_SCENARIO 表がありません）")
        }
        return (db, { try? FileManager.default.removeItem(at: tmp) })
    }

    /// 取り込み元の作品一覧
    public static func scenarios(in src: SQLiteDatabase) throws -> [Scenario] {
        try src.query("SELECT * FROM SW_SCENARIO ORDER BY SCENARIO_ID").map(Self.scenario)
    }

    /// 取り込み元の先頭ユーザーのスタイルと書式設定（無ければ nil）
    public static func styles(in src: SQLiteDatabase) throws -> (styles: [LineStyle], textStyles: [TextStyle], setting: OptionSetting)? {
        guard try src.tableExists("SW_USER_OPTION"),
              let srcUser = try src.scalarInt("SELECT MIN(USER_ID) FROM SW_USER_OPTION WHERE USER_ID > 0") else { return nil }
        let hasMargin = try src.tableExists("SW_SOLO_STYLE_MARGIN")
        let rows = hasMargin
            ? try src.query("""
                SELECT O.*, M.MARGIN_BEFORE, M.MARGIN_AFTER FROM SW_USER_OPTION O
                  LEFT JOIN SW_SOLO_STYLE_MARGIN M ON M.USER_ID = O.USER_ID AND M.STYLE_ID = O.USER_OPTION_STYLE_ID
                  WHERE O.USER_ID = ? ORDER BY O.USER_OPTION_STYLE_ORDER_NO
                """, [.int(srcUser)])
            : try src.query("SELECT * FROM SW_USER_OPTION WHERE USER_ID = ? ORDER BY USER_OPTION_STYLE_ORDER_NO", [.int(srcUser)])
        guard !rows.isEmpty else { return nil }
        var setting = OptionSetting()
        if try src.tableExists("SW_USER_OPTION_SETTING"),
           let r = try src.query("SELECT * FROM SW_USER_OPTION_SETTING WHERE USER_ID = ?", [.int(srcUser)]).first {
            let kagi = (try? src.columnExists(table: "SW_USER_OPTION_SETTING", column: "USE_KAGIKAKKO")) == true ? r.intValue("USE_KAGIKAKKO", 1) != 0 : true
            setting = OptionSetting(characterLength: r.intValue("CHARACTER_LENGTH", 8), bodyLength: r.intValue("BODY_LENGTH", 32), useKagikakko: kagi)
        }
        var textStyles = TextStyle.defaults
        if try src.tableExists("SW_SOLO_TEXT_STYLE") {
            let saved = try src.query("SELECT * FROM SW_SOLO_TEXT_STYLE WHERE USER_ID = ?", [.int(srcUser)]).compactMap(Self.textStyle)
            textStyles = TextStyleKind.allCases.map { k in saved.first { $0.kind == k } ?? .default(k) }
        }
        return (rows.map(Self.style), textStyles, setting)
    }

    public struct ImportResult: Sendable {
        public var scenarios = 0
        public var scenes = 0
        public var characters = 0
        public var lines = 0
        public var importedStyles = false
    }

    /// 別の ScenarioWriterCafe / Solo の SQLite からシナリオを全部この DB に取り込む（ユーザーは問わず自分の作品にする）。
    /// `stylesToo` が true なら、相手の先頭ユーザーのスタイルとオプション設定で自分のものを置き換える。
    public func importAll(from sourceURL: URL, stylesToo: Bool) throws -> ImportResult {
        let (src, cleanup) = try Self.openSource(sourceURL)
        defer { cleanup() }
        var result = ImportResult()
        for s in try Self.scenarios(in: src) {
            let newId = try importScenario(from: src, scenarioId: s.id)
            result.scenarios += 1
            result.scenes += Int(try db.scalarInt("SELECT COUNT(*) FROM SW_SCENE WHERE SCENARIO_ID = ?", [.int(newId)]) ?? 0)
            result.characters += Int(try db.scalarInt("SELECT COUNT(*) FROM SW_CHARACTER WHERE SCENARIO_ID = ?", [.int(newId)]) ?? 0)
            result.lines += Int(try db.scalarInt("SELECT COUNT(*) FROM SW_SCENARIO_LINES WHERE SCENARIO_ID = ?", [.int(newId)]) ?? 0)
        }
        if stylesToo, let st = try Self.styles(in: src) {
            try replaceStyles(st.styles, setting: st.setting)
            result.importedStyles = true
        }
        return result
    }

    // MARK: - 作品ファイル（.scwd = JSON。ScenarioFile を見る。作業用コピーは SQLite）

    public struct WorkSummary: Identifiable, Hashable, Sendable {
        public var url: URL
        public var scenario: Scenario
        public var thumbnail: Data?
        public var id: String { url.path }
    }

    /// 作品ファイルの作品情報を読む（一覧表示用）。JSON の作品ファイルと、作業用コピー（SQLite）のどちらも読める。読めなければ nil
    public static func summary(of url: URL) -> WorkSummary? {
        guard let head = try? FileHandle(forReadingFrom: url).read(upToCount: 16), !ScenarioFile.isSQLite(head) else { return sqliteSummary(of: url) }
        guard let data = try? Data(contentsOf: url), let f = try? ScenarioFile.decode(data) else { return nil }
        let sc = Scenario(title: f.scenario.title, subtitle: f.scenario.subtitle, writerName: f.scenario.writer, memo: f.scenario.memo,
                          date: f.scenario.date, category: f.scenario.category)
        return WorkSummary(url: url, scenario: sc, thumbnail: f.thumbnail.flatMap { Data(base64Encoded: $0) })
    }

    static func sqliteSummary(of url: URL) -> WorkSummary? {
        guard let db = try? SQLiteDatabase(path: url.path, readOnly: true),
              (try? db.tableExists("SW_SCENARIO")) == true,
              let r = try? db.query("SELECT * FROM SW_SCENARIO ORDER BY SCENARIO_ID LIMIT 1").first else { return nil }
        let sc = scenario(r)
        let thumb = (try? db.tableExists("SW_SOLO_THUMB")) == true
            ? try? db.query("SELECT PNG FROM SW_SOLO_THUMB WHERE SCENARIO_ID = ?", [.int(sc.id)]).first?.blob("PNG") : nil
        return WorkSummary(url: url, scenario: sc, thumbnail: thumb ?? nil)
    }

    /// フォルダ内の作品ファイル一覧（更新日時の新しい順）
    public static func works(in folder: URL) -> [WorkSummary] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix("." + workFileExtension) && !$0.hasPrefix(".") }
            .compactMap { summary(of: folder.appendingPathComponent($0)) }
            .sorted { ($0.scenario.date, $0.url.lastPathComponent) > ($1.scenario.date, $1.url.lastPathComponent) }
    }

    /// タイトルから、そのフォルダでまだ使われていないファイル名を作る
    public static func uniqueWorkURL(in folder: URL, title: String) -> URL {
        let base = TextFormat.safeFileName(title, fallback: "無題")
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let u = folder.appendingPathComponent(name).appendingPathExtension(workFileExtension)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }
}
