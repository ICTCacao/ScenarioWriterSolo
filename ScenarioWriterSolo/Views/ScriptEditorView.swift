import SwiftUI
import ScenarioWriterCore

/// 台本編集（いちばん使う画面）。場面を選び、行を書く・並べ替える・追加する。
struct ScriptEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    /// 設定 › 書式「編集の書き方向」
    @AppStorage("editorVertical") private var vertical = false

    var body: some View {
        VStack(spacing: 0) {
            sceneBar
            Divider()
            if model.scenes.isEmpty {
                ContentUnavailableView {
                    Label("場面がありません", systemImage: "theatermasks")
                } description: {
                    Text("「場面」画面で場面を追加すると台詞を書けます。")
                } actions: {
                    Button("場面を追加") { model.addScene(); model.section = .scenes }
                }
            } else if vertical {
                verticalLines
            } else {
                linesList
            }
        }
    }

    /// 縦書き: 行を右から左へ並べる。見えている列だけを作る（VerticalColumnsView）。
    /// LazyHStack を右から左（layoutDirection RTL）で使うと SwiftUI が見えていない列まで大量に作り、
    /// 全画面の解除などウインドウの大きさが変わったときに数十秒固まる（2026-09-22 のハング）
    private var verticalLines: some View {
        GeometryReader { geo in
            VerticalColumnsView(columnHeight: geo.size.height - 24, menu: { line in AnyView(lineMenu(line)) })
        }
    }

    private var sceneBar: some View {
        HStack(spacing: 8) {
            Button { model.selectScene(offset: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(model.scenes.first?.id == model.selectedSceneId)
                .help("前の場面（⌘[）")
            Picker("場面", selection: Binding(get: { model.selectedSceneId ?? 0 }, set: { model.selectedSceneId = $0 })) {
                ForEach(Array(model.scenes.enumerated()), id: \.element.id) { i, s in
                    Text("\(i + 1). \(s.name.isEmpty ? "（無題の場面）" : s.name)").tag(s.id)
                }
            }
            .labelsHidden()
            .frame(width: 280)
            Button { model.selectScene(offset: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(model.scenes.last?.id == model.selectedSceneId)
                .help("次の場面（⌘]）")
            if let s = model.selectedScene, !s.description.isEmpty {
                Text(s.description.replacingOccurrences(of: "\n", with: " "))
                    .foregroundStyle(Color.adaptive(hex: "#006400", dark: scheme == .dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 8)
            }
            Text("\(model.lines.count) 行").foregroundStyle(.secondary).font(.caption).fixedSize()
            Button { model.insertLine(after: nil) } label: { Label("行を追加", systemImage: "plus") }
                .help("末尾に行を追加（選択中の行の下に足すには ⌘⏎）")
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var linesList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.lines) { line in
                    LineRowView(line: line)
                        .id(line.id)
                        .listRowSeparator(.visible)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.selectedLineId == line.id ? Color.primary.opacity(0.05) : Color.clear)
                                .padding(.horizontal, 4)
                        )
                        .contextMenu { lineMenu(line) }
                }
                .onMove { model.moveLines(from: $0, to: $1) }
                if model.lines.isEmpty {
                    Text("まだ台詞がありません。右上の「行を追加」か ⌘⏎ で書き始めてください。")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                // 末尾に余白（最後の行の下にも追加ボタン）
                HStack {
                    Spacer()
                    Button { model.insertLine(after: nil) } label: { Label("この下に行を追加", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .onChange(of: model.focusRequestLineId) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func lineMenu(_ line: ScriptLine) -> some View {
        Button("この下に行を追加") { model.insertLine(after: line.id) }
        Button("この上に行を追加") { model.insertLine(before: line.id) }
        Divider()
        Button(vertical ? "前へ（右へ）" : "上へ") { model.moveLine(line.id, up: true) }
        Button(vertical ? "次へ（左へ）" : "下へ") { model.moveLine(line.id, up: false) }
        if model.scenes.count > 1 {
            Menu("別の場面の末尾へ移す") {
                ForEach(model.scenes.filter { $0.id != line.sceneId }) { s in
                    Button(s.name.isEmpty ? "（無題の場面）" : s.name) { model.moveLine(line.id, toScene: s.id) }
                }
            }
        }
        Divider()
        Button("削除", role: .destructive) { model.deleteLine(line.id) }
    }
}

/// 1 行。左に種別と人物、右に本文（クリックしてその場で直す・自動保存）。
struct LineRowView: View {
    @EnvironmentObject private var model: AppModel
    let line: ScriptLine
    var vertical: Bool = false
    var columnHeight: CGFloat = 400

    @State private var text: String
    @State private var saveTask: Task<Void, Never>?
    @State private var focused = false
    @State private var wantsFocus = false
    @State private var hovering = false
    /// 縦書き: 本文欄の実測幅（VerticalColumnsView に preference で渡す）
    @State private var measuredTextWidth: CGFloat?
    @Environment(\.colorScheme) private var scheme
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.lineHeightKey) private var lineHeight = 1.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0

    /// 本文の @State は最初から行の本文で作る。空で始めて onAppear で入れる方式だと、onAppear より先に
    /// 「書きかけを確定」の通知が来たとき空文字を保存してしまう（本文が消える）
    init(line: ScriptLine, vertical: Bool = false, columnHeight: CGFloat = 400) {
        self.line = line
        self.vertical = vertical
        self.columnHeight = columnHeight
        _text = State(initialValue: line.text)
    }

    private var style: ResolvedStyle { model.resolvedStyle(for: line.type) }
    private var color: Color { Color.adaptive(hex: style.color, dark: scheme == .dark) }

    var body: some View {
        Group {
            if vertical { verticalBody } else { horizontalBody }
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedLineId = line.id }
        .onHover { hovering = $0 }
        .onChange(of: line.text) { _, new in if !focused, new != text { text = new } }
        .onChange(of: model.focusRequestLineId) { _, id in
            if id == line.id {
                wantsFocus = true
                model.focusRequestLineId = nil
            }
        }
        .onAppear {
            if model.focusRequestLineId == line.id { wantsFocus = true; model.focusRequestLineId = nil }
        }
        // メニュー（⌘⏎ など）から行を操作する前に、書きかけを保存する
        .onReceive(NotificationCenter.default.publisher(for: .swFlushLineEdits)) { _ in flushSave() }
    }

    /// 本文欄（横書き・縦書き共通）
    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("本文").foregroundStyle(.tertiary).padding(.top, 4).padding(.leading, 6).allowsHitTesting(false)
            }
            LineTextView(text: $text,
                         font: EditorFont.font(family: fontFamily, size: EditorFont.pointSize(base: fontBase, styleSize: style.fontSize)),
                         color: NSColor(color),
                         lineHeightMultiple: CGFloat(lineHeight),
                         kern: CGFloat(kern),
                         vertical: vertical,
                         fixedWidth: vertical ? nil : EditorMetrics.bodyExtent(chars: model.setting.bodyLength, indent: style.indent, pointSize: pointSize, kern: CGFloat(kern)),
                         requestFocus: wantsFocus,
                         onFocusChange: { f in
                             focused = f
                             if f { model.selectedLineId = line.id } else { flushSave() }
                         },
                         onFocusRequestHandled: { wantsFocus = false },
                         onCommandReturn: { shift in
                             flushSave()
                             if shift { model.insertLine(before: line.id) } else { model.insertLine(after: line.id) }
                         },
                         onNavigate: { offset in
                             flushSave()
                             model.focusLine(offset: offset, from: line.id)
                         },
                         onMeasuredWidth: vertical ? { w, h in
                             // ウインドウの大きさが変わる途中の一時的な高さで測った値は使わない
                             if h == verticalTextHeight, measuredTextWidth != w { measuredTextWidth = w }
                         } : nil)
            .id(vertical)
        }
        // 縦書き: 本文欄の実際の幅を列配置（VerticalColumnsView）に知らせる
        .preference(key: VerticalTextWidthKey.self, value: (vertical ? measuredTextWidth : nil).map { [line.id: $0] } ?? [:])
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(focused ? Color.primary.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(focused ? Color.secondary.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
        .onChange(of: text) { _, new in scheduleSave(new) }
    }

    private var pointSize: CGFloat { EditorFont.pointSize(base: fontBase, styleSize: style.fontSize) }

    /// 縦書きの本文欄の高さ（VerticalColumnsView の見積もりと同じ式）
    private var verticalTextHeight: CGFloat {
        Self.verticalTextHeight(columnHeight: columnHeight, indent: style.indent, bodyLength: model.setting.bodyLength, pointSize: pointSize, kern: CGFloat(kern))
    }

    /// 縦書きの本文欄の高さ: 列に入る高さと、「読む」と同じ本文の文字数（−字下げ）ぶんの短いほう
    static func verticalTextHeight(columnHeight: CGFloat, indent: Int, bodyLength: Int, pointSize: CGFloat, kern: CGFloat) -> CGFloat {
        let available = max(columnHeight - 64 - CGFloat(min(indent, 8)) * 14, 120)
        return min(available, EditorMetrics.bodyExtent(chars: bodyLength, indent: indent, pointSize: pointSize, kern: kern))
    }

    /// 縦書きの 1 列: 上に種別・人物、下に本文（上から下へ）。列は右から左へ並ぶ
    private var verticalBody: some View {
        let headerW: CGFloat = 120 + 4 + 24   // 種別 + メニューボタン。列の最小幅にする
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                typePicker.frame(width: 120)
                Menu {
                    Button("この左に行を追加") { model.insertLine(after: line.id) }
                    Button("この右に行を追加") { model.insertLine(before: line.id) }
                    Divider()
                    Button("前へ（右へ）") { model.moveLine(line.id, up: true) }
                    Button("次へ（左へ）") { model.moveLine(line.id, up: false) }
                    Divider()
                    Button("削除", role: .destructive) { model.deleteLine(line.id) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .opacity(hovering || model.selectedLineId == line.id ? 1 : 0.25)
            }
            HStack {
                Spacer(minLength: 0)
                if style.showsName { characterPicker.frame(width: 120) }
                else { Text(style.abbreviation).font(.caption).foregroundStyle(color).frame(height: 22) }
            }
            // 本文は列の右端から始める（縦書きの 1 行目は右）。列の幅は上の選択ボックス幅を最小にして、本文が長ければ左へ広がる
            textEditor
                .frame(height: verticalTextHeight)
                .frame(minWidth: headerW, alignment: .trailing)
                .padding(.top, CGFloat(min(style.indent, 8)) * 14)   // 字下げは上から
        }
        .frame(minWidth: headerW, alignment: .trailing)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(model.selectedLineId == line.id ? Color.primary.opacity(0.05) : Color.clear)
        )
    }

    private var horizontalBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    typePicker
                    if style.showsName { characterPicker }
                    else if !style.abbreviation.isEmpty {
                        Text(style.abbreviation).font(.caption).foregroundStyle(color).padding(.leading, 4)
                    }
                }
                .frame(width: 170, alignment: .leading)

                HStack(alignment: .top, spacing: 0) {
                    if style.indent > 0 {
                        Color.clear.frame(width: CGFloat(min(style.indent, 8)) * 14)
                    }
                    if style.kagikakko {
                        Text("「").foregroundStyle(color.opacity(0.6)).padding(.top, 3)
                    }
                    // 本文は「読む」と同じ文字数で折り返す（幅は LineTextView の fixedWidth で固定）
                    textEditor
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("この下に行を追加") { model.insertLine(after: line.id) }
                    Button("この上に行を追加") { model.insertLine(before: line.id) }
                    Divider()
                    Button("上へ") { model.moveLine(line.id, up: true) }
                    Button("下へ") { model.moveLine(line.id, up: false) }
                    Divider()
                    Button("削除", role: .destructive) { model.deleteLine(line.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .opacity(hovering || model.selectedLineId == line.id ? 1 : 0.25)
            }
            .padding(.vertical, 4)
            // 行の下の「＋」バー（マウスを乗せると出る）
            HStack {
                Spacer()
                Button { flushSave(); model.insertLine(after: line.id) } label: {
                    Label("この下に追加", systemImage: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0)
                Spacer()
            }
            .frame(height: 12)
        }
    }

    private var typePicker: some View {
        Picker("種別", selection: Binding(get: { line.type }, set: { t in
            var l = line; l.type = t
            if !model.resolvedStyle(for: t).showsName { /* 人物はそのまま残す（Web 版と同じ） */ }
            model.updateLine(l)
        })) {
            ForEach(model.styles) { s in
                Text(s.name).tag(s.styleId)
            }
            if model.styleByType[line.type] == nil { Text("種別 \(line.type)").tag(line.type) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(color)
    }

    private var characterPicker: some View {
        Picker("登場人物", selection: Binding(get: { line.characterId ?? 0 }, set: { c in
            var l = line; l.characterId = c == 0 ? nil : c
            model.updateLine(l)
        })) {
            Text("（人物なし）").tag(Int64(0))
            ForEach(model.characters) { c in Text(c.name).tag(c.id) }
            if let cid = line.characterId, model.characterById[cid] == nil { Text("（削除された人物）").tag(cid) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fontWeight(.semibold)
    }

    private func scheduleSave(_ new: String) {
        guard new != line.text else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        guard text != line.text else { return }
        var l = line; l.text = text
        model.updateLine(l)
    }
}
