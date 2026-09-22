import SwiftUI
import ScenarioWriterCore

/// シノプシス（あらすじ）。自動保存。
struct SynopsisView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("editorVertical") private var vertical = false
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.lineHeightKey) private var lineHeight = 1.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var saved = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("あらすじ・梗概。ダウンロードした台本（テキスト / Word）の冒頭と、HTML・「読む」画面に入ります。")
                    .foregroundStyle(.secondary).font(.callout)
                Spacer()
                Text(saved ? "保存済み" : "保存中…").font(.caption).foregroundStyle(.tertiary)
                Text("\(text.count) 文字").font(.caption).foregroundStyle(.secondary)
            }
            // 固定スタイル「シノプシス」のサイズと色
            let ts = model.textStyle(.synopsis)
            let font = EditorFont.font(family: fontFamily, size: EditorFont.pointSize(base: fontBase, styleSize: ts.fontSize))
            let color = Color.adaptive(hex: ts.color, dark: scheme == .dark)
            // 「読む」と同じ本文の文字数で折り返す
            let bodyChars = max(model.setting.bodyLength - max(ts.indent, 0), 4)
            if vertical {
                // 縦書き: 右から左へ、上から下へ。横にスクロール
                VerticalTextEditor(text: $text, font: font, color: NSColor(color),
                                   lineHeightMultiple: CGFloat(lineHeight), kern: CGFloat(kern), bodyChars: bodyChars)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .padding(8)
            } else {
                TextEditor(text: $text)
                    .font(Font(font))
                    .foregroundStyle(color)
                    .lineSpacing(6)
                    .frame(maxWidth: CGFloat(bodyChars) * (font.pointSize + CGFloat(max(kern, 0))) + 28, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            }
        }
        .padding()
        .onAppear { text = model.synopsis }
        .onChange(of: model.selectedScenarioId) { _, _ in text = model.synopsis; saved = true }
        .onChange(of: model.synopsis) { _, new in if new != text { saveTask?.cancel(); text = new; saved = true } }
        .onChange(of: text) { _, new in
            guard new != model.synopsis else { return }
            saved = false
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                model.saveSynopsis(new)
                saved = true
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if text != model.synopsis { model.saveSynopsis(text) }
        }
    }
}
