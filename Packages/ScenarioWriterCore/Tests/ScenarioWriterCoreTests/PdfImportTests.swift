import XCTest
@testable import ScenarioWriterCore

final class PdfImportTests: XCTestCase {
    typealias G = PdfScriptImporter.Glyph
    let pitch = 14.0, body = 665.0, nameTop = 779.0, colStep = 25.0

    /// 1 列を作る。top から下へ字送りで並べる
    func col(_ x: Double, top: Double, _ text: String) -> [G] {
        text.enumerated().map { G(x: x, y: top - Double($0.offset) * pitch, char: String($0.element)) }
    }
    /// 人物名＋セリフの列
    func speech(_ x: Double, _ name: String, _ text: String) -> [G] { col(x, top: nameTop, name) + col(x, top: body, text) }
    let full = String(repeating: "あ", count: 31) + "い"   // 下まで埋まった 1 列（32 字）

    func testVerticalScript() throws {
        var x = 1100.0
        func next() -> Double { x -= colStep; return x + colStep }
        var p: [G] = []
        p += col(next(), top: nameTop, "第") + col(x + colStep, top: nameTop - 34, "一") + col(x + colStep, top: nameTop - 68, "場")
        p += col(next(), top: body - pitch * 2, "幕が開く。")
        p += speech(next(), "太郎", full)               // 折り返して
        p += col(next(), top: body, "続き。")               // 続く
        p += col(next(), top: body + 0, "改行のあと。")      // 前が「。」で短い → 改行
        p += col(next(), top: body - pitch, "段落の頭。")     // 1 字下げ → 段落
        p += speech(next(), "花子", "はい。")
        p += col(next(), top: body - pitch * 2, String(repeating: "う", count: 28))  // ト書の折り返し
        p += col(next(), top: body - pitch * 2, "える。")
        p += col(next(), top: body - pitch * 2 - 2, "♪歌のはじめ")
        p += col(next(), top: body - pitch * 4, "歌のつづき")
        p += col(next(), top: body - pitch * 2, "ト書にもどる。")
        p += speech(next(), "太郎", "おわり。")
        // 下の帯の横書き（きっかけ）は捨てる
        p += "音響きっかけ".enumerated().map { G(x: 600 + Double($0.offset) * 10, y: 150, char: String($0.element)) }
        // 本文の頭の高さを決めるのに十分な列数があるよう、2 ページ目にセリフを足す
        var p2: [G] = []
        for i in 0..<6 { p2 += speech(1100 - Double(i) * colStep, "花子", full) }
        p2 += col(1100 - 6 * colStep, top: body, "最後。")

        let r = try PdfScriptImporter.parse(pages: [p, p2])
        XCTAssertEqual(r.scenes.map(\.name), ["第一場"])
        XCTAssertEqual(r.characters, ["太郎", "花子"])
        let l = r.scenes[0].lines
        XCTAssertEqual(l[0], .init(kind: .direction, text: "幕が開く。"))
        XCTAssertEqual(l[1], .init(kind: .dialogue, character: "太郎", text: full + "続き。\n改行のあと。\n　段落の頭。"))
        XCTAssertEqual(l[2], .init(kind: .dialogue, character: "花子", text: "はい。"))
        XCTAssertEqual(l[3], .init(kind: .direction, text: String(repeating: "う", count: 28) + "える。"))
        XCTAssertEqual(l[4], .init(kind: .lyric, text: "♪歌のはじめ\n歌のつづき"))
        XCTAssertEqual(l[5], .init(kind: .direction, text: "ト書にもどる。"))
        XCTAssertEqual(l[6], .init(kind: .dialogue, character: "太郎", text: "おわり。"))
        XCTAssertFalse(l.contains { $0.text.contains("きっかけ") })
        // ページをまたいだ最後のセリフの続き
        XCTAssertEqual(l.last, .init(kind: .dialogue, character: "花子", text: full + "最後。"))
    }

    func testNoTextThrows() {
        XCTAssertThrowsError(try PdfScriptImporter.parse(pages: [[]]))
    }

    func testNormalizeVerticalForms() {
        XCTAssertEqual(PdfScriptImporter.normalize("﹁あ︑い︒﹂"), "「あ、い。」")
    }

    func testStoreFromImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swsolo-test-\(UUID().uuidString)")
        let store = try ScenarioStore(url: dir.appendingPathComponent("swdata.sqlite"))
        let r = PdfScriptImporter.Result(scenes: [.init(name: "第一場", lines: [
            .init(kind: .direction, text: "幕"), .init(kind: .dialogue, character: "太郎", text: "やあ\n二行目"), .init(kind: .lyric, text: "♪")])],
            characters: ["太郎"])
        let id = try store.createScenario(Scenario(title: "取込"), imported: r)
        let chars = try store.characters(scenarioId: id)
        XCTAssertEqual(chars.map(\.name), ["太郎"])
        let lines = try store.allLines(scenarioId: id)
        XCTAssertEqual(lines.map(\.type), [2, 1, 3])
        XCTAssertEqual(lines[1].characterId, chars[0].id)
        XCTAssertEqual(lines[1].text, "やあ\n二行目")
    }

    /// 手元の台本 PDF で通しで試す（SW_PDF_SAMPLE にパスを入れたときだけ）
    func testSamplePdf() throws {
        guard let path = ProcessInfo.processInfo.environment["SW_PDF_SAMPLE"] else { throw XCTSkip("SW_PDF_SAMPLE なし") }
        let r = try PdfScriptImporter.parse(url: URL(fileURLWithPath: path))
        print("場面 \(r.scenes.count) 人物 \(r.characters.count) 行 \(r.lineCount)")
        print(r.scenes.map(\.name), r.characters)
        if let out = ProcessInfo.processInfo.environment["SW_PDF_DUMP"] {
            var t = ""
            for sc in r.scenes { t += "■ \(sc.name)\n"; for l in sc.lines { t += "\(l.kind)\t\(l.character ?? "-")\t\(l.text.replacingOccurrences(of: "\n", with: "⏎"))\n" } }
            try t.write(toFile: out, atomically: true, encoding: .utf8)
        }
        XCTAssertFalse(r.scenes.flatMap(\.lines).contains { $0.kind == .dialogue && $0.character == nil })
    }
}
