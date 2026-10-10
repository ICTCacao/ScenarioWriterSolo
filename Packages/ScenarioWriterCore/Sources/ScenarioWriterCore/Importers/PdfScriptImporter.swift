import Foundation
import PDFKit

/// 縦書きの台本 PDF（Word・InDesign などから書き出した、文字の情報が残っているもの）から、場面・登場人物・行を取り出す。
///
/// PDF の文字の並び順は縦書きではあてにならないので、1 文字ずつの位置から組み立て直す。
/// 1. 縦に隣の文字がある字だけを本文とし、横書き（上下の帯のきっかけ・ページ番号など）は捨てる
/// 2. x で列にまとめ、列を右から左、列の中を上から下に読む。大きく空いたところで列を断片に分ける
/// 3. 断片の書き出しの高さで見分ける … 上端の人物名欄 = 人物名（「第◯場」は場面）、いちばん多い高さ = セリフ、
///    1 字下げ = セリフの段落の頭、さらに下げたもの = ト書（「♪」で始まるものとその続きは歌詞）
/// 4. 下まで埋まった列の次の列は折り返しとしてつなぐ。名前のないセリフ位置の列は前のセリフの続き（改行・ページまたぎ）
///
/// スキャンした PDF や、文字をアウトライン化した PDF（Solo の PDF 書き出しもこれ）は文字の情報がないので読めない。
public enum PdfScriptImporter {

