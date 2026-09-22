import SwiftUI
import ScenarioWriterCore

/// 場面設定
struct ScenesView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("editorVertical") private var vertical = false
    @State private var confirmDelete: ScriptScene?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("場面 \(model.scenes.count)　合計 \(timeString(model.totalSceneSeconds))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.showBulkScenes = true } label: { Label("一括追加…", systemImage: "square.grid.3x3") }
                    .popover(isPresented: $model.showBulkScenes) { BulkScenesPopover() }
                Button { model.addScene() } label: { Label("場面追加", systemImage: "plus") }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if vertical {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        // 件数が少ないので HStack。LazyHStack を右から左にすると SwiftUI が列を何度も作り直す
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(model.scenes) { s in
                                SceneRow(scene: s, onDelete: { confirmDelete = s }, vertical: true, columnHeight: geo.size.height - 24)
                                    .id(s.id)
                                    .contextMenu { sceneMenu(s) }
                            }
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(12)
                        .frame(minWidth: geo.size.width, alignment: .trailing)
                    }
                    // 先頭（右端）から始める
                    .onAppear {
                        if let first = model.scenes.first?.id { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(first, anchor: UnitPoint(x: 1, y: 0)) } }
                    }
                    }
                }
            } else {
                List {
                    ForEach(model.scenes) { s in
                        SceneRow(scene: s, onDelete: { confirmDelete = s })
                            .contextMenu { sceneMenu(s) }
                    }
                    .onMove { model.moveScenes(from: $0, to: $1) }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }
        }
        .confirmationDialog("場面「\(confirmDelete?.name ?? "")」を削除しますか？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("台詞ごと削除する", role: .destructive) { if let s = confirmDelete { model.deleteScene(s) }; confirmDelete = nil }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        } message: { Text("この場面に書いた台詞もすべて消えます。") }
    }

    @ViewBuilder
    private func sceneMenu(_ s: ScriptScene) -> some View {
        Button("この場面の台本を開く") { model.selectedSceneId = s.id; model.section = .script }
        Divider()
        Button(vertical ? "前へ（右へ）" : "上へ") { model.moveScene(s, up: true) }
        Button(vertical ? "次へ（左へ）" : "下へ") { model.moveScene(s, up: false) }
        Divider()
        Button("削除…", role: .destructive) { confirmDelete = s }
    }

    static func timeString(_ sec: Int) -> String { String(format: "%d分%02d秒", sec / 60, sec % 60) }
    private func timeString(_ sec: Int) -> String { Self.timeString(sec) }
}

