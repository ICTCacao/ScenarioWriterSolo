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
        .frame(width: 960, height: 560)
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
                Text("縦書きでは、行が右から左へ並び、各行の本文は上から下へ書きます。Tab / ⇧Tab のほか ⌘← / ⌘→ で前後の行へ移れます。「読む」画面の縦書き / 横書きはこれとは別に、読む画面のバーで切り替えます。")
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
                Text("台本画面の本文欄に使います。基準サイズはスタイルのサイズが 12 のときの大きさで、スタイルごとの差はそのまま反映されます。「読む」画面や書き出しには影響しません。")
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
    var orderText: String { line.map { "\($0.orderNo)" } ?? "—" }
    var name: String { line?.name ?? text?.kind.label ?? "" }
    var color: String { line?.color ?? text?.color ?? "#000000" }
    var styleIdText: String { line.map { "\($0.styleId)" } ?? "—" }
    var fontSize: Int { line?.fontSize ?? text?.fontSize ?? 12 }
    var indent: Int { line?.indent ?? text?.indent ?? 0 }
    var abbreviation: String { line?.abbreviation ?? "" }
    var marginBefore: Int { line?.marginBefore ?? text?.marginBefore ?? 0 }
    var marginAfter: Int { line?.marginAfter ?? text?.marginAfter ?? 0 }
    var modeText: String { line.map { LineStyle.wordModeLabels[$0.wordMode] ?? "" } ?? "固定（削除できません）" }
}

