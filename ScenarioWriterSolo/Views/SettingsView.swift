import SwiftUI
import ScenarioWriterCore

/// 設定（Web 版「オプション設定」＋データの場所）
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            FormatSettingsView()
                .tabItem { Label("書式", systemImage: "textformat") }
            StylesSettingsView()
                .tabItem { Label("スタイル", systemImage: "paintpalette") }
            DataSettingsView()
                .tabItem { Label("データ", systemImage: "externaldrive") }
        }
        .frame(width: 1040, height: 580)
    }
}

struct FormatSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var s = OptionSetting()
    @State private var name = ""
    @AppStorage("editorVertical") private var editorVertical = false
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.lineHeightKey) private var lineHeight = 1.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0
    private let families = EditorFont.families

    var body: some View {
        Form {
            Section("編集画面") {
                Picker("編集の書き方向", selection: $editorVertical) {
                    Text("横書き").tag(false)
                    Text("縦書き").tag(true)
                }
                .pickerStyle(.segmented)
                Text("縦書きでは、行が右から左へ並び、各行の本文は上から下へ書きます。Tab / ⇧Tab のほか ⌘← / ⌘→ で前後の行へ移れます。ツールバーの「縦書き / 横書き」ボタンでも切り替えられます。「読む」画面の縦書き / 横書きはこれとは別で、読む画面のバーか、読む画面を開いているときのツールバーのボタンで切り替えます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("編集画面のフォント") {
                Picker("フォント", selection: $fontFamily) {
                    Text("システムフォント").tag("")
                    Divider()
                    ForEach(families, id: \.self) { f in Text(f).tag(f) }
                }
                HStack {
                    Text("基準サイズ")
                    Slider(value: $fontBase, in: 10...28, step: 1)
                    Text("\(Int(fontBase)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("行間")
                    Slider(value: $lineHeight, in: 1.0...2.5, step: 0.1)
                    Text(String(format: "%.1f 倍", lineHeight)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("文字間隔")
                    Slider(value: $kern, in: 0...6, step: 0.5)
                    Text(String(format: "%.1f pt", kern)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack(alignment: .top) {
                    Text("見本:").foregroundStyle(.secondary)
                    Text("今宵は月が赤くなるだろうか。\n空はあんなにも青く、日差しは私を優しく包んでいるのに。")
                        .font(Font(EditorFont.font(family: fontFamily, size: EditorFont.pointSize(base: fontBase, styleSize: 12))))
                        .kerning(kern)
                        .lineSpacing((lineHeight - 1.0) * fontBase)
                }
                Text("台本画面の本文欄に使います。基準サイズはスタイルのサイズが 12 のときの大きさで、ほかのサイズはその比率で大きさが決まります（18 なら 1.5 倍）。ツールバーのスライダーでも変えられます。「読む」画面や書き出しには影響しません。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("編集画面のフォントを既定に戻す") { fontFamily = ""; fontBase = 14; lineHeight = 1.0; kern = 0 }
            }
            Section("USER OPTION 設定") {
                Stepper("シナリオヘッダ部（登場人物名欄）の文字数: \(s.characterLength)", value: $s.characterLength, in: 2...30)
                Stepper("シナリオボディ部（本文 1 行）の文字数: \(s.bodyLength)", value: $s.bodyLength, in: 8...80)
                Toggle("台詞を「」で囲む", isOn: $s.useKagikakko)
                Text("文字数はテキスト出力と Word の見出し幅に使います。「」のチェックを外すと、画面・読む・出力すべてで「」を付けません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("あなたの名前") {
                TextField("名前（Word ファイルの作成者欄に入ります）", text: $name)
            }
        }
        .formStyle(.grouped)
        .onAppear { s = model.setting; name = model.userName }
        .onChange(of: s) { _, new in if new != model.setting { model.saveSetting(new) } }
        .onChange(of: name) { _, new in if new != model.userName { model.saveUserName(new) } }
    }
}

/// スタイル一覧の 1 行。行のスタイル（削除できる）か固定スタイル（削除できない）のどちらか
struct StyleRow: Identifiable {
    let id: String
    var line: LineStyle? = nil
    var text: TextStyle? = nil
    var isFixed: Bool { text != nil }
}

/// 表の中で直接直す文字欄。打っている間は手元で持ち、少し待ってから保存する
private struct InlineTextCell: View {
    let value: String
    var width: CGFloat? = nil
    var placeholder = ""
    let onChange: (String) -> Void
    @State private var text = ""
    @State private var task: Task<Void, Never>?
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .onAppear { text = value }
            .onChange(of: value) { _, v in if v != text { text = v } }
            .onChange(of: text) { _, t in
                guard t != value else { return }
                task?.cancel()
                task = Task { try? await Task.sleep(for: .milliseconds(600)); guard !Task.isCancelled else { return }; onChange(t) }
            }
            .onSubmit { task?.cancel(); if text != value { onChange(text) } }
    }
}

/// 表の中で直接直す数値欄（範囲に収める）
private struct InlineIntCell: View {
    let value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 46
    let onChange: (Int) -> Void
    @State private var text = ""
    @State private var task: Task<Void, Never>?
    private func commit() {
        task?.cancel()
        let v = min(max(Int(text.trimmingCharacters(in: .whitespaces)) ?? value, range.lowerBound), range.upperBound)
        text = String(v)
        if v != value { onChange(v) }
    }
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, v in if String(v) != text { text = String(v) } }
            .onChange(of: text) { _, _ in
                task?.cancel()
                task = Task { try? await Task.sleep(for: .milliseconds(800)); guard !Task.isCancelled else { return }; commit() }
            }
            .onSubmit { commit() }
    }
}

/// 表の中で直接直す色
private struct InlineColorCell: View {
    let hex: String
    let onChange: (String) -> Void
    @State private var color: Color = .black
    @State private var task: Task<Void, Never>?
    var body: some View {
        ColorPicker("", selection: $color, supportsOpacity: false)
            .labelsHidden()
            .onAppear { color = Color(hex: hex) }
            .onChange(of: hex) { _, h in color = Color(hex: h) }
            .onChange(of: color) { _, c in
                let h = NSColor(c).hexString
                guard h.lowercased() != hex.lowercased() else { return }
                task?.cancel()
                task = Task { try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }; onChange(h) }
            }
    }
}

struct StylesSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false
    @State private var confirmDelete: LineStyle?
    @State private var showBulkSize = false
    @State private var bulkSize = 12

    private var rows: [StyleRow] {
        model.styles.map { StyleRow(id: "L\($0.id)", line: $0) } + model.textStyles.map { StyleRow(id: "T\($0.kind.rawValue)", text: $0) }
    }

    /// 行のスタイルを部分的に変えて保存する
    private func update(_ s: LineStyle, _ change: (inout LineStyle) -> Void) {
        var n = s; change(&n)
        if n != s { model.updateStyle(n) }
    }
    private func update(_ t: TextStyle, _ change: (inout TextStyle) -> Void) {
        var n = t; change(&n)
        if n != t { model.updateTextStyle(n) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows) {
                TableColumn("順") { r in
                    if let s = r.line { InlineIntCell(value: s.orderNo, range: 0...100000, width: 60) { v in update(s) { $0.orderNo = v } } }
                    else { Text("—").foregroundStyle(.tertiary) }
                }.width(66)
                TableColumn("スタイル名") { r in
                    if let s = r.line {
                        InlineTextCell(value: s.name, placeholder: "スタイル名") { v in
                            let name = v.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty { update(s) { $0.name = name } }
                        }
                    } else if let t = r.text {
                        HStack { Text(t.kind.label); Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }.width(min: 140, ideal: 160)
                TableColumn("番号") { r in Text(r.line.map { "\($0.styleId)" } ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(40)
                TableColumn("サイズ") { r in
                    if let s = r.line { InlineIntCell(value: s.fontSize, range: 6...48) { v in update(s) { $0.fontSize = v } } }
                    else if let t = r.text { InlineIntCell(value: t.fontSize, range: 6...48) { v in update(t) { $0.fontSize = v } } }
                }.width(52)
                TableColumn("色") { r in
                    if let s = r.line { InlineColorCell(hex: s.color) { v in update(s) { $0.color = v } } }
                    else if let t = r.text { InlineColorCell(hex: t.color) { v in update(t) { $0.color = v } } }
                }.width(40)
                TableColumn("字下げ") { r in
                    if let s = r.line { InlineIntCell(value: s.indent, range: 0...20) { v in update(s) { $0.indent = v } } }
                    else if let t = r.text { InlineIntCell(value: t.indent, range: 0...20) { v in update(t) { $0.indent = v } } }
                }.width(52)
                TableColumn("省略文字") { r in
                    if let s = r.line { InlineTextCell(value: s.abbreviation, width: 64) { v in update(s) { $0.abbreviation = v } } }
                }.width(72)
                TableColumn("余白 前 / 後") { r in
                    HStack(spacing: 4) {
                        if let s = r.line {
                            InlineIntCell(value: s.marginBefore, range: 0...4, width: 40) { v in update(s) { $0.marginBefore = v } }
                            InlineIntCell(value: s.marginAfter, range: 0...4, width: 40) { v in update(s) { $0.marginAfter = v } }
                        } else if let t = r.text {
                            InlineIntCell(value: t.marginBefore, range: 0...4, width: 40) { v in update(t) { $0.marginBefore = v } }
                            InlineIntCell(value: t.marginAfter, range: 0...4, width: 40) { v in update(t) { $0.marginAfter = v } }
                        }
                    }
                }.width(92)
                TableColumn("表示の仕方") { r in
                    if let s = r.line {
                        Picker("", selection: Binding(get: { s.wordMode }, set: { v in update(s) { $0.wordMode = v } })) {
                            ForEach([1, 2, 3, 0], id: \.self) { m in Text(LineStyle.wordModeLabels[m] ?? "").tag(m) }
                        }
                        .labelsHidden()
                    } else {
                        Text("固定（削除できません）").font(.caption).foregroundStyle(.secondary)
                    }
                }.width(min: 220, ideal: 240)
                TableColumn("") { r in
                    if let s = r.line {
                        Button(role: .destructive) { confirmDelete = s } label: { Image(systemName: "trash") }.help("削除").buttonStyle(.borderless)
                    }
                }.width(36)
            }
            Divider()
            HStack {
                Button("既定に戻す…") { confirmReset = true }
                Button("サイズを一括設定…") { bulkSize = model.styles.first?.fontSize ?? 12; showBulkSize = true }
                    .popover(isPresented: $showBulkSize) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("すべてのスタイルのフォントサイズ").font(.headline)
                            Stepper("サイズ: \(bulkSize)", value: $bulkSize, in: 6...48)
                            Text("スタイルごとの差をなくして同じ大きさにします。編集画面の文字の大きさは 設定 › 書式 の「基準サイズ」でも変えられます。")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Spacer()
                                Button("キャンセル") { showBulkSize = false }
                                Button("\(model.styles.count + model.textStyles.count) 件に適用") { model.setAllStyleFontSizes(bulkSize); showBulkSize = false }
                                    .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding()
                        .frame(width: 320)
                    }
                Spacer()
                Text("表の中でそのまま直せます。台本画面の種別メニューには「順」の順に出ます。🔒 は固定スタイル。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.addStyle(LineStyle(name: "新しいスタイル", fontSize: model.styles.first?.fontSize ?? 14, color: "#000000", indent: 0, abbreviation: "", wordMode: 1))
                } label: { Label("USER STYLE 追加", systemImage: "plus") }
            }
            .padding(10)
        }
        .confirmationDialog("スタイルを既定の \(ScenarioStore.defaultStyles.count) 種に戻しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("既定に戻す", role: .destructive) { model.resetStyles() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("自分で追加・変更したスタイルは消えます。固定スタイル（シノプシス・場面説明・登場人物）も既定に戻ります。台詞の種別番号は変わりません。") }
        .confirmationDialog("スタイル「\(confirmDelete?.name ?? "")」を削除しますか？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("削除する", role: .destructive) { if let s = confirmDelete { model.deleteStyle(s) }; confirmDelete = nil }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        } message: { Text("この種別を使っている台詞は「種別 \(confirmDelete?.styleId ?? 0)」として残り、既定の見え方になります。") }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("作品ファイル") {
                Text("作品は 1 つずつ「タイトル.scwd」というファイルです。Web 版 ScenarioWriterCafe の swdata.sqlite と同じ形式（1 作品だけ入った SQLite）。編集はアプリ内の作業用コピーで行い、保存（⌘S）で本ファイルへ書き戻します。バックアップはファイルをコピーするだけです。")
                    .font(.caption).foregroundStyle(.secondary)
                if let u = model.currentWorkURL {
                    LabeledContent("開いている作品") { Text(u.path).font(.caption.monospaced()).textSelection(.enabled) }
                    Button("Finder で表示") { model.revealCurrent() }
                }
                HStack {
                    Button("最近使った作品の一覧を消す") { model.clearRecents() }.disabled(model.recents.isEmpty)
                    Text("ファイルは消えません。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Web 版との行き来") {
                HStack {
                    Button("Web 版・バックアップから取り込む…") { model.importDatabase() }
                    Text("Web 版の sw_config フォルダごと選び、次に分割先のフォルダを選びます。中の作品が 1 作品 1 ファイルになります。作品をまだ開いたことがなければスタイル設定も引き継ぎます。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("この作品を Web 版用に書き出す…") { model.exportForWeb() }.disabled(model.scenario == nil)
                    Text("開いている作品を swdata.sqlite として保存します。Web 版の sw_config/ に置くとそのまま開けます。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if model.hasLegacyDatabase {
                    HStack {
                        Button("以前のデータを作品ファイルに分けて保存…") { model.migrateLegacy() }
                        Text("1.0.0 の全作品入りデータベースが残っています。").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Web 版で MySQL を使っている場合は、Web 版の初期設定で SQLite を選んだ環境に一度移してから取り込んでください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("共通設定の場所") {
                Text(AppModel.settingsURL.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("スタイルと書式設定はここに入り、開いた作品ファイルにも写されます。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
