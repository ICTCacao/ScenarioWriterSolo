import SwiftUI
import ScenarioWriterCore

/// 縦書きの本文欄の実測幅（行 ID → 幅）。列配置の見積もりを実測で置き換える
struct VerticalTextWidthKey: PreferenceKey {
    static let defaultValue: [Int64: CGFloat] = [:]
    static func reduce(value: inout [Int64: CGFloat], nextValue: () -> [Int64: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 縦書きの列配置。行を右から左へ並べ、見えている列（＋前後の余裕）だけ LineRowView を作る。
///
/// LazyHStack を layoutDirection = .rightToLeft で使うと、SwiftUI が見えていない列まで大量に作る
/// （左から右なら全画面の出入りで数列なのに、右から左だと百数十列、条件によっては全行）。
/// 行が数百ある場面ではウインドウの大きさが変わるたびに数十秒固まるので、列の幅を自分で見積もって
/// 位置を決め、表示する範囲だけを ForEach で作る。
struct VerticalColumnsView: View {
    @EnvironmentObject private var model: AppModel
    let columnHeight: CGFloat
    let menu: (ScriptLine) -> AnyView

    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.lineHeightKey) private var lineHeight = 1.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0

    /// LineRowView.verticalBody と同じ寸法
    static let headerW: CGFloat = 120 + 4 + 24
    /// 選択ボックスを閉じているとき（縦書きの人物名だけ）の見出し幅
    static let collapsedHeaderW: CGFloat = 26
    static let headerH: CGFloat = 64
    static let rowPadding: CGFloat = 6
    static let spacing: CGFloat = 4
    static let sidePad: CGFloat = 12
    static let topPad: CGFloat = 8
    static let addColumnW: CGFloat = 100
    /// 見えている範囲の外側にこれだけ余分に作っておく（スクロール中に白く抜けないように）
    static let overscan: CGFloat = 300

    /// 行 ID → 本文欄の幅（見積もり。表示中の列は実測で置き換える）。列の幅は columnWidth(_:_:) で出す
    @State private var widths: [Int64: CGFloat] = [:]
    /// 見積もりの条件（行の本文・種別・列の高さ・フォント）。変わったら見積もり直す
    @State private var widthKeys: [Int64: Int] = [:]
    @State private var viewport: CGRect = .zero
    /// ScrollView の左の余白（contentInsets.leading）。サイドバーの下まで広がる ScrollView では
    /// サイドバーの幅ぶんあり、visibleRect はその余白を含めて数える（左端で minX = −280）が、scrollTo(x:) の x は
    /// 余白の内側から数える。そのまま渡すと ⌘⏎ のたびに約 280pt 左へ飛んだ
    @State private var offsetDelta: CGFloat = 0
    @State private var scrollPos = ScrollPosition(edge: .trailing)
    @State private var refreshTask: Task<Void, Never>?
    /// viewport の大きさが決まる前に来たスクロール要求（行 ID。0 = 先頭）
    @State private var pendingScroll: Int64?

    /// 列の位置。index 順に右から左へ
    private struct Layout {
        var lefts: [CGFloat] = []
        var widths: [CGFloat] = []
        var totalW: CGFloat = 0
        func right(_ i: Int) -> CGFloat { lefts[i] + widths[i] }
    }

    private func makeLayout(_ lines: [ScriptLine]) -> Layout {
        var l = Layout()
        l.lefts.reserveCapacity(lines.count); l.widths.reserveCapacity(lines.count)
        var used: CGFloat = 0
        for line in lines {
            let w = columnWidth(line.id, widths[line.id] ?? 0)
            l.widths.append(w)
            used += w + Self.spacing
        }
        l.totalW = Self.sidePad + Self.addColumnW + Self.spacing + used + Self.sidePad
        var x = l.totalW - Self.sidePad
        for w in l.widths { x -= w; l.lefts.append(x); x -= Self.spacing }
        return l
    }

    /// 見えている範囲（＋余裕）に掛かる行の index 範囲
    private func visibleRange(_ l: Layout, count: Int) -> Range<Int> {
        guard count > 0, viewport.width > 0 else { return 0..<min(count, 12) }
        let x0 = viewport.minX - Self.overscan, x1 = viewport.maxX + Self.overscan
        // lefts は index が増えるほど小さい。x1 より右端が小さくなる最初の index が lo
        var lo = 0, hi = count
        while lo < hi { let m = (lo + hi) / 2; if l.right(m) > x1 { lo = m + 1 } else { hi = m } }
        var lo2 = lo, hi2 = count
        while lo2 < hi2 { let m = (lo2 + hi2) / 2; if l.lefts[m] < x0 { hi2 = m } else { lo2 = m + 1 } }
        return lo..<max(lo, lo2)
    }

    /// 列の幅 = max(見出し幅, 本文幅) + 余白。見出しは選択ボックスを開いている行だけ広い
    private func columnWidth(_ id: Int64, _ textW: CGFloat) -> CGFloat {
        max(model.headerEditLineId == id ? Self.headerW : Self.collapsedHeaderW, textW) + Self.rowPadding * 2
    }

    var body: some View {
        let lines = model.lines
        let layout = makeLayout(lines)
        let range = visibleRange(layout, count: lines.count)
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: layout.totalW, height: columnHeight + Self.topPad * 2)
                ForEach(lines[range], id: \.id) { line in
                    let i = lines.firstIndex(where: { $0.id == line.id }) ?? 0
                    LineRowView(line: line, vertical: true, columnHeight: columnHeight)
                        .contextMenu { menu(line) }
                        .frame(width: layout.widths[i], alignment: .trailing)
                        .offset(x: layout.lefts[i], y: Self.topPad)
                }
                // 末尾（左端）に追加
                VStack {
                    Button { model.insertLine(after: nil) } label: { Label("行を追加", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(width: Self.addColumnW, height: columnHeight)
                .offset(x: Self.sidePad, y: Self.topPad)
                if lines.isEmpty {
                    Text("まだ台詞がありません。右上の「行を追加」か ⌘⏎ で書き始めてください。")
                        .foregroundStyle(.secondary)
                        .padding()
                        .offset(x: Self.sidePad + Self.addColumnW + Self.spacing, y: Self.topPad)
                }
            }
        }
        .scrollPosition($scrollPos)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.leading } action: { _, d in
            if d != offsetDelta { LineTextView.log("scroll: offsetDelta \(offsetDelta) -> \(d)"); offsetDelta = d }
        }
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, new in
            if new != viewport {
                if abs(new.minX - viewport.minX) > 20 { LineTextView.log("scroll: viewport minX \(viewport.minX) -> \(new.minX) w=\(new.width)") }
                viewport = new
            }
            if let p = pendingScroll, new.width > 0 { pendingScroll = nil; scroll(toLine: p, in: model.lines, animated: false) }
        }
        .onPreferenceChange(VerticalTextWidthKey.self) { measured in
            // 本文欄の実測幅（列幅は columnWidth で見出し幅・余白を足す）
            var changed = false
            for (id, w) in measured {
                if abs((widths[id] ?? -1) - w) > 0.5 {
                    LineTextView.log("columns: id=\(id) est=\(widths[id] ?? -1) actual=\(w)")
                    widths[id] = w; changed = true
                }
            }
            if changed { LineTextView.log("columns: measured \(measured.count) updated") }
        }
        .onAppear { refreshWidths(lines, force: true); scrollToStart(lines) }
        .onChange(of: linesSignature(lines)) { _, _ in refreshWidths(lines, force: false) }
        .onChange(of: columnHeight) { _, _ in scheduleRefresh() }
        .onChange(of: fontSignature) { _, _ in scheduleRefresh() }
        .onChange(of: model.setting.bodyLength) { _, _ in scheduleRefresh() }
        .onChange(of: layout.totalW) { old, new in
            // 内容の幅が変わっても右端からの距離を保つ（右から左へ読むので、右端基準のほうが自然）。
            // 左端までスクロールしているとき（場面の最後を書いているとき）も保つ。保たないと ⌘⏎ で列が増えるたびに本文が右へずれる
            guard old > 0, viewport.width > 0 else { return }
            let fromRight = old - viewport.maxX
            let x = max(0, min(new - viewport.width, new - fromRight - viewport.width))
            LineTextView.log("scroll: totalW \(old) -> \(new) keepRight x \(viewport.minX) -> \(x)")
            scrollTo(visibleX: x)
            // 続けて幅が変わったとき（新しい行の見積もり → 実測など）に古い位置から計算しないよう、すぐ反映しておく
            viewport.origin.x = x
        }
        .onChange(of: model.selectedSceneId) { _, _ in scrollToStart(model.lines) }
        .onChange(of: model.focusRequestLineId) { _, id in
            guard let id else { return }
            // 行を足した直後は、上の「右端からの距離を保つ」スクロールが済んでから見えているか調べる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reveal(id) }
        }
    }

