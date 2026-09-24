import XCTest
import CoreGraphics
import CoreText
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
        for t in PdfExporter.Template.allCases {
            let data = try PdfExporter.make(doc, template: t, cover: .init(writerName: "作者", version: "第1稿", address: "住所"))
            XCTAssertEqual(data.prefix(5), Data("%PDF-".utf8))
            // 版下用に文字はアウトライン化する（フォントを埋め込まない）
            let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
            XCTAssertGreaterThanOrEqual(pdf.numberOfPages, 3, t.label)
            for i in 1...pdf.numberOfPages {
                let res = pdf.page(at: i)!.dictionary!
                var resources: CGPDFDictionaryRef?
                var fonts: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(res, "Resources", &resources), let resources {
                    XCTAssertFalse(CGPDFDictionaryGetDictionary(resources, "Font", &fonts), "\(t.label) p.\(i) にフォントがある")
                }
            }
        }
        // トンボ付き: 仕上がり（TrimBox）は A4、用紙はその外に余白を足した大きさ
        let tombo = try PdfExporter.make(doc, template: .a4PortraitVertical, cover: .init(), options: .init(trimMarks: true))
        let tp = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: tombo as CFData)!)?.page(at: 1))
        XCTAssertEqual(tp.getBoxRect(.trimBox).width, 595.28, accuracy: 0.1)
        XCTAssertEqual(tp.getBoxRect(.bleedBox).width, 595.28 + PdfExporter.mm(6), accuracy: 0.1)
        XCTAssertGreaterThan(tp.getBoxRect(.mediaBox).width, tp.getBoxRect(.bleedBox).width)
        let xml = try XmlExporter.make(doc, cover: .init())
        XCTAssertTrue(xml.contains("台本&lt;&amp;&gt;"))
        XCTAssertTrue(xml.contains("<w:br/>"))
        let html = HtmlExporter.make(doc)
        XCTAssertTrue(html.contains("「おはよう」"))
        XCTAssertTrue(html.contains("margin-inline-start:3em;inline-size:29em"))
    }

    /// PDF の 1 行は「人物名欄 characterLength 字 ＋ 本文 bodyLength 字」で折り返す（字下げは本文に含める）
    func testPdfLineLengthFollowsSetting() throws {
        let sc = Scenario(id: 1, title: "字数")
        let line1 = ScriptLine(id: 1, scenarioId: 1, sceneId: 1, type: 1, characterId: 1, text: String(repeating: "あ", count: 50))
        let line2 = ScriptLine(id: 2, scenarioId: 1, sceneId: 1, type: 2, text: String(repeating: "い", count: 50))
        for t in PdfExporter.Template.allCases {
            let doc = ScenarioDocument(scenario: sc, synopsis: "", characters: [CastMember(id: 1, scenarioId: 1, orderNo: 100, name: "太郎", chara: "")],
                                       scenes: [ScriptScene(id: 1, scenarioId: 1, orderNo: 100, name: "一")], linesByScene: [1: [line1, line2]],
                                       styles: [], setting: OptionSetting(characterLength: 6, bodyLength: 20, useKagikakko: false))
            let page = PdfExporter.Page.of(t)
            let body = try XCTUnwrap(PdfExporter.buildSections(doc, page: page, cover: .init()).last)
            let fs = CTFramesetterCreateWithAttributedString(body.text as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: page.body, transform: nil),
                [kCTFrameProgressionAttributeName: (page.vertical ? CTFrameProgression.rightToLeft : .topToBottom).rawValue] as CFDictionary)
            let str = body.text.string as NSString
            let lines = (CTFrameGetLines(frame) as! [CTLine]).map { l -> String in
                let r = CTLineGetStringRange(l)
                return str.substring(with: NSRange(location: r.location, length: r.length)).trimmingCharacters(in: .newlines)
            }
            // 台詞: 人物名欄 6 字（太郎＋空白 4）＋本文 20 字 → あ 20 / 20 / 10
            let a = lines.filter { $0.contains("あ") }
            XCTAssertEqual(a.map { $0.filter { $0 == "あ" }.count }, [20, 20, 10], t.label)
            XCTAssertTrue(a[0].hasPrefix("太郎　　　　あ"), t.label)
            // ト書（字下げ 3）: 6 ＋ 3 字下げ ＋ 17 字
            XCTAssertEqual(lines.filter { $0.contains("い") }.map { $0.filter { $0 == "い" }.count }, [17, 17, 16], t.label)
            // 2 行目以降は人物名欄（＋字下げ）の下から始まる（縦書きは下へ、横書きは右へずれる）
            let origins = PdfExporter.lineOrigins(frame, in: page.body, text: body.text, vertical: page.vertical)
            let idx = lines.indices.filter { lines[$0].contains("あ") }
            let jdx = lines.indices.filter { lines[$0].contains("い") }
            let em = body.text.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: (str.range(of: "あ")).location, effectiveRange: nil)
                .map { CTFontGetSize($0 as! CTFont) } ?? 0
            let shift = { (i: Int) -> CGFloat in page.vertical ? origins[idx[0]].y - origins[i].y : origins[i].x - origins[idx[0]].x }
            XCTAssertEqual(shift(idx[1]), 6 * em, accuracy: 0.01, t.label)
            XCTAssertEqual(shift(jdx[1]), 9 * em, accuracy: 0.01, t.label)
        }
    }

    /// 書き込み欄: 上なら本文ページの行が欄の長さだけ下（横書きは右）から始まり、上 / 下とも 1 行が残りに収まる
    func testPdfMemoArea() throws {
        let sc = Scenario(id: 1, title: "欄")
        let line = ScriptLine(id: 1, scenarioId: 1, sceneId: 1, type: 1, characterId: 1, text: String(repeating: "あ", count: 80))
        let doc = ScenarioDocument(scenario: sc, synopsis: "", characters: [CastMember(id: 1, scenarioId: 1, orderNo: 100, name: "太郎", chara: "")],
                                   scenes: [ScriptScene(id: 1, scenarioId: 1, orderNo: 100, name: "一")], linesByScene: [1: [line]],
                                   styles: [], setting: OptionSetting(characterLength: 8, bodyLength: 32, useKagikakko: false))
        for t in PdfExporter.Template.allCases {
            let page = PdfExporter.Page.of(t)
            var starts: [PdfExporter.MemoArea: CGFloat] = [:]
            for memo in PdfExporter.MemoArea.allCases {
                let body = try XCTUnwrap(PdfExporter.buildSections(doc, page: page, cover: .init(), memo: memo).last)
                XCTAssertEqual(body.memoRule == nil, memo == .none)
                let fs = CTFramesetterCreateWithAttributedString(body.text as CFAttributedString)
                let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: page.body, transform: nil),
                    [kCTFrameProgressionAttributeName: (page.vertical ? CTFrameProgression.rightToLeft : .topToBottom).rawValue] as CFDictionary)
                let lines = CTFrameGetLines(frame) as! [CTLine]
                let str = body.text.string as NSString
                let i = try XCTUnwrap(lines.firstIndex { str.substring(with: NSRange(location: CTLineGetStringRange($0).location, length: CTLineGetStringRange($0).length)).contains("あ") })
                let o = PdfExporter.lineOrigins(frame, in: page.body, text: body.text, vertical: page.vertical)[i]
                starts[memo] = page.vertical ? page.body.maxY - o.y : o.x - page.body.minX
                // 台詞の 1 行目は 人物名欄 8 字 ＋ 本文 32 字（残りに収まり、途中で折れない）
                let r = CTLineGetStringRange(lines[i])
                XCTAssertEqual(str.substring(with: NSRange(location: r.location, length: r.length)).filter { $0 == "あ" }.count, 32, "\(t.label) \(memo)")
            }
            XCTAssertEqual(starts[.top]! - starts[.none]!, PdfExporter.memoLength(page, .top), accuracy: 0.01, t.label)
            XCTAssertEqual(starts[.bottom]!, starts[.none]!, accuracy: 0.01, t.label)
            // 下: 罫は 1 行の終わり（8 ＋ 32 字）のすぐ後ろ。台詞とのあいだに空きを作らない
            let bottom = try XCTUnwrap(PdfExporter.buildSections(doc, page: page, cover: .init(), memo: .bottom).last?.memoRule)
            let em = bottom / 40.5
            XCTAssertLessThan(bottom - (starts[.none]! + 40 * em), em, t.label)
        }
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
