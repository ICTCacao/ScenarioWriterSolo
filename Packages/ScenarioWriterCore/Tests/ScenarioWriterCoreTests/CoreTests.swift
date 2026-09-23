import XCTest
@testable import ScenarioWriterCore

final class CoreTests: XCTestCase {
    func tempStore() throws -> ScenarioStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-test-\(UUID().uuidString)")
        return try ScenarioStore(url: dir.appendingPathComponent("swdata.sqlite"))
    }

    func testScenarioFileRoundTrip() throws {
        let store = try tempStore()
        let id = try store.createScenario(Scenario(title: "往復", subtitle: "副題", writerName: "作者", category: 1), acts: 1, scenesPerAct: 2, characterCount: 2)
        let scenes = try store.scenes(scenarioId: id)
        let chars = try store.characters(scenarioId: id)
        try store.saveSynopsis(scenarioId: id, text: "あらすじ\n二行目")
        try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[0].id, type: 1, characterId: chars[1].id, text: "こんにちは。\n二行目"), after: nil)
        try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[0].id, type: 2, text: "ト書き"), after: nil)
        try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[1].id, type: 1, characterId: chars[0].id, text: "二場目"), after: nil)
        var t = TextStyle.default(.synopsis); t.fontSize = 18; try store.saveTextStyle(t)
        try store.setThumbnail(scenarioId: id, png: Data([0x89, 0x50, 0x4E, 0x47]))

        let file = try store.exportFile(scenarioId: id, app: "test")
        let data = try file.encode()
        XCTAssertTrue(ScenarioFile.isJSON(data))
        XCTAssertFalse(ScenarioFile.isSQLite(data))
        let back = try ScenarioFile.decode(data)
        XCTAssertEqual(back, file)
        XCTAssertEqual(back.scenes.count, 2)
        XCTAssertEqual(back.scenes[0].lines.count, 2)
        XCTAssertEqual(back.scenes[0].lines[0].text, "こんにちは。\n二行目")
        XCTAssertEqual(back.textStyles["synopsis"]?.size, 18)

        let other = try tempStore()
        let nid = try other.importFile(back)
        XCTAssertEqual(try other.scenario(id: nid)?.title, "往復")
        XCTAssertEqual(try other.synopsis(scenarioId: nid), "あらすじ\n二行目")
        let lines2 = try other.allLines(scenarioId: nid)
        XCTAssertEqual(lines2.count, 3)
        let chars2 = try other.characters(scenarioId: nid)
        XCTAssertEqual(lines2[0].characterId, chars2[1].id)   // 人物の参照が張り替わる
        XCTAssertEqual(try other.textStyles().first { $0.kind == .synopsis }?.fontSize, 18)
        XCTAssertEqual(try other.thumbnail(scenarioId: nid)?.count, 4)
        XCTAssertEqual(try other.exportFile(scenarioId: nid, app: "test").scenes, file.scenes)

        // 一覧用の読み取り（JSON ファイル）
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-\(UUID().uuidString).scwd")
        try data.write(to: url)
        XCTAssertEqual(ScenarioStore.summary(of: url)?.scenario.title, "往復")
        // 壊れたファイル・別の JSON
        XCTAssertThrowsError(try ScenarioFile.decode(Data("{\"format\":\"other\"}".utf8)))
        XCTAssertThrowsError(try ScenarioFile.decode(Data("SQLite format 3".utf8)))
    }

    func testTextStyles() throws {
        let store = try tempStore()
        XCTAssertEqual(try store.textStyles().count, TextStyleKind.allCases.count)
        XCTAssertEqual(try store.textStyles().first { $0.kind == .sceneDescription }?.color, "#006400")
        var t = TextStyle.default(.synopsis); t.fontSize = 20; t.marginAfter = 2
        try store.saveTextStyle(t)
        XCTAssertEqual(try store.textStyles().first { $0.kind == .synopsis }?.fontSize, 20)
        // 別の DB に写す
        let other = try tempStore()
        try other.replaceStyles(try store.styles(), textStyles: try store.textStyles(), setting: try store.setting())
        XCTAssertEqual(try other.textStyles().first { $0.kind == .synopsis }?.marginAfter, 2)
        XCTAssertEqual(try ScenarioStore.styles(in: other.db)?.textStyles.first { $0.kind == .synopsis }?.fontSize, 20)
        // 既定に戻す
        try store.resetStylesToDefault()
        XCTAssertEqual(try store.textStyles().first { $0.kind == .synopsis }?.fontSize, 14)
    }

    func testCreateEditCopy() throws {
        let store = try tempStore()
        XCTAssertEqual(try store.styles().count, ScenarioStore.defaultStyles.count)
        XCTAssertEqual(try store.styles().first { $0.styleId == 2 }?.marginBefore, 1)
        let id = try store.createScenario(Scenario(title: "テスト", writerName: "作者"), acts: 1, scenesPerAct: 2, characterCount: 2)
        let scenes = try store.scenes(scenarioId: id)
        XCTAssertEqual(scenes.count, 2)
        let chars = try store.characters(scenarioId: id)
        XCTAssertEqual(chars.count, 2)
        let l1 = try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[0].id, type: 1, characterId: chars[0].id, text: "こんにちは。\n二行目"), after: nil)
        let l2 = try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[0].id, type: 2, text: "ト書き"), after: nil)
        _ = try store.insertLine(ScriptLine(scenarioId: id, sceneId: scenes[0].id, type: 1, characterId: chars[1].id, text: "間に入る"), after: l1)
        let lines = try store.lines(sceneId: scenes[0].id)
        XCTAssertEqual(lines.map(\.text), ["こんにちは。\n二行目", "間に入る", "ト書き"])
        XCTAssertEqual(lines.map(\.orderNo), [100, 200, 300])
        try store.moveLine(id: l2, up: true)
        XCTAssertEqual(try store.lines(sceneId: scenes[0].id).map(\.id)[1], l2)
        // DB には <br> で入る
        let raw = try store.db.query("SELECT SCENARIO_LINES FROM SW_SCENARIO_LINES WHERE SCENARIO_LINES_ID = ?", [.int(l1)]).first?.text("SCENARIO_LINES")
        XCTAssertEqual(raw, "こんにちは。<br>二行目")
        XCTAssertEqual(try store.searchLines(scenarioId: id, query: "二行").count, 1)
        XCTAssertEqual(try store.replaceInLines(scenarioId: id, search: "こんにちは", replacement: "やあ"), 1)
        try store.saveSynopsis(scenarioId: id, text: "あらすじ")
        let copyId = try store.copyScenario(id: id)
        let copy = try store.scenario(id: copyId)!
        XCTAssertEqual(copy.title, "テストのコピー")
        let copyScenes = try store.scenes(scenarioId: copyId)
        XCTAssertEqual(try store.lines(sceneId: copyScenes[0].id).count, 3)
        XCTAssertEqual(try store.synopsis(scenarioId: copyId), "あらすじ")
        try store.deleteScenario(id: id)
        XCTAssertEqual(try store.scenarios().count, 1)
        // 取り込み
        let other = try tempStore()
        let r = try other.importAll(from: store.url, stylesToo: false)
        XCTAssertEqual(r.scenarios, 1)
        XCTAssertEqual(r.lines, 3)
    }

    func testTextFormat() {
        XCTAssertEqual(TextFormat.toFullWidth("ﾃｷｽﾄabc12 ｷﾞ!"), "テキストａｂｃ１２ ギ!")
        XCTAssertEqual(TextFormat.toFullWidth("a!", asciiSymbols: true), "ａ！")
        XCTAssertEqual(TextFormat.kagikakko("やあ。"), "「やあ」")
        XCTAssertEqual(TextFormat.wrap("あいうえおかきくけこ", width: 4), ["あいうえ", "おかきく", "けこ"])
        // 行頭禁則「。」はぶら下げ
        XCTAssertEqual(TextFormat.wrap("あいう。えおかき", width: 3), ["あいう。", "えおか", "き"])
        // 行末禁則「「」は前で折る
        XCTAssertEqual(TextFormat.wrap("あい「うえお", width: 3), ["あい", "「うえ", "お"])
        XCTAssertEqual(TextFormat.wrap("一行\n二行", width: 10), ["一行", "二行"])
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 22
        XCTAssertEqual(TextFormat.wareki(Calendar(identifier: .gregorian).date(from: c)!), "令和8年9月22日")
        c.year = 2019; c.month = 5; c.day = 1
        XCTAssertEqual(TextFormat.wareki(Calendar(identifier: .gregorian).date(from: c)!), "令和元年5月1日")
    }

    func testExporters() throws {
        let store = try tempStore()
        // 台詞を「」で囲むのは既定でオフ。このテストでは囲む書き出しを確かめるのでオンにする
        XCTAssertFalse(try store.setting().useKagikakko)
        try store.saveSetting(OptionSetting(useKagikakko: true))
        let id = try store.createScenario(Scenario(title: "台本<&>", subtitle: "副題", writerName: "作者"), acts: 1, scenesPerAct: 1, characterCount: 1)
        let sc = try store.scenes(scenarioId: id)[0]
        let ch = try store.characters(scenarioId: id)[0]
        try store.updateCharacter(CastMember(id: ch.id, scenarioId: id, orderNo: 100, name: "太郎", chara: "主人公"))
        _ = try store.insertLine(ScriptLine(scenarioId: id, sceneId: sc.id, type: 1, characterId: ch.id, text: "おはよう。"), after: nil)
        _ = try store.insertLine(ScriptLine(scenarioId: id, sceneId: sc.id, type: 2, text: "太郎、立ち上がる。\n窓を開ける。"), after: nil)
        _ = try store.insertLine(ScriptLine(scenarioId: id, sceneId: sc.id, type: 8, text: "雨の音"), after: nil)
        let doc = try store.document(scenarioId: id)!
        let txt = TextExporter.makeText(doc)
        XCTAssertTrue(txt.contains("太郎　　　　　　「おはよう」"), txt)
        XCTAssertTrue(txt.contains("　　　　　　ＳＥ　　　　雨の音"), txt)
        let sjis = TextExporter.makeData(doc, encoding: .shiftJIS, lineEnding: .crlf)
        XCTAssertTrue(sjis.count > 0)
        for t in DocxExporter.Template.allCases {
            let data = try DocxExporter.make(doc, template: t, cover: .init(writerName: "作者", version: "第1稿"), userName: "テスト")
            XCTAssertGreaterThan(data.count, 10_000)
            XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
        }
        let xml = try XmlExporter.make(doc, cover: .init())
        XCTAssertTrue(xml.contains("台本&lt;&amp;&gt;"))
        XCTAssertTrue(xml.contains("<w:br/>"))
        let html = HtmlExporter.make(doc)
        XCTAssertTrue(html.contains("「おはよう」"))
        XCTAssertTrue(html.contains("margin-inline-start:3em;inline-size:29em"))
    }

    func testImportReadsWal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-wal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("swdata.sqlite").path
        // Web 版と同じく WAL モード。別の接続を開いたままにして、更新が -wal に残った状態を作る
        let web = try ScenarioStore(url: URL(fileURLWithPath: path))
        try web.db.exec("PRAGMA journal_mode=WAL")
        let holder = try SQLiteDatabase(path: path)
        _ = try holder.query("SELECT COUNT(*) FROM SW_SCENARIO")
        let id = try web.createScenario(Scenario(title: "WAL"), acts: 1, scenesPerAct: 1, characterCount: 1)
        let sc = try web.scenes(scenarioId: id)[0]
        let lid = try web.insertLine(ScriptLine(scenarioId: id, sceneId: sc.id, type: 1, text: ""), after: nil)
        var l = try web.line(id: lid)!; l.text = "あとから書いた台詞"; try web.updateLine(l)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"))
        // -wal を無視して開くと空のまま（従来の不具合の再現）
        let imm = try SQLiteDatabase(path: path, readOnly: true, immutable: true)
        let stale = try imm.query("SELECT SCENARIO_LINES FROM SW_SCENARIO_LINES").first?.text("SCENARIO_LINES") ?? "(none)"
        XCTAssertNotEqual(stale, "あとから書いた台詞")
        // 取り込みは WAL ごと複製するので最新
        let solo = try tempStore()
        let r = try solo.importAll(from: URL(fileURLWithPath: path), stylesToo: false)
        XCTAssertEqual(r.lines, 1)
        let imported = try solo.scenarios().first!
        let lines = try solo.lines(sceneId: try solo.scenes(scenarioId: imported.id)[0].id)
        XCTAssertEqual(lines.first?.text, "あとから書いた台詞")
        // フォルダ指定でも同じ
        let solo2 = try tempStore()
        XCTAssertEqual(try solo2.importAll(from: dir, stylesToo: false).scenarios, 1)
        _ = holder
    }

    func testWorkFiles() throws {
        let lib = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        let u1 = ScenarioStore.uniqueWorkURL(in: lib, title: "春/夏: 物語")
        XCTAssertEqual(u1.lastPathComponent, "春_夏_ 物語.scwd")
        let w1 = try ScenarioStore(url: u1)
        let id = try w1.createScenario(Scenario(title: "春/夏: 物語"), acts: 1, scenesPerAct: 1, characterCount: 1)
        try w1.setThumbnail(scenarioId: id, png: Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(ScenarioStore.uniqueWorkURL(in: lib, title: "春/夏: 物語").lastPathComponent, "春_夏_ 物語 2.scwd")
        let works = ScenarioStore.works(in: lib)
        XCTAssertEqual(works.count, 1)
        XCTAssertEqual(works[0].scenario.title, "春/夏: 物語")
        XCTAssertEqual(works[0].thumbnail?.count, 4)
        // 別ファイルへ複製（画像も付いてくる）
        let u2 = ScenarioStore.uniqueWorkURL(in: lib, title: "コピー先")
        let w2 = try ScenarioStore(url: u2)
        let nid = try w2.importScenario(from: w1.db, scenarioId: id, titleSuffix: "のコピー")
        XCTAssertEqual(try w2.scenario(id: nid)?.title, "春/夏: 物語のコピー")
        XCTAssertEqual(try w2.thumbnail(scenarioId: nid)?.count, 4)
        XCTAssertEqual(ScenarioStore.works(in: lib).count, 2)
        // スタイルの置き換え
        var st = try w2.styles(); st[0].name = "台詞!"
        try w2.replaceStyles(st, setting: OptionSetting(characterLength: 10, bodyLength: 40, useKagikakko: false))
        XCTAssertEqual(try w2.styles()[0].name, "台詞!")
        XCTAssertEqual(try w2.setting().bodyLength, 40)
    }
}
