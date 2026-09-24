import Foundation
import CoreGraphics
import CoreText

/// PDF 台本。Word（.docx）と同じ用紙・書き方・表紙の情報で、Core Text で直接組む（Word を経由しない）。
/// 縦書きは行を右から左へ積み（kCTFrameProgressionRightToLeft）、字形を縦組み用にする（kCTVerticalFormsAttributeName）。
/// ページ送りは CTFramesetter が 1 ページに収めた範囲を順に進めて決める。
///
/// 印刷所に版下として渡せるよう、文字はすべてアウトライン化する（字形をパスにして塗る。フォントを埋め込まない）。
/// 色は墨 1 色（DeviceGray の 0 = K100%）。場面の見出し（柱）は Word テンプレートと同じく三方を罫で囲む。
/// 求めがあればトンボ（角・センター）と裁ち落としの枠（TrimBox / BleedBox）を付ける。
public enum PdfExporter {

    public typealias Template = DocxExporter.Template
    public typealias CoverInfo = DocxExporter.CoverInfo

    public struct Options: Sendable {
        /// トンボを付け、仕上がりの外に裁ち落としとトンボの余白を足す
        public var trimMarks: Bool
        /// 裁ち落とし（pt）。既定 3mm
        public var bleed: CGFloat
        public init(trimMarks: Bool = false, bleed: CGFloat = PdfExporter.mm(3)) {
            self.trimMarks = trimMarks; self.bleed = bleed
        }
    }

    public static func mm(_ v: CGFloat) -> CGFloat { v * 72 / 25.4 }

    /// 場面の見出しの段落に付ける印（囲み罫を引く行を探すのに使う）
    static let sceneKey = NSAttributedString.Key("swSceneHeading")

    /// 用紙・余白・文字の大きさ（pt）
    struct Page {
        var size: CGSize
        var margin: (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat)
        var vertical: Bool
        var fontSize: CGFloat
        /// 場面ごとに改ページする（A4縦 縦書きの Word テンプレートは「場面　柱」が改ページ前置き）
        var sceneBreak: Bool
        var body: CGRect {
            CGRect(x: margin.left, y: margin.bottom,
                   width: size.width - margin.left - margin.right, height: size.height - margin.top - margin.bottom)
        }
        var pitch: CGFloat { (fontSize * 1.8).rounded() }

        static func of(_ t: Template) -> Page {
            let a4 = CGSize(width: 595.28, height: 841.89)
            switch t {
            case .a4PortraitVertical:
                return Page(size: a4, margin: (72, 60, 72, 60), vertical: true, fontSize: 12, sceneBreak: true)
            case .a4PortraitHorizontal:
                return Page(size: a4, margin: (72, 64, 80, 80), vertical: false, fontSize: 11, sceneBreak: false)
            case .a4LandscapeVertical:
                return Page(size: CGSize(width: a4.height, height: a4.width), margin: (80, 72, 64, 72), vertical: true, fontSize: 11, sceneBreak: false)
            }
        }
    }

    /// 1 つの節（新しいページから始まる）
    struct Section {
        var text: NSAttributedString
        var numbered: Bool
    }

    // MARK: - 書体

    static let minchoNames = ["HiraMinProN-W3", "HiraMinPro-W3", "YuMincho-Regular"]
    static let minchoBoldNames = ["HiraMinProN-W6", "HiraMinPro-W6", "YuMincho-Demibold"]
    static let gothicNames = ["HiraKakuProN-W6", "HiraKakuPro-W6", "YuGothic-Bold"]