    /// 行が見えていなければ見えるところまで動かす
    private func reveal(_ id: Int64) {
        guard viewport.width > 0, let i = model.lines.firstIndex(where: { $0.id == id }) else { return }
        let l = makeLayout(model.lines)
        // 見えていれば動かさない。見えていなければ、見えるところまでだけ動かす（⌘⏎ で足した行など、
        // 本文の位置をなるべく動かさない）。遠く離れた行（検索で飛ぶなど）は中央へ
        if l.lefts[i] >= viewport.minX && l.right(i) <= viewport.maxX { return }
        LineTextView.log("scroll: reveal id=\(id) col=\(l.lefts[i])..\(l.right(i)) viewport=\(viewport.minX)..\(viewport.maxX)")
        let margin: CGFloat = 24
        let x = l.lefts[i] < viewport.minX
            ? l.lefts[i] - margin                          // 左にはみ出す → 列の左端が見えるまで
            : l.right(i) + margin - viewport.width         // 右にはみ出す → 列の右端が見えるまで
        if abs(x - viewport.minX) > viewport.width {
            scroll(toLine: id, in: model.lines, animated: true)
            return
        }
        let clamped = max(0, min(l.totalW - viewport.width, x))
        withAnimation(.easeOut(duration: 0.15)) { scrollTo(visibleX: clamped) }
    }