    /// 1 文字。座標は PDF のページ座標（y は上ほど大きい）
    public struct Glyph: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var char: String
        public init(x: Double, y: Double, char: String) { self.x = x; self.y = y; self.char = char }
    }

    public enum Kind: Sendable, Equatable { case dialogue, direction, lyric }

    public struct Line: Sendable, Equatable {
        public var kind: Kind
        public var character: String?
        public var text: String
        public init(kind: Kind, character: String? = nil, text: String) { self.kind = kind; self.character = character; self.text = text }

        /// 行の種別（SW_USER_OPTION の STYLE_ID）。既定のスタイルの 1=セリフ 2=ト書 3=歌詞
        public var styleId: Int {
            switch kind { case .dialogue: return 1; case .direction: return 2; case .lyric: return 3 }
        }
    }

    public struct Scene: Sendable, Equatable {
        public var name: String
        public var lines: [Line]
        public init(name: String, lines: [Line] = []) { self.name = name; self.lines = lines }
    }

    public struct Result: Sendable, Equatable {
        public var scenes: [Scene]
        /// 出てきた順
        public var characters: [String]
        public var lineCount: Int { scenes.reduce(0) { $0 + $1.lines.count } }
    }

    public enum ImportError: LocalizedError {
        case unreadable
        case noText
        case notVertical
        public var errorDescription: String? {
            switch self {
            case .unreadable: return "PDF を開けませんでした。"
            case .noText: return "この PDF には文字の情報がありません（スキャンした PDF や、文字をアウトライン化した PDF は読めません）。"
            case .notVertical: return "縦書きの台本として読み取れませんでした（いまは縦書きの台本だけに対応しています）。"
            }
        }
    }

    // MARK: - PDF から

    public static func parse(url: URL) throws -> Result {
        guard let doc = PDFDocument(url: url) else { throw ImportError.unreadable }
        var pages: [[Glyph]] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            pages.append(glyphs(of: page))
        }
        guard pages.contains(where: { !$0.isEmpty }) else { throw ImportError.noText }
        return try parse(pages: pages)
    }

    /// PDF に書かれた題名（なければ nil）
    public static func title(of url: URL) -> String? {
        guard let t = PDFDocument(url: url)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String else { return nil }
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// 1 文字ずつの位置。`characterBounds(at:)` は文字とずれる PDF があるので、1 文字の選択範囲から取る。
    /// 同じ文字が 2 回返ることがあるので、同じ位置・同じ字は 1 つにする。
    static func glyphs(of page: PDFPage) -> [Glyph] {
        var seen = Set<String>()
        var out: [Glyph] = []
        for i in 0..<page.numberOfCharacters {
            guard let sel = page.selection(for: NSRange(location: i, length: 1)), let s = sel.string else { continue }
            let c = normalize(s)
            if c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let r = sel.bounds(for: page)
            if seen.insert("\(Int(r.midX * 2)),\(Int(r.midY * 2)),\(c)").inserted {
                out.append(Glyph(x: Double(r.midX), y: Double(r.midY), char: c))
            }
        }
        return out
    }

    /// 縦書き用の字形（︑︒﹁﹂ など）をふつうの字に
    static func normalize(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.flatMap { u -> [Unicode.Scalar] in
            if (0xFE10...0xFE19).contains(u.value) || (0xFE30...0xFE4F).contains(u.value) {
                return Array(String(u).precomposedStringWithCompatibilityMapping.unicodeScalars)
            }
            return [u]
        }))
    }

    // MARK: - 組み立て

    /// 列の断片
    struct Segment {
        var x: Double
        var top: Double
        var bottom: Double
        var text: String
        /// 2 字目の高さ（行頭の約物をぶら下げた行の、本当の書き出しを見るため）
        var second: Double?
    }

    /// ページごとの文字から組み立てる（ページは読む順。見開きは 1 枚で右のページが先）
    public static func parse(pages: [[Glyph]]) throws -> Result {
        let columns = pages.map { verticalColumns(of: $0) }
        guard columns.contains(where: { $0.contains { $0.count >= 3 } }) else { throw ImportError.notVertical }

        // 字送り: 列の中の字の間隔の、小さいほうから 1/4 あたり（句読点の詰めや断片の間を避ける）
        var gaps: [Double] = []
        for page in columns { for col in page { for k in col.indices.dropFirst() { let g = col[k - 1].y - col[k].y; if g > 3 { gaps.append(g) } } } }
        gaps.sort()
        let pitch = gaps.isEmpty ? 14 : gaps[gaps.count / 4]

        // 本文の頭: 断片の書き出しの高さでいちばん多いもの。人物名欄はそれより 1.5 字以上上
        let rough = columns.map { $0.flatMap { segments(of: $0, pitch: pitch, nameBand: .infinity) } }
        var tops: [Int: Int] = [:]
        for page in rough { for s in page where s.text.count >= 3 { tops[Int(s.top.rounded()), default: 0] += 1 } }
        guard let bodyTop = tops.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }).map({ Double($0.key) }) else { throw ImportError.notVertical }
        let nameBand = bodyTop + pitch * 1.5
        let segs = columns.map { $0.flatMap { segments(of: $0, pitch: pitch, nameBand: nameBand) } }

        // 本文の下端: セリフ位置から始まる長い列の下端で、3 回以上出てくるいちばん下
        var bottoms: [Int: Int] = [:]
        for page in segs { for s in page where abs(s.top - bodyTop) < pitch / 2 && s.text.count >= 10 { bottoms[Int(s.bottom.rounded()), default: 0] += 1 } }
        let bodyBottom = bottoms.keys.sorted().first { bottoms[$0]! >= 3 }.map(Double.init)
            ?? segs.flatMap { $0 }.map(\.bottom).min() ?? 0

        func slot(_ top: Double) -> Int { Int(((bodyTop - top) / pitch).rounded()) }
        let inBody = { (s: Segment) in s.top <= nameBand && s.top > bodyBottom }
        // 書き出し位置ごとの 1 列の最大字数（9 割のところ）
        var lens: [Int: [Int]] = [:]
        for page in segs { for s in page where inBody(s) { lens[slot(s.top), default: []].append(s.text.count) } }
        let maxLen = lens.mapValues { a -> Int in let b = a.sorted(); return b[min(b.count - 1, b.count * 9 / 10)] }
        // ト書の位置: セリフより下げた書き出しでいちばん多いもの（1 字下げはセリフの段落）
        var slotCount: [Int: Int] = [:]
        for page in segs { for s in page where inBody(s) && slot(s.top) > 1 { slotCount[slot(s.top), default: 0] += 1 } }
        let directionSlot = slotCount.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 2

        let openers: Set<Character> = ["「", "『", "（", "(", "“", "〝"]
        let enders: Set<Character> = ["。", "」", "）", "』", "！", "？", "!", "?", ")"]
        let sceneHeading = #"^(第.+[場幕景]|[○◯〇●].*|[Ss]\s*#?\s*\d+.*)$"#

        var scenes: [Scene] = []
        var characters: [String] = []
        // 組み立て中の行（open = 下まで埋まって次の列に続きそう）
        var current: [(line: Line, open: Bool, slot: Int)] = []

        func flushScene() {
            if current.isEmpty { return }
            if scenes.isEmpty { scenes.append(Scene(name: "（冒頭）")) }
            scenes[scenes.count - 1].lines += current.map(\.line)
            current = []
        }
        func add(_ kind: Kind, _ name: String?, _ text: String, open: Bool, slot: Int) {
            if let name, !characters.contains(name) { characters.append(name) }
            current.append((Line(kind: kind, character: name, text: text), open, slot))
        }
        func appendToLast(_ text: String, separator: String, open: Bool) {
            current[current.count - 1].line.text += separator + text
            current[current.count - 1].open = open
        }

        for page in segs {
            let main = page.filter { $0.top > bodyBottom - pitch }.sorted { $0.x > $1.x }
            // 表紙など、セリフ位置にも人物名欄にも何もないページは飛ばす
            if !main.contains(where: { abs($0.top - bodyTop) < pitch / 2 || $0.top > nameBand }) { continue }
            var pendingName: String?
            for s in main {
                let last = current.last
                var sl = slot(s.top)
                // セリフの続きでないところで「 などをぶら下げた行は、2 字目を書き出しとみなす（ト書の中の引用など）
                if let c = s.text.first, openers.contains(c), last?.line.kind != .dialogue, let second = s.second { sl = slot(second) }
                let ml = maxLen[sl] ?? 30
                let open = s.text.count >= ml - 2 || (s.text.count >= ml * 3 / 4 && !enders.contains(s.text.last!))
                if s.top > nameBand {
                    // 人物名欄
                    if s.text.range(of: sceneHeading, options: .regularExpression) != nil {
                        flushScene()
                        scenes.append(Scene(name: s.text))
                    } else if s.text.count <= 8 && !s.text.hasPrefix("♪") {
                        pendingName = s.text
                    } else if last?.line.kind == .lyric && !s.text.hasPrefix("♪") {
                        appendToLast(s.text, separator: "\n", open: false)
                    } else {
                        add(s.text.hasPrefix("♪") ? .lyric : .direction, nil, s.text, open: false, slot: sl)
                    }
                } else if let name = pendingName {
                    pendingName = nil
                    if s.text.hasPrefix("♪") {
                        // 「音楽　早春譜」のように名前欄に見出しがあって、下が歌詞
                        add(.direction, nil, name, open: false, slot: sl)
                        add(.lyric, nil, s.text, open: open, slot: sl)
                    } else {
                        add(.dialogue, name, s.text, open: open, slot: sl)
                    }
                } else if let last, last.line.kind == .lyric, !s.text.hasPrefix("♪"),
                          sl != directionSlot || (s.text.count <= 20 && !s.text.contains(where: { "、。".contains($0) })) {
                    // 歌詞の続き（段をずらした歌詞も）。ト書の位置の行は、短くて句読点のないものだけ
                    appendToLast(s.text, separator: last.open && last.slot == sl ? "" : "\n", open: open)
                    current[current.count - 1].slot = sl
                } else if sl <= 1, let last, last.line.kind == .dialogue {
                    // 名前のないセリフ位置の列は前のセリフの続き。1 字下げは段落の頭
                    let sep = last.open && sl <= 0 ? "" : (sl == 1 ? "\n　" : "\n")
                    appendToLast(s.text, separator: sep, open: open)
                } else {
                    // 名前のない行はト書（セリフの高さから始まっていても）。「♪」で始まれば歌詞
                    let lyric = s.text.hasPrefix("♪")
                    if !lyric, let last, last.line.kind == .direction, last.open, last.slot == sl {
                        appendToLast(s.text, separator: "", open: open)
                    } else {
                        add(lyric ? .lyric : .direction, nil, s.text, open: open, slot: sl)
                    }
                }
            }
            if let name = pendingName { add(.direction, nil, name, open: false, slot: 0) }
        }
        flushScene()
        if scenes.isEmpty { throw ImportError.notVertical }
        return Result(scenes: scenes, characters: characters)
    }

    /// 縦書きの字だけを x で列にまとめる（列は右から、列の中は上から）。
    /// 縦に近い字があり、横の隣より近い字を縦書きとみなす。どちらにも隣がない字（1 字だけの行など）も縦書きに入れる。
    static func verticalColumns(of glyphs: [Glyph]) -> [[Glyph]] {
        // 近所だけを見るよう 20pt 四方の升に分ける
        let cell = 20.0
        var grid: [Int64: [Int]] = [:]
        func key(_ x: Double, _ y: Double) -> Int64 { Int64((x / cell).rounded(.down)) << 32 | Int64(Int32((y / cell).rounded(.down))) & 0xFFFF_FFFF }
        for (i, g) in glyphs.enumerated() { grid[key(g.x, g.y), default: []].append(i) }
        var vertical: [Glyph] = []
        for (i, a) in glyphs.enumerated() {
            var dv = Double.infinity, dh = Double.infinity
            for dx in -1...1 { for dy in -1...1 {
                for j in grid[key(a.x + Double(dx) * cell, a.y + Double(dy) * cell)] ?? [] where j != i {
                    let b = glyphs[j]
                    if abs(a.x - b.x) < 3 { dv = min(dv, abs(a.y - b.y)) }
                    if abs(a.y - b.y) < 3 { dh = min(dh, abs(a.x - b.x)) }
                }
            } }
            if dv <= dh || dh > 17 { vertical.append(a) }
        }
        var cols: [[Glyph]] = []
        for g in vertical.sorted(by: { $0.x > $1.x }) {
            if let l = cols.last, abs(l[0].x - g.x) < 4 { cols[cols.count - 1].append(g) } else { cols.append([g]) }
        }
        return cols.map { $0.sorted { $0.y > $1.y } }
    }

    /// 列を、大きく空いたところで断片に分ける。人物名欄（nameBand より上）の字は、間が空いていても 1 つにまとめる（「第　一　場」など）。
    /// 行頭の約物（「 など）は字の中心が下にずれるので、2 字目から 1 字戻した位置も書き出しの高さとして見る。
    static func segments(of col: [Glyph], pitch: Double, nameBand: Double) -> [Segment] {
        guard !col.isEmpty else { return [] }
        var out: [Segment] = []
        var cur: [Glyph] = [col[0]]
        func flush() {
            let top = cur.count > 1 && cur[0].y - cur[1].y < pitch * 1.5 ? max(cur[0].y, cur[1].y + pitch) : cur[0].y
            out.append(Segment(x: cur[0].x, top: top, bottom: cur.last!.y, text: cur.map(\.char).joined(), second: cur.count > 1 ? cur[1].y : nil))
        }
        for g in col.dropFirst() {
            let prev = cur.last!
            let bothInNameBand = prev.y > nameBand && g.y > nameBand
            if prev.y - g.y > pitch * 2.2 && !bothInNameBand { flush(); cur = [g] } else { cur.append(g) }
        }
        flush()
        return out
    }
}