    static func font(_ names: [String], _ size: CGFloat) -> CTFont {
        for n in names {
            let f = CTFontCreateWithName(n as CFString, size, nil)
            if (CTFontCopyPostScriptName(f) as String) == n { return f }
        }
        return CTFontCreateUIFontForLanguage(.system, size, "ja" as CFString) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    // MARK: - 段落

    struct Para {
        var font: CTFont
        var sceneHeading = false
        var alignment: CTTextAlignment = .natural
        var firstIndent: CGFloat = 0
        var headIndent: CGFloat = 0
        var tailIndent: CGFloat = 0
        var lineHeight: CGFloat
        var spacingBefore: CGFloat = 0
        var spacingAfter: CGFloat = 0
    }

    final class Builder {
        let page: Page
        let out = NSMutableAttributedString()
        init(page: Page) { self.page = page }

        /// 段落を 1 つ足す。段落内の改行は行区切り（U+2028）にして、折り返しと同じ字下げを保つ
        func add(_ text: String, _ p: Para) {
            let body = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\u{2028}")
            var align = p.alignment
            var first = p.firstIndent, head = p.headIndent, tail = p.tailIndent
            var lh = p.lineHeight, before = p.spacingBefore, after = p.spacingAfter
            let settings: [CTParagraphStyleSetting] = [
                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &align),
                CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: &first),
                CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: &head),
                CTParagraphStyleSetting(spec: .tailIndent, valueSize: MemoryLayout<CGFloat>.size, value: &tail),
                CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &lh),
                CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &lh),
                CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: &before),
                CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: &after),
            ]
            let style = CTParagraphStyleCreate(settings, settings.count)
            var attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): p.font,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
            ]
            if page.vertical { attrs[NSAttributedString.Key(kCTVerticalFormsAttributeName as String)] = true }
            if p.sceneHeading { attrs[PdfExporter.sceneKey] = true }
            // 段落の区切りの改行は前の段落の書式にする（見出しの印が次の段落の先頭に漏れないように）
            if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: out.attributes(at: out.length - 1, effectiveRange: nil))) }
            out.append(NSAttributedString(string: body, attributes: attrs))
        }
    }

    // MARK: - 作る

    public static func make(_ doc: ScenarioDocument, template: Template, cover: CoverInfo, options: Options = .init()) throws -> Data {
        let page = Page.of(template)
        let sections = buildSections(doc, page: page, cover: cover)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw DocxExporter.ExportError(message: "PDF を作れません") }
        // トンボを付けるときは、仕上がり（page.size）の四方に裁ち落とし＋トンボの余白を足した用紙にして、中身をずらして描く
        let slug: CGFloat = options.trimMarks ? options.bleed + mm(12) : 0
        let trim = CGRect(x: slug, y: slug, width: page.size.width, height: page.size.height)
        var media = CGRect(x: 0, y: 0, width: trim.width + slug * 2, height: trim.height + slug * 2)
        func box(_ r: CGRect) -> CFData { var r = r; return Data(bytes: &r, count: MemoryLayout<CGRect>.size) as CFData }
        let pageInfo: [CFString: Any] = options.trimMarks
            ? [kCGPDFContextMediaBox: box(media), kCGPDFContextTrimBox: box(trim),
               kCGPDFContextBleedBox: box(trim.insetBy(dx: -options.bleed, dy: -options.bleed))]
            : [kCGPDFContextMediaBox: box(media)]
        let writer = cover.writerName.isEmpty ? doc.scenario.writerName : cover.writerName
        let info: [CFString: Any] = [
            kCGPDFContextTitle: doc.scenario.title,
            kCGPDFContextAuthor: writer,
            kCGPDFContextCreator: "ScenarioWriterSolo",
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &media, info as CFDictionary) else {
            throw DocxExporter.ExportError(message: "PDF を作れません")
        }
        let headerFont = font(minchoNames, 8)
        var pageNo = 0
        for sec in sections {
            let fs = CTFramesetterCreateWithAttributedString(sec.text as CFAttributedString)
            let path = CGPath(rect: page.body, transform: nil)
            let frameAttrs: [CFString: Any] = [
                kCTFrameProgressionAttributeName: (page.vertical ? CTFrameProgression.rightToLeft : .topToBottom).rawValue,
            ]
            var start = 0
            let total = sec.text.length
            repeat {
                ctx.beginPDFPage(pageInfo as CFDictionary)
                ctx.setFillColor(gray: 0, alpha: 1)
                ctx.setStrokeColor(gray: 0, alpha: 1)
                if options.trimMarks { drawTrimMarks(ctx, trim: trim, bleed: options.bleed) }
                ctx.saveGState()
                ctx.translateBy(x: trim.minX, y: trim.minY)
                let frame = CTFramesetterCreateFrame(fs, CFRange(location: start, length: 0), path, frameAttrs as CFDictionary)
                fillOutlines(frame, in: page.body, ctx)
                strokeSceneBoxes(frame, page: page, ctx)
                if sec.numbered {
                    pageNo += 1
                    drawPageFurniture(ctx, page: page, title: doc.scenario.title, pageNo: pageNo, font: headerFont)
                }
                ctx.restoreGState()
                ctx.endPDFPage()
                let visible = CTFrameGetVisibleStringRange(frame)
                // 1 文字も入らない（余白が狭すぎる等）ときは打ち切る
                if visible.length <= 0 { break }
                start += visible.length
            } while start < total
        }
        ctx.closePDF()
        return data as Data
    }

    /// 上の余白に題名、下の余白の中央にページ番号
    static func drawPageFurniture(_ ctx: CGContext, page: Page, title: String, pageNo: Int, font: CTFont) {
        func draw(_ s: String, centerX: CGFloat? = nil, rightX: CGFloat? = nil, y: CGFloat) {
            let a = NSAttributedString(string: s, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let line = CTLineCreateWithAttributedString(a)
            let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x = centerX.map { $0 - w / 2 } ?? (rightX.map { $0 - w } ?? 0)
            fillOutlines(line, at: CGPoint(x: x, y: y), ctx)
        }
        let b = page.body
        draw(title, rightX: b.maxX, y: b.maxY + page.margin.top / 2 - 3)
        draw("— \(pageNo) —", centerX: b.midX, y: page.margin.bottom / 2 - 3)
    }

    // MARK: - 場面の見出しの囲み（柱）

    /// Word テンプレートの「場面　柱」と同じく、見出しの行を三方の罫で囲む。
    /// 行頭側の端は字下げの位置、行末側は本文欄の端まで伸ばして開けておく
    /// （縦書き: 右・上・左を引き下を開ける。横書き: 上・左・下を引き右を開ける）。
    static func strokeSceneBoxes(_ frame: CTFrame, page: Page, _ ctx: CGContext) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let rect = page.body
        // 見出しの行の外接矩形（行の進む向きの幅は字の大きさ、行頭は行の原点）
        var boxes: [CGRect] = []
        var prevHeading = false
        for (i, line) in lines.enumerated() {
            guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
                  (CTRunGetAttributes(run) as NSDictionary)[sceneKey.rawValue] as? Bool == true else { prevHeading = false; continue }
            let fontRef = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String]
            let size = fontRef.map { CTFontGetSize($0 as! CTFont) } ?? page.fontSize
            let pad = size * 0.45
            let o = CGPoint(x: rect.minX + origins[i].x, y: rect.minY + origins[i].y)
            let r: CGRect
            if page.vertical {
                // 縦の行の原点は列の中心線の上端
                r = CGRect(x: o.x - size / 2 - pad, y: rect.minY, width: size + pad * 2, height: o.y + pad - rect.minY)
            } else {
                var ascent: CGFloat = 0, descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                r = CGRect(x: o.x - pad, y: o.y - descent - pad * 0.6, width: rect.maxX - (o.x - pad), height: ascent + descent + pad * 1.2)
            }
            // 見出しが折り返して 2 行以上になったら 1 つの囲みにまとめる
            if prevHeading, let last = boxes.popLast() { boxes.append(last.union(r)) } else { boxes.append(r) }
            prevHeading = true
        }
        guard !boxes.isEmpty else { return }
        ctx.setLineWidth(0.6)
        for b in boxes {
            let p = CGMutablePath()
            if page.vertical {
                p.move(to: CGPoint(x: b.maxX, y: b.minY)); p.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
                p.addLine(to: CGPoint(x: b.minX, y: b.maxY)); p.addLine(to: CGPoint(x: b.minX, y: b.minY))
            } else {
                p.move(to: CGPoint(x: b.maxX, y: b.maxY)); p.addLine(to: CGPoint(x: b.minX, y: b.maxY))
                p.addLine(to: CGPoint(x: b.minX, y: b.minY)); p.addLine(to: CGPoint(x: b.maxX, y: b.minY))
            }
            ctx.addPath(p)
            ctx.strokePath()
        }
    }

    // MARK: - トンボ

    /// 角トンボ（仕上がり線と裁ち落とし線の二重）とセンタートンボ。線は K100% の 0.25pt
    static func drawTrimMarks(_ ctx: CGContext, trim: CGRect, bleed: CGFloat) {
        let len = mm(10)           // 角トンボの線の長さ（裁ち落とし線から外へ）
        let p = CGMutablePath()
        for (cx, ox) in [(trim.minX, CGFloat(-1)), (trim.maxX, 1)] {
            for (cy, oy) in [(trim.minY, CGFloat(-1)), (trim.maxY, 1)] {
                // 横の線: 仕上がり線の延長（内トンボ）と裁ち落とし線の延長（外トンボ）
                p.move(to: CGPoint(x: cx + ox * bleed, y: cy)); p.addLine(to: CGPoint(x: cx + ox * (bleed + len), y: cy))
                p.move(to: CGPoint(x: cx, y: cy + oy * bleed)); p.addLine(to: CGPoint(x: cx + ox * (bleed + len), y: cy + oy * bleed))
                // 縦の線
                p.move(to: CGPoint(x: cx, y: cy + oy * bleed)); p.addLine(to: CGPoint(x: cx, y: cy + oy * (bleed + len)))
                p.move(to: CGPoint(x: cx + ox * bleed, y: cy)); p.addLine(to: CGPoint(x: cx + ox * bleed, y: cy + oy * (bleed + len)))
            }
        }
        // センタートンボ（十字）: 各辺の中央、裁ち落としの外
        let arm = mm(5), gap = bleed + mm(2)
        for (x, y, horizontalEdge, o) in [(trim.midX, trim.maxY, true, CGFloat(1)), (trim.midX, trim.minY, true, -1),
                                          (trim.minX, trim.midY, false, -1), (trim.maxX, trim.midY, false, 1)] {
            if horizontalEdge {
                let c = CGPoint(x: x, y: y + o * (gap + arm))
                p.move(to: CGPoint(x: x, y: y + o * gap)); p.addLine(to: CGPoint(x: x, y: y + o * (gap + arm * 2)))
                p.move(to: CGPoint(x: c.x - arm * 2, y: c.y)); p.addLine(to: CGPoint(x: c.x + arm * 2, y: c.y))
            } else {
                let c = CGPoint(x: x + o * (gap + arm), y: y)
                p.move(to: CGPoint(x: x + o * gap, y: y)); p.addLine(to: CGPoint(x: x + o * (gap + arm * 2), y: y))
                p.move(to: CGPoint(x: c.x, y: c.y - arm * 2)); p.addLine(to: CGPoint(x: c.x, y: c.y + arm * 2))
            }
        }
        ctx.setLineWidth(0.25)
        ctx.addPath(p)
        ctx.strokePath()
    }

    // MARK: - アウトライン化

    /// フレームの文字を輪郭のパスで塗る（CTFrameDraw の代わり）。
    /// 縦書きのフレームでも、ランの字形位置は行の原点からの縦組みの座標（縦組み用の送りと字形の中心合わせ込み）で返るので、
    /// 回転をかけずに原点 + 位置へ置けば CTFrameDraw と同じ所に来る（横倒しの欧文も縦組み用の字形 vrt2 で来る）。
    static func fillOutlines(_ frame: CTFrame, in rect: CGRect, _ ctx: CGContext) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (i, line) in lines.enumerated() {
            fillOutlines(line, at: CGPoint(x: rect.minX + origins[i].x, y: rect.minY + origins[i].y), ctx)
        }
    }

    static func fillOutlines(_ line: CTLine, at origin: CGPoint, _ ctx: CGContext) {
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let fontRef = attrs[kCTFontAttributeName as String] else { continue }
            let font = fontRef as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
            for k in 0..<n {
                var t = CGAffineTransform(translationX: origin.x + pos[k].x, y: origin.y + pos[k].y)
                if let g = CTFontCreatePathForGlyph(font, glyphs[k], &t) { path.addPath(g) }
            }
        }
        guard !path.isEmpty else { return }
        ctx.addPath(path)
        ctx.fillPath(using: .winding)
    }

    // MARK: - 中身

    static func buildSections(_ doc: ScenarioDocument, page: Page, cover: CoverInfo) -> [Section] {
        let fs = page.fontSize
        let pitch = page.pitch
        let mincho = font(minchoNames, fs)
        let gothic = font(gothicNames, fs)
        let title = doc.scenario.title
        let nameW = CGFloat(max(doc.setting.characterLength, 2))
        let gap: CGFloat = 1   // 人物名と本文のあいだ（文字数）
        var sections: [Section] = []

        // 表紙
        do {
            let b = Builder(page: page)
            let t = font(minchoBoldNames, 26), st = font(minchoNames, 18), cap = font(minchoNames, 13), small = font(minchoNames, 11)
            let writer = cover.writerName.isEmpty ? doc.scenario.writerName : cover.writerName
            let date = cover.date.map { TextFormat.wareki($0) } ?? ""
            let contacts = [cover.address, cover.phone, cover.email].filter { !$0.isEmpty }
            if page.vertical {
                // 右寄りに題名、左寄りに作者と連絡先（Word テンプレートの表紙と同じ並び）
                let top = page.body.height * 0.12
                b.add(TextFormat.toFullWidth(title), Para(font: t, firstIndent: top, headIndent: top, lineHeight: 48, spacingBefore: 30))
                if !doc.scenario.subtitle.isEmpty {
                    b.add(TextFormat.toFullWidth(doc.scenario.subtitle), Para(font: st, firstIndent: top + 54, headIndent: top + 54, lineHeight: 34))
                }
                let lower = page.body.height * 0.52
                b.add("", Para(font: cap, lineHeight: page.body.width * 0.3))
                for s in [date, cover.version] where !s.isEmpty {
                    b.add(TextFormat.toFullWidth(s), Para(font: cap, firstIndent: lower, headIndent: lower, lineHeight: 26))
                }
                b.add("作者名：" + writer, Para(font: cap, firstIndent: lower, headIndent: lower, lineHeight: 26))
                if !cover.writerId.isEmpty {
                    b.add(TextFormat.toFullWidth(cover.writerId), Para(font: cap, firstIndent: lower, headIndent: lower, lineHeight: 26))
                }
                for s in contacts {
                    b.add(TextFormat.toFullWidth(s), Para(font: small, firstIndent: lower, headIndent: lower, lineHeight: 20))
                }
            } else {
                b.add(title, Para(font: t, alignment: .center, lineHeight: 40, spacingBefore: page.body.height * 0.28))
                if !doc.scenario.subtitle.isEmpty {
                    b.add(doc.scenario.subtitle, Para(font: st, alignment: .center, lineHeight: 30, spacingBefore: 8))
                }
                if !date.isEmpty { b.add(date, Para(font: cap, alignment: .center, lineHeight: 22, spacingBefore: 40)) }
                if !cover.version.isEmpty { b.add(cover.version, Para(font: cap, alignment: .center, lineHeight: 22)) }
                b.add("作者名：" + writer, Para(font: cap, alignment: .center, lineHeight: 24, spacingBefore: 60))
                if !cover.writerId.isEmpty { b.add(cover.writerId, Para(font: cap, alignment: .center, lineHeight: 22)) }
                for (i, s) in contacts.enumerated() {
                    b.add(s, Para(font: small, alignment: .right, lineHeight: 18, spacingBefore: i == 0 ? page.body.height * 0.12 : 0))
                }
            }
            sections.append(Section(text: b.out, numbered: false))
        }

        let heading = font(minchoBoldNames, fs + 4)
        let headingPara = Para(font: heading, lineHeight: pitch * 1.4, spacingAfter: pitch)

        // 登場人物
        if !doc.characters.isEmpty {
            let b = Builder(page: page)
            b.add("「\(title)」・登場人物", headingPara)
            for c in doc.characters {
                let name = TextFormat.padRight(TextFormat.toFullWidth(c.name), to: Int(nameW))
                let chara = TextFormat.toFullWidth(c.chara.isEmpty ? c.name : c.chara)
                b.add(name + TextFormat.spaces(Int(gap)) + chara,
                      Para(font: mincho, headIndent: (nameW + gap) * fs, lineHeight: pitch, spacingAfter: pitch * 0.4))
            }
            sections.append(Section(text: b.out, numbered: true))
        }

        // シノプシス
        if !doc.synopsis.isEmpty {
            let b = Builder(page: page)
            b.add("「\(title)」・シノプシス", headingPara)
            for para in TextFormat.toFullWidth(doc.synopsis).replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
                b.add(String(para), Para(font: mincho, firstIndent: fs * 3, headIndent: fs * 2, lineHeight: pitch))
            }
            sections.append(Section(text: b.out, numbered: true))
        }

        // 本文
        let chars = doc.characterById
        let styles = doc.styleByType
        var body: Builder?
        for scene in doc.scenes {
            if body == nil || page.sceneBreak {
                if let b = body { sections.append(Section(text: b.out, numbered: true)) }
                body = Builder(page: page)
            }
            let b = body!
            b.add(TextFormat.toFullWidth(scene.name),
                  Para(font: gothic, sceneHeading: true, firstIndent: fs * 2, headIndent: fs * 2, lineHeight: pitch * 1.3,
                       spacingBefore: b.out.length == 0 ? pitch * 0.3 : pitch * 1.5, spacingAfter: pitch * 0.8))
            if !scene.description.isEmpty {
                b.add(TextFormat.toFullWidth(scene.description),
                      Para(font: mincho, firstIndent: (nameW + gap + 1) * fs, headIndent: (nameW + gap) * fs, lineHeight: pitch, spacingAfter: pitch * 0.6))
            }
            for line in doc.lines(of: scene) {
                let f = ScriptFormatter.format(line, characters: chars, styles: styles, useKagikakko: doc.setting.useKagikakko)
                let st = f.style
                let name = TextFormat.toFullWidth(st.showsName ? f.characterName : "")
                let abbr = TextFormat.toFullWidth(st.abbreviation)
                let text = TextFormat.toFullWidth(f.text, asciiSymbols: true)
                let bodyIndent = CGFloat(min(st.indent, 10))
                let head: String
                if name.isEmpty {
                    head = abbr.isEmpty ? TextFormat.spaces(Int(nameW)) : TextFormat.padLeft(abbr, to: Int(nameW))
                } else {
                    head = TextFormat.padRight(abbr.isEmpty ? name : name + "　" + abbr, to: Int(nameW))
                }
                let hanging = (nameW + gap + bodyIndent) * fs
                let p = Para(font: mincho, headIndent: hanging, lineHeight: pitch,
                             spacingBefore: CGFloat(st.marginBefore) * pitch, spacingAfter: pitch * 0.35 + CGFloat(st.marginAfter) * pitch)
                b.add(head + TextFormat.spaces(Int(gap + bodyIndent)) + text, p)
            }
        }
        if let b = body { sections.append(Section(text: b.out, numbered: true)) }
        return sections
    }
}