struct StylesSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: LineStyle?
    @State private var editingText: TextStyle?
    @State private var confirmReset = false
    @State private var confirmDelete: LineStyle?
    @State private var showBulkSize = false
    @State private var bulkSize = 12

    private var rows: [StyleRow] {
        model.styles.map { StyleRow(id: "L\($0.id)", line: $0) } + model.textStyles.map { StyleRow(id: "T\($0.kind.rawValue)", text: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows) {
                TableColumn("順") { s in Text(s.orderText).monospacedDigit().foregroundStyle(.secondary) }.width(48)
                TableColumn("スタイル名") { s in
                    HStack {
                        Circle().fill(Color(hex: s.color)).frame(width: 10, height: 10)
                        Text(s.name)
                        if s.isFixed { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }.width(min: 150, ideal: 170)
                TableColumn("番号") { s in Text(s.styleIdText).monospacedDigit().foregroundStyle(.secondary) }.width(40)
                TableColumn("サイズ") { s in Text("\(s.fontSize)") }.width(44)
                TableColumn("字下げ") { s in Text("\(s.indent)") }.width(44)
                TableColumn("省略文字") { s in Text(s.abbreviation) }.width(64)
                TableColumn("余白 前/後") { s in Text("\(s.marginBefore) / \(s.marginAfter)").monospacedDigit() }.width(70)
                TableColumn("表示の仕方") { s in Text(s.modeText).font(.caption) }.width(min: 220, ideal: 250)
                TableColumn("") { s in
                    HStack(spacing: 10) {
                        Button { if let l = s.line { editing = l } else { editingText = s.text } } label: { Image(systemName: "pencil") }.help("編集")
                        if let l = s.line {
                            Button(role: .destructive) { confirmDelete = l } label: { Image(systemName: "trash") }.help("削除")
                        }
                    }
                    .buttonStyle(.borderless)
                }.width(60)
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
                Text("行の「種別」ごとの見た目。台本画面の種別メニューにはこの並び順で出ます。🔒 は固定スタイル。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { editing = LineStyle(name: "新しいスタイル", fontSize: 12, color: "#000000", indent: 0, abbreviation: "", wordMode: 1) } label: { Label("USER STYLE 追加", systemImage: "plus") }
            }
            .padding(10)
        }
        .sheet(item: $editing) { s in StyleEditSheet(style: s) }
        .sheet(item: $editingText) { t in TextStyleEditSheet(style: t) }
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

struct StyleEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var style: LineStyle
    @State private var color: Color = .black
    @State private var showsName = true
    @State private var kagi = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("スタイル名", text: $style.name)
                Stepper("並び順: \(style.orderNo)", value: $style.orderNo, in: 0...100000, step: 100)
                Stepper("フォントサイズ: \(style.fontSize)", value: $style.fontSize, in: 6...48)
                ColorPicker("フォント色", selection: $color, supportsOpacity: false)
                Stepper("字下げ数: \(style.indent)", value: $style.indent, in: 0...20)
                TextField("省略文字（NA / M / SE …）", text: $style.abbreviation)
                Toggle("登場人物名を出す", isOn: $showsName)
                Toggle("台詞を「」で囲む", isOn: $kagi)
                Section("前後の余白（行数）") {
                    Stepper("前に空ける: \(style.marginBefore) 行", value: $style.marginBefore, in: 0...4)
                    Stepper("後に空ける: \(style.marginAfter) 行", value: $style.marginAfter, in: 0...4)
                    Text("「読む」画面（縦書きでは列の間隔）とテキスト・Word の出力に効きます。編集画面には出ません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("見え方") {
                    HStack(alignment: .top) {
                        Text(ScriptFormatter.labelFor(name: showsName ? "太郎" : "", style: preview))
                            .fontWeight(.semibold)
                            .frame(width: 120, alignment: .leading)
                        Color.clear.frame(width: CGFloat(style.indent) * 12, height: 1)
                        Text(kagi ? "「おはよう」" : "おはよう")
                            .foregroundStyle(color)
                            .font(.system(size: 14 + CGFloat(style.fontSize - 12) * 0.5))
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(style.id == 0 ? "追加" : "保存") {
                    style.color = NSColor(color).hexString
                    style.wordMode = LineStyle.wordMode(showsName: showsName, kagikakko: kagi)
                    if style.id == 0 { model.addStyle(style) } else { model.updateStyle(style) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(style.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 480)
        .onAppear {
            color = Color(hex: style.color)
            showsName = style.showsName
            kagi = style.usesKagikakko
        }
    }

    private var preview: ResolvedStyle {
        ResolvedStyle(name: style.name, fontSize: style.fontSize, color: style.color, indent: style.indent, abbreviation: style.abbreviation, showsName: showsName, kagikakko: kagi)
    }
}

/// 固定スタイル（シノプシス・場面説明・登場人物）の編集。名前と並び順は変えられず、削除もできない
struct TextStyleEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var style: TextStyle
    @State private var color: Color = .black

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("スタイル") { Text(style.kind.label).fontWeight(.semibold) }
                Stepper("フォントサイズ: \(style.fontSize)", value: $style.fontSize, in: 6...48)
                ColorPicker("フォント色", selection: $color, supportsOpacity: false)
                Stepper("字下げ数: \(style.indent)", value: $style.indent, in: 0...20)
                Section("前後の余白（行数）") {
                    Stepper("前に空ける: \(style.marginBefore) 行", value: $style.marginBefore, in: 0...4)
                    Stepper("後に空ける: \(style.marginAfter) 行", value: $style.marginAfter, in: 0...4)
                }
                Section("見え方") {
                    Text(sample)
                        .foregroundStyle(color)
                        .font(.system(size: 14 + CGFloat(style.fontSize - 12) * 0.5))
                        .padding(.leading, CGFloat(style.indent) * 12)
                    Text("フォントサイズと色は編集画面と「読む」画面に、字下げと余白は「読む」画面に効きます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    style.color = NSColor(color).hexString
                    model.updateTextStyle(style)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 400)
        .onAppear { color = Color(hex: style.color) }
    }

    private var sample: String {
        switch style.kind {
        case .synopsis: return "夕暮れの谷で、一匹の狼が問いかける。"
        case .sceneDescription: return "夜。古い教会の礼拝堂。"
        case .character: return "太郎　二十歳。少し内気な大学生。"
        }
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