    /// 見えている範囲の左端（visibleRect.minX）を x にする
    private func scrollTo(visibleX x: CGFloat) {
        scrollPos.scrollTo(x: x + offsetDelta)
    }

    private var fontSignature: String { "\(fontFamily)/\(fontBase)/\(lineHeight)/\(kern)" }

    private func linesSignature(_ lines: [ScriptLine]) -> Int {
        var h = Hasher()
        for l in lines { h.combine(l.id); h.combine(l.type); h.combine(l.text) }
        return h.finalize()
    }

    /// 高さやフォントが変わったとき: 変化が落ち着いてから見積もり直す（ウインドウの大きさが変わる途中の
    /// 一時的な高さで全行を測ると無駄なので）
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            refreshWidths(model.lines, force: false)
        }
    }

    /// 列幅の見積もり。条件（本文・種別・高さ・フォント）が変わった行だけ測り直す
    private func refreshWidths(_ lines: [ScriptLine], force: Bool) {
        var newWidths: [Int64: CGFloat] = [:]
        var newKeys: [Int64: Int] = [:]
        var measured = 0
        for line in lines {
            let style = model.resolvedStyle(for: line.type)
            let pointSize = EditorFont.pointSize(base: fontBase, styleSize: style.fontSize)
            let h = LineRowView.verticalTextHeight(columnHeight: columnHeight, indent: style.indent, bodyLength: model.setting.bodyLength,
                                                   pointSize: pointSize, kern: CGFloat(kern))
            var k = Hasher()
            k.combine(line.text); k.combine(line.type); k.combine(h); k.combine(fontSignature)
            let key = k.finalize()
            if !force, widthKeys[line.id] == key, let w = widths[line.id] {
                newWidths[line.id] = w; newKeys[line.id] = key
                continue
            }
            let font = EditorFont.font(family: fontFamily, size: pointSize)
            let tw = AutoHeightTextView.verticalWidth(text: line.text, font: font, lineHeightMultiple: CGFloat(lineHeight),
                                                      kern: CGFloat(kern), height: h)
            newWidths[line.id] = tw
            newKeys[line.id] = key
            measured += 1
        }
        if measured > 0 { LineTextView.log("columns: estimated \(measured) of \(lines.count) height=\(columnHeight)") }
        if newWidths != widths { widths = newWidths }
        widthKeys = newKeys
    }

    /// 先頭（右端）へ。フォーカスしたい行・選択中の行があればそこへ
    private func scrollToStart(_ lines: [ScriptLine]) {
        let target = (model.focusRequestLineId ?? model.selectedLineId).flatMap { id in lines.contains { $0.id == id } ? id : nil } ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scroll(toLine: target, in: model.lines, animated: false) }
    }

    /// 行を中央へ（0 なら先頭＝右端へ）。viewport の大きさが未定なら決まってから
    private func scroll(toLine id: Int64, in lines: [ScriptLine], animated: Bool) {
        LineTextView.log("scroll: toLine id=\(id) animated=\(animated)")
        guard viewport.width > 0 else { pendingScroll = id; return }
        guard id != 0, let i = lines.firstIndex(where: { $0.id == id }) else { scrollPos.scrollTo(edge: .trailing); return }
        let l = makeLayout(lines)
        let x = max(0, min(l.totalW - viewport.width, l.lefts[i] + l.widths[i] / 2 - viewport.width / 2))
        if animated { withAnimation { scrollTo(visibleX: x) } } else { scrollTo(visibleX: x) }
    }
}