extension ScenarioStore {
    /// PDF から取り出した台本を新しい作品として入れる。登場人物は出てきた順、行は場面ごとに並べる。
    @discardableResult
    public func createScenario(_ s: Scenario, imported r: PdfScriptImporter.Result) throws -> Int64 {
        try db.transaction {
            let id = try insertScenario(s)
            var charIds: [String: Int64] = [:]
            for (i, name) in r.characters.enumerated() {
                try db.run("INSERT INTO SW_CHARACTER (SCENARIO_ID, CHARACTER_ORDER_NO, CHARACTER_NAME, CHARACTER_CHARA) VALUES (?, ?, ?, '')",
                           [.int(id), .real(Double(i + 1) * 100), .text(name)])
                charIds[name] = db.lastInsertRowId
            }
            for (i, scene) in r.scenes.enumerated() {
                try db.run("INSERT INTO SW_SCENE (SCENARIO_ID, SCENE_ORDER_NO, SCENE_VALID_CD, SCENE_NAME, SCENE_DESCRIPTION, SCENE_TIME_MIN, SCENE_TIME_SEC) VALUES (?, ?, 0, ?, '', 0, 0)",
                           [.int(id), .real(Double(i + 1) * 100), .text(scene.name)])
                let sceneId = db.lastInsertRowId
                for (k, l) in scene.lines.enumerated() {
                    let charVal: SQLiteDatabase.SQLiteValue? = l.character.flatMap { charIds[$0] }.map { .int($0) }
                    try db.run("INSERT INTO SW_SCENARIO_LINES (SCENARIO_ID, SCENE_ID, SCENARIO_LINES_ORDER_NO, SCENARIO_TYPE, CHARACTER_ID, SCENARIO_LINES) VALUES (?, ?, ?, ?, ?, ?)",
                               [.int(id), .int(sceneId), .real(Double(k + 1) * 100), .i(l.styleId), charVal, .text(DBText.toDB(l.text))])
                }
            }
            try db.run("INSERT INTO SW_SYNOPSIS (SCENARIO_ID, SYNOPSIS, UPDATE_DATE) VALUES (?, '', ?)", [.int(id), .text(Self.now())])
            return id
        }
    }
}