struct SceneRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let scene: ScriptScene
    let onDelete: () -> Void
    var vertical: Bool = false
    var columnHeight: CGFloat = 400
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0
    @State private var draft: ScriptScene = ScriptScene()
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if vertical { verticalBody } else { horizontalBody }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { draft = scene }
        .onChange(of: scene) { _, new in if new != draft { saveTask?.cancel(); saveTask = nil; draft = new } }
        .onChange(of: draft) { _, new in
            guard new != scene else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                model.updateScene(new)
                saveTask = nil
            }
        }
    }

    /// 縦書き: 1 場面 1 列。上に番号・有効・時間・ボタン、その下に場面名（縦書き）、場面説明（縦書き）
    private var verticalBody: some View {
        let headerH: CGFloat = 96
        // 上の 有効・分・秒 の行の幅。場面説明の既定の幅もこれに合わせる
        let controlsW: CGFloat = 200
        return VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text("\(index + 1)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { model.selectedSceneId = scene.id; model.section = .script } label: { Image(systemName: "text.quote") }.help("この場面の台本を開く")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("削除")
            }
            HStack(spacing: 4) {
                Picker("", selection: $draft.validCd) { Text("有効").tag(0); Text("無効").tag(9) }.labelsHidden().frame(width: 70)
                TextField("分", value: $draft.timeMin, format: .number).frame(width: 40).multilineTextAlignment(.trailing)
                Text("分")
                TextField("秒", value: $draft.timeSec, format: .number).frame(width: 40).multilineTextAlignment(.trailing)
                Text("秒")
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: controlsW)
            HStack(alignment: .top, spacing: 6) {
                VerticalField(text: $draft.description, placeholder: "場面説明", height: min(max(columnHeight - headerH, 160), descExtent),
                              color: NSColor(descColor), styleSize: model.textStyle(.sceneDescription).fontSize, minWidth: controlsW)
                VerticalField(text: $draft.name, placeholder: "場面名（柱）", height: max(columnHeight - headerH, 160), sizeDelta: 2)
            }
            Text("\(lineCount) 行").font(.caption2).foregroundStyle(.tertiary)
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
                    TextField("場面名（柱）", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                    Picker("", selection: $draft.validCd) {
                        Text("有効").tag(0)
                        Text("無効").tag(9)
                    }
                    .labelsHidden().frame(width: 80)
                    HStack(spacing: 2) {
                        TextField("分", value: $draft.timeMin, format: .number).frame(width: 44).multilineTextAlignment(.trailing)
                        Text("分")
                        TextField("秒", value: $draft.timeSec, format: .number).frame(width: 44).multilineTextAlignment(.trailing)
                        Text("秒")
                    }
                    .textFieldStyle(.roundedBorder)
                    Button { model.selectedSceneId = scene.id; model.section = .script } label: { Image(systemName: "text.quote") }
                        .help("この場面の台本を開く")
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                        .help("削除")
                }
                TextField("場面説明（場所・時間など。台本にも出ます）", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .font(Font(EditorFont.font(family: fontFamily, size: EditorFont.pointSize(base: fontBase, styleSize: model.textStyle(.sceneDescription).fontSize))))
                    .foregroundStyle(descColor)
                    .frame(maxWidth: descExtent + 8, alignment: .leading)
                Text("\(lineCount) 行").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 固定スタイル「場面説明」の色
    private var descColor: Color { Color.adaptive(hex: model.textStyle(.sceneDescription).color, dark: scheme == .dark) }
    /// 場面説明の本文の長さ（「読む」と同じ文字数）
    private var descExtent: CGFloat {
        let ts = model.textStyle(.sceneDescription)
        return EditorMetrics.bodyExtent(chars: model.setting.bodyLength, indent: ts.indent, pointSize: EditorFont.pointSize(base: fontBase, styleSize: ts.fontSize), kern: CGFloat(kern))
    }
    private var index: Int { model.scenes.firstIndex { $0.id == scene.id } ?? 0 }
    private var lineCount: Int {
        (try? model.store?.lines(sceneId: scene.id).count) ?? 0
    }
}

struct BulkScenesPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var acts = 1
    @State private var scenesPerAct = 3
    @State private var actBefore = "第"
    @State private var actAfter = "幕"
    @State private var sceneBefore = "　"
    @State private var sceneAfter = "場"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("場面を一括追加").font(.headline)
            Stepper("幕の数: \(acts)", value: $acts, in: 1...20)
            Stepper("1 幕あたりの場の数: \(scenesPerAct)", value: $scenesPerAct, in: 1...50)
            HStack(spacing: 4) {
                TextField("", text: $actBefore).frame(width: 40)
                Text("1").foregroundStyle(.secondary)
                TextField("", text: $actAfter).frame(width: 40)
                TextField("", text: $sceneBefore).frame(width: 40)
                Text("1").foregroundStyle(.secondary)
                TextField("", text: $sceneAfter).frame(width: 40)
            }
            Text("例: \(actBefore)1\(actAfter)\(sceneBefore)1\(sceneAfter)").foregroundStyle(.secondary).font(.caption)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("\(acts * scenesPerAct) 場面を追加") {
                    model.addScenesInBulk(acts: acts, scenesPerAct: scenesPerAct, actFormat: (actBefore, actAfter), sceneFormat: (sceneBefore, sceneAfter))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
