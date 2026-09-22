import SwiftUI
import ScenarioWriterCore

/// 登場人物設定
struct CastView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("editorVertical") private var vertical = false
    @State private var confirmDelete: CastMember?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("登場人物 \(model.characters.count)").foregroundStyle(.secondary)
                Spacer()
                Button { model.addCharacter() } label: { Label("登場人物追加", systemImage: "person.badge.plus") }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if vertical {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        // 件数が少ないので HStack。LazyHStack を右から左にすると SwiftUI が列を何度も作り直す
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(model.characters) { c in
                                CastRow(member: c, onDelete: { confirmDelete = c }, vertical: true, columnHeight: geo.size.height - 24)
                                    .id(c.id)
                                    .contextMenu { castMenu(c) }
                            }
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(12)
                        .frame(minWidth: geo.size.width, alignment: .trailing)
                    }
                    // 先頭（右端）から始める
                    .onAppear {
                        if let first = model.characters.first?.id { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(first, anchor: UnitPoint(x: 1, y: 0)) } }
                    }
                    }
                }
            } else {
                List {
                    ForEach(model.characters) { c in
                        CastRow(member: c, onDelete: { confirmDelete = c })
                            .contextMenu { castMenu(c) }
                    }
                    .onMove { model.moveCharacters(from: $0, to: $1) }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }
        }
        .confirmationDialog("「\(confirmDelete?.name ?? "")」を削除しますか？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("削除する", role: .destructive) { if let c = confirmDelete { model.deleteCharacter(c) }; confirmDelete = nil }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        } message: { Text("この人物を使っている台詞は名前なしになります（台詞そのものは残ります）。") }
    }

    @ViewBuilder
    private func castMenu(_ c: CastMember) -> some View {
        Button(vertical ? "前へ（右へ）" : "上へ") { model.moveCharacter(c, up: true) }
        Button(vertical ? "次へ（左へ）" : "下へ") { model.moveCharacter(c, up: false) }
        Divider()
        Button("削除…", role: .destructive) { confirmDelete = c }
    }
}

struct CastRow: View {
    @EnvironmentObject private var model: AppModel
    let member: CastMember
    let onDelete: () -> Void
    var vertical: Bool = false
    var columnHeight: CGFloat = 400
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0
    @Environment(\.colorScheme) private var scheme
    @State private var draft = CastMember()
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if vertical { verticalBody } else { horizontalBody }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { draft = member }
        .onChange(of: member) { _, new in if new != draft { saveTask?.cancel(); saveTask = nil; draft = new } }
        .onChange(of: draft) { _, new in
            guard new != member else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                model.updateCharacter(new)
                saveTask = nil
            }
        }
    }

    /// 縦書き: 1 人 1 列。上に番号とボタン、その下に人物名（縦書き）と人物設定（縦書き）
    private var verticalBody: some View {
        let headerH: CGFloat = 60
        return VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text("\(index + 1)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("\(lineCount) 台詞").font(.caption2).foregroundStyle(.tertiary)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("削除")
            }
            HStack(alignment: .top, spacing: 6) {
                // 人物設定の既定の幅は台本画面のセレクトボックスと同じ
                VerticalField(text: $draft.chara, placeholder: "人物設定", height: min(max(columnHeight - headerH, 160), charaExtent),
                              color: NSColor(charaColor), styleSize: model.textStyle(.character).fontSize, minWidth: 148)
                VerticalField(text: $draft.name, placeholder: "登場人物名", height: max(columnHeight - headerH, 160), sizeDelta: 2)
            }
        }
        .padding(6)
    }

    private var horizontalBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("登場人物名", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .frame(maxWidth: 320)
                    Spacer()
                    Text("\(lineCount) 台詞").font(.caption2).foregroundStyle(.tertiary)
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("削除")
                }
                TextField("人物設定（年齢・性格など。台本の人物表に出ます）", text: $draft.chara, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...8)
                    .font(Font(EditorFont.font(family: fontFamily, size: EditorFont.pointSize(base: fontBase, styleSize: model.textStyle(.character).fontSize))))
                    .foregroundStyle(charaColor)
                    .frame(maxWidth: charaExtent + 8, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    /// 固定スタイル「登場人物」の色
    private var charaColor: Color { Color.adaptive(hex: model.textStyle(.character).color, dark: scheme == .dark) }
    /// 人物設定の本文の長さ（「読む」と同じ文字数）
    private var charaExtent: CGFloat {
        let ts = model.textStyle(.character)
        return EditorMetrics.bodyExtent(chars: model.setting.bodyLength, indent: ts.indent, pointSize: EditorFont.pointSize(base: fontBase, styleSize: ts.fontSize), kern: CGFloat(kern))
    }
    private var index: Int { model.characters.firstIndex { $0.id == member.id } ?? 0 }
    private var lineCount: Int {
        guard let store = model.store, let sid = model.selectedScenarioId else { return 0 }
        return (try? store.allLines(scenarioId: sid).filter { $0.characterId == member.id }.count) ?? 0
    }
}
