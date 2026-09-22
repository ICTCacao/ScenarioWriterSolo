import SwiftUI
import AppKit

/// 台詞 1 行分のテキスト欄。高さは内容に合わせて伸び、カーソル色・フォーカス時の背景を自分で決められる
/// （SwiftUI の TextEditor だと挿入カーソルの色や、行全体ではなく欄だけを強調する見た目が作れないため）。
struct LineTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    /// 行間（倍率）と文字間隔（pt）
    var lineHeightMultiple: CGFloat = 1.0
    var kern: CGFloat = 0
    /// 縦書きで編集（右から左へ行が並び、各行の中は上から下）
    var vertical: Bool = false
    /// 横書きの欄の幅（本文の文字数ぶん）。指定があれば提案の幅に関係なくこの幅で答える。
    /// 提案に合わせて幅を変えると、HStack / List が 462 と 328.5 のような 2 つの幅で交互に測り、
    /// 幅ごとに高さが違うため枠が往復して固まる（2026-09-22 に本人環境で発生）
    var fixedWidth: CGFloat? = nil
    /// true を渡すとフォーカスを取りに行く。取ったら onFocusRequestHandled で知らせる
    var requestFocus: Bool
    var onFocusChange: (Bool) -> Void
    var onFocusRequestHandled: () -> Void
    /// ⌘⏎（shift 付きなら true）
    var onCommandReturn: (Bool) -> Void
    /// Tab / ⇧Tab: 次(+1)・前(-1)の行へ
    var onNavigate: (Int) -> Void
    /// 縦書き: 本文に合わせて決めた欄の幅を知らせる（列配置の見積もりを実測で置き換える）。
    /// 作った直後の空文字の幅など、本文と一致しない一時的な値は知らせない
    var onMeasuredWidth: ((CGFloat, CGFloat) -> Void)? = nil   // (幅, 測ったときの高さ)

    func makeNSView(context: Context) -> AutoHeightTextView {
        LineTextView.log("make vertical=\(vertical) chars=\(text.count)")
        let v = AutoHeightTextView()
        v.delegate = context.coordinator
        v.isVerticalLayout = vertical
        v.isRichText = false
        v.allowsUndo = true
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.isContinuousSpellCheckingEnabled = false
        v.drawsBackground = false
        v.focusRingType = .none
        v.textContainerInset = NSSize(width: 4, height: 4)
        v.textContainer?.lineFragmentPadding = 2
        if vertical {
            // 縦書き: 高さ（行の長さ）は親が決め、幅（行数ぶん）は内容に合わせて伸びる
            v.setLayoutOrientation(.vertical)
            // 向きを変えると minSize/maxSize が元のフレームの値のまま残り、列より広い幅で描かれて隣と重なる。制限をなくす
            v.minSize = .zero
            v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            v.isVerticallyResizable = false
            v.isHorizontallyResizable = false
            v.autoresizingMask = []
            v.textContainer?.widthTracksTextView = true
            v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            v.setContentHuggingPriority(.required, for: .horizontal)
        } else {
            v.minSize = .zero
            v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            v.isVerticallyResizable = true
            v.isHorizontallyResizable = false
            v.autoresizingMask = [.width]
            v.textContainer?.widthTracksTextView = true
            v.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            v.setContentHuggingPriority(.required, for: .vertical)
        }
        v.onFocusChange = { [weak c = context.coordinator] f in c?.parent.onFocusChange(f) }
        v.onCommandReturn = { [weak c = context.coordinator] shift in c?.parent.onCommandReturn(shift) }
        v.onNavigate = { [weak c = context.coordinator] o in c?.parent.onNavigate(o) }
        v.string = text
        apply(to: v)
        return v
    }

    func updateNSView(_ v: AutoHeightTextView, context: Context) {
        context.coordinator.parent = self
        // 日本語入力の変換中（未確定文字がある間）は文字列も入力属性も触らない。
        // 触ると AppKit が未確定範囲を直そうとして例外を出し、落ちる（2026-09-22 のクラッシュ）
        let composing = v.hasMarkedText()
        if !composing {
            if v.string != text { v.string = text; v.invalidateIntrinsicContentSize() }
            apply(to: v)
        }
        if requestFocus, let w = v.window, w.firstResponder !== v {
            w.makeFirstResponder(v)
            v.setSelectedRange(NSRange(location: (v.string as NSString).length, length: 0))
            DispatchQueue.main.async { onFocusRequestHandled() }
        }
    }

    private func apply(to v: AutoHeightTextView) {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = max(lineHeightMultiple, 0.5)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: kern]
        let signature = "\(font.fontName)/\(font.pointSize)/\(lineHeightMultiple)/\(kern)/\(color.hexString)"
        // フォントなどが変わったときだけ適用する（毎回 typingAttributes を触ると入力中の状態を乱す）
        if v.appliedSignature != signature, let storage = v.textStorage {
            v.appliedSignature = signature
            v.insertionPointColor = .controlAccentColor
            v.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.35)]
            v.font = font
            v.textColor = color
            v.typingAttributes = attrs
            storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
            v.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: AutoHeightTextView, context: Context) -> CGSize? {
        if vertical {
            // 高さ（行の長さ）が決まっていない提案（nil / 無限）で測ると 1 行に収まる幅を返してしまい、
            // 実際の高さで折り返した本文が列からはみ出す。決まった高さだけを使い、無ければ前回の高さ
            var height = proposal.height ?? 0
            if !height.isFinite || height <= 0 { height = context.coordinator.lastHeight }
            guard height > 0 else { return nil }
            context.coordinator.lastHeight = height
            let size = CGSize(width: v.width(forHeight: height), height: height)
            LineTextView.log("v sizeThatFits proposal=\(proposal.width.map { "\($0)" } ?? "nil")x\(proposal.height.map { "\($0)" } ?? "nil") -> \(size) bounds=\(v.bounds.size) chars=\(v.string.count)")
            if let cb = onMeasuredWidth, v.string == text, v.appliedSignature != "" {
                let w = size.width, h = height
                DispatchQueue.main.async { cb(w, h) }   // レイアウト中に @State を触らない
            }
            return size
        }
        var width = fixedWidth ?? (proposal.width ?? 0)
        if !width.isFinite || width <= 0 { width = v.bounds.width }
        guard width > 0 else { return nil }
        let h = v.height(forWidth: width)
        LineTextView.log("h sizeThatFits proposal=\(proposal.width.map { "\($0)" } ?? "nil")x\(proposal.height.map { "\($0)" } ?? "nil") -> \(width)x\(h) bounds=\(v.bounds.size) chars=\(v.string.count)")
        return CGSize(width: width, height: h)
    }

    /// 起動引数 -logLayout <ファイル> で寸法計算を記録（動作確認用）
    static let logPath: String? = UserDefaults.standard.string(forKey: "logLayout")
    static func log(_ s: String) {
        guard let p = logPath, !p.isEmpty, let h = FileHandle(forWritingAtPath: p) ?? { FileManager.default.createFile(atPath: p, contents: nil); return FileHandle(forWritingAtPath: p) }() else { return }
        h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); h.closeFile()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineTextView
        let textUndo = UndoManager()
        var lastHeight: CGFloat = 0
        init(_ p: LineTextView) { parent = p }
        /// 欄の中の文字入力は欄ごとの履歴にする（行の削除・並び替えなどはウインドウの履歴）
        func undoManager(for view: NSTextView) -> UndoManager? { textUndo }
        func textDidChange(_ n: Notification) {
            guard let v = n.object as? AutoHeightTextView else { return }
            parent.text = v.string
            v.invalidateIntrinsicContentSize()
        }
    }
}

final class AutoHeightTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onCommandReturn: ((Bool) -> Void)?
    var onNavigate: ((Int) -> Void)?
    var isVerticalLayout = false
    /// 最後に適用したフォント・行間などの組（変わったときだけ本文全体に適用し直す）
    var appliedSignature = ""

    /// 計測は表示用のレイアウトを触らず、計測専用の NSLayoutManager で行う。
    /// 表示中の textContainer の大きさを書き換えると、レイアウト中にビュー自身がリサイズされて
    /// SwiftUI の再レイアウト要求が起き、AppKit が例外を投げる（縦書きで落ちた原因）
    private func measuredUsedRect(containerSize: NSSize) -> NSRect {
        // ビューを持たない TextKit 2 のスタックで測る。計測に NSTextView を使うと、文字列の差し替えのたびに
        // 選択範囲の修正 → 入力コンテキストの有効化が走り、入力中の日本語 IME セッションを止めに行って
        // SwiftUI の更新と衝突して落ちる（2026-09-22 のクラッシュ。縦書き・横書きとも同じ経路）。
        // 縦書きも横組みで測る: 日本語の字送りは縦横とも 1 文字 1em、行送りも同じなので行数が一致する
        let m = Self.measurer
        let src = attributedString()
        m.content.performEditingTransaction {
            if src.length == 0 {
                m.content.textStorage?.setAttributedString(NSAttributedString(string: " ", attributes: [.font: font ?? NSFont.systemFont(ofSize: 14)]))
            } else {
                m.content.textStorage?.setAttributedString(src)
            }
        }
        m.container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 2
        m.container.size = containerSize
        m.layout.ensureLayout(for: m.layout.documentRange)
        return m.layout.usageBoundsForTextContainer
    }

    private struct Measurer {
        let content: NSTextContentStorage
        let layout: NSTextLayoutManager
        let container: NSTextContainer
    }

    private static let measurer: Measurer = {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 2
        content.addTextLayoutManager(layout)
        layout.textContainer = container
        return Measurer(content: content, layout: layout, container: container)
    }()

    /// 縦書きの本文欄の幅を、ビューを作らずに見積もる（自前で仮想化した列配置で、まだ作っていない列の幅に使う）。
    /// 表示中のビューの width(forHeight:) と同じ計算（inset 4pt・lineFragmentPadding 2pt・+1pt の余裕）
    static func verticalWidth(text: String, font: NSFont, lineHeightMultiple: CGFloat, kern: CGFloat, height: CGFloat) -> CGFloat {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = max(lineHeightMultiple, 0.5)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: ps, .kern: kern]
        let src = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attrs)
        let m = measurer
        m.content.performEditingTransaction { m.content.textStorage?.setAttributedString(src) }
        m.container.lineFragmentPadding = 2
        m.container.size = NSSize(width: max(height - 8, 10), height: CGFloat.greatestFiniteMagnitude)
        m.layout.ensureLayout(for: m.layout.documentRange)
        return max(ceil(m.layout.usageBoundsForTextContainer.height) + 8 + 1, 24)
    }

    /// 縦書き: 行の長さ（高さ）を与えて、必要な幅（行数ぶん）を返す。
    /// 縦書きでは textContainer の「幅」が行の長さ、usedRect の「高さ」が行の並ぶ方向の長さになる
    func width(forHeight height: CGFloat) -> CGFloat {
        let used = measuredUsedRect(containerSize: NSSize(width: max(height - textContainerInset.height * 2, 10), height: CGFloat.greatestFiniteMagnitude))
        return max(ceil(used.height) + textContainerInset.width * 2 + 1, 24)
    }

    /// 横書き: 幅を与えて必要な高さを返す。**整数に切り上げる**。フォントの行の高さは端数（例 30.4pt）になり、
    /// そのまま返すと SwiftUI がピクセルに揃えた枠（30.5）と食い違い、setFrameSize → 再計測 → また 30.4 … と
    /// 無限に往復して固まる（2026-09-22 に本人環境で発生。Web 版から取り込んだ作品を開くと固まった）
    func height(forWidth width: CGFloat) -> CGFloat {
        let used = measuredUsedRect(containerSize: NSSize(width: max(width - textContainerInset.width * 2, 10), height: CGFloat.greatestFiniteMagnitude))
        return max(ceil(used.height + textContainerInset.height * 2), 24)
    }

    override var intrinsicContentSize: NSSize {
        if isVerticalLayout { return NSSize(width: width(forHeight: bounds.height), height: NSView.noIntrinsicMetric) }
        return NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            LineTextView.log("setFrameSize \(newSize) vertical=\(isVerticalLayout) chars=\(string.count)")
            if !isVerticalLayout {
                // 横書き: 高さが本文に合っているなら再計測を頼まない（頼むと SwiftUI との往復が止まらないことがある）
                if abs(height(forWidth: newSize.width) - newSize.height) < 1 { return }
            }
            invalidateIntrinsicContentSize()
            if isVerticalLayout {
                // 列の幅が本文の幅と違うなら（高さが後から決まったときなど）、次のランループで再計測を頼む
                let need = width(forHeight: newSize.height)
                if abs(need - newSize.width) > 1 {
                    LineTextView.log("v setFrameSize \(newSize) need=\(need) -> relayout")
                    DispatchQueue.main.async { [weak self] in self?.invalidateIntrinsicContentSize() }
                }
            }
        }
    }

    // SwiftUI の更新中に @State を触らないよう、次のランループで知らせる
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in self?.onFocusChange?(true) } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in self?.onFocusChange?(false) } }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        // 日本語入力の変換中は IME に任せる（変換中に行の追加・移動をすると未確定文字の扱いが崩れる）
        if hasMarkedText() { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {                       // esc: 編集を終える
            window?.makeFirstResponder(nil)
            return
        }
        if (event.keyCode == 36 || event.keyCode == 76), flags.contains(.command) {   // ⌘⏎ / ⌘⇧⏎
            onCommandReturn?(flags.contains(.shift))
            return
        }
        if event.keyCode == 48 {                       // Tab: 次の行、⇧Tab: 前の行（⌘Tab は macOS のアプリ切替なので使えない）
            onNavigate?(flags.contains(.shift) ? -1 : 1)
            return
        }
        if isVerticalLayout, flags == [.command], event.keyCode == 123 || event.keyCode == 124 {   // 縦書き: ⌘← 次の行、⌘→ 前の行
            onNavigate?(event.keyCode == 123 ? 1 : -1)
            return
        }
        super.keyDown(with: event)
    }
}


/// 場面・登場人物・シノプシスの縦書き欄。LineTextView をフォント設定付きで使う簡易版
struct VerticalField: View {
    @Binding var text: String
    var placeholder: String = ""
    var height: CGFloat
    var color: NSColor = .labelColor
    var sizeDelta: CGFloat = 0
    /// スタイルのサイズ（12 が基準サイズ）。指定があれば sizeDelta より優先
    var styleSize: Int? = nil
    /// 既定の幅（本文がこれより多いときは列が増えて広がる）
    var minWidth: CGFloat = 40
    var onEditingEnd: (() -> Void)? = nil
    @AppStorage(EditorFont.familyKey) private var fontFamily = ""
    @AppStorage(EditorFont.sizeKey) private var fontBase = 14.0
    @AppStorage(EditorFont.lineHeightKey) private var lineHeight = 1.0
    @AppStorage(EditorFont.kernKey) private var kern = 0.0
    @State private var focused = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(.tertiary).font(.caption).padding(6).allowsHitTesting(false)
            }
            LineTextView(text: $text,
                         font: EditorFont.font(family: fontFamily, size: styleSize.map { EditorFont.pointSize(base: fontBase, styleSize: $0) } ?? (CGFloat(fontBase) + sizeDelta)),
                         color: color,
                         lineHeightMultiple: CGFloat(lineHeight),
                         kern: CGFloat(kern),
                         vertical: true,
                         requestFocus: false,
                         onFocusChange: { f in focused = f; if !f { onEditingEnd?() } },
                         onFocusRequestHandled: {},
                         onCommandReturn: { _ in },
                         onNavigate: { _ in })
                .id("v")
        }
        .frame(height: height)
        .frame(minWidth: minWidth, alignment: .trailing)
        .background(RoundedRectangle(cornerRadius: 6).fill(focused ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Color.secondary.opacity(0.7) : Color.secondary.opacity(0.25), lineWidth: 1))
    }
}


/// シノプシスなど長い本文の縦書き編集。NSScrollView の中に縦組みの NSTextView を置き、横にスクロールする。
/// 折り返す長さ（列の高さ）は枠の高さから自分で決め、幅（列数）は本文の量から決める。
/// NSTextView の自動追従（widthTracksTextView など）は縦組みでは枠の大きさの変化に追従しないことがあり、
/// 枠を小さくしても列が枠の下にはみ出したままになる（2026-09-22 に報告）
struct VerticalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor = .labelColor
    var lineHeightMultiple: CGFloat = 1.0
    var kern: CGFloat = 0
    /// 1 列に入れる文字数（「読む」と同じ本文の文字数）。nil なら枠の高さいっぱい
    var bodyChars: Int? = nil

    static let inset: CGFloat = 12

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasHorizontalScroller = true
        sv.hasVerticalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        let doc = FlippedContainerView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        tv.drawsBackground = false
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.focusRingType = .none
        tv.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        tv.textContainer?.lineFragmentPadding = 2
        tv.setLayoutOrientation(.vertical)
        // 大きさは全部こちらで決める
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = []
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        doc.addSubview(tv)
        sv.documentView = doc
        sv.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.clipFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: sv.contentView)
        tv.string = text
        apply(to: tv, force: true)
        context.coordinator.scrollView = sv
        context.coordinator.textView = tv
        context.coordinator.docView = doc
        DispatchQueue.main.async {
            context.coordinator.relayout(keepRightEdge: false)
            context.coordinator.scrollToStart()
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        context.coordinator.parent = self
        if !tv.hasMarkedText() {
            var changed = false
            if tv.string != text { tv.string = text; changed = true }
            if apply(to: tv, force: false) { changed = true }
            if context.coordinator.lastBodyChars != bodyChars { context.coordinator.lastBodyChars = bodyChars; changed = true }
            if changed {
                DispatchQueue.main.async {
                    context.coordinator.relayout(keepRightEdge: false)
                    context.coordinator.scrollToStart()
                }
            }
        }
    }

    /// フォントなどを適用する。変えたときだけ true
    @discardableResult
    private func apply(to tv: NSTextView, force: Bool) -> Bool {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = max(lineHeightMultiple, 0.5)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: kern]
        let signature = "\(font.fontName)/\(font.pointSize)/\(lineHeightMultiple)/\(kern)/\(color.hexString)"
        guard force || tv.identifier?.rawValue != signature, let storage = tv.textStorage else { return false }
        tv.identifier = NSUserInterfaceItemIdentifier(signature)
        tv.insertionPointColor = .controlAccentColor
        tv.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.35)]
        tv.font = font
        tv.textColor = color
        tv.typingAttributes = attrs
        storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        return true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class FlippedContainerView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VerticalTextEditor
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var docView: NSView?
        private var lastClipSize: NSSize = .zero
        var lastBodyChars: Int?
        init(_ p: VerticalTextEditor) { parent = p; lastBodyChars = p.bodyChars }
        deinit { NotificationCenter.default.removeObserver(self) }

        func textDidChange(_ n: Notification) {
            guard let v = n.object as? NSTextView else { return }
            parent.text = v.string
            relayout(keepRightEdge: true)
        }

        @objc func clipFrameChanged(_ n: Notification) {
            guard let sv = scrollView, sv.contentView.bounds.size != lastClipSize else { return }
            relayout(keepRightEdge: true)
        }

        /// 枠の高さから折り返す長さを決め、本文の量から幅（列数）を決めて、文書ビューと本文欄の大きさを合わせる。
        /// 本文が枠より狭いときは右寄せ（縦書きは右から始まる）
        func relayout(keepRightEdge: Bool) {
            guard let sv = scrollView, let tv = textView, let doc = docView, let container = tv.textContainer else { return }
            let clip = sv.contentView.bounds.size
            guard clip.height > 0 else { return }
            lastClipSize = clip
            let inset = VerticalTextEditor.inset
            let visible = sv.contentView.bounds
            let fromRight = doc.frame.width - visible.maxX
            // 縦組みでは textContainer の「幅」が行の長さ（見た目の高さ）。本文の文字数が決まっていればそこで折り返す
            var lineLength = max(clip.height - inset * 2, 10)
            if let n = parent.bodyChars {
                lineLength = min(lineLength, CGFloat(n) * (parent.font.pointSize + max(parent.kern, 0)) + 6)
            }
            container.size = NSSize(width: lineLength, height: CGFloat.greatestFiniteMagnitude)
            var used: NSRect = .zero
            if let lm = tv.layoutManager {
                lm.ensureLayout(for: container)
                used = lm.usedRect(for: container)
            } else if let tlm = tv.textLayoutManager {
                tlm.ensureLayout(for: tlm.documentRange)
                used = tlm.usageBoundsForTextContainer
            }
            // 縦組みの usedRect: 高さが列の並ぶ方向（見た目の幅）
            let contentW = max(ceil(used.height) + inset * 2 + 1, 40)
            let docW = max(contentW, clip.width)
            doc.frame = NSRect(x: 0, y: 0, width: docW, height: clip.height)
            tv.frame = NSRect(x: docW - contentW, y: 0, width: contentW, height: min(lineLength + inset * 2, clip.height))
            if keepRightEdge, fromRight.isFinite, fromRight >= 0 {
                let x = max(0, min(docW - clip.width, docW - fromRight - clip.width))
                sv.contentView.scroll(to: NSPoint(x: x, y: 0))
                sv.reflectScrolledClipView(sv.contentView)
            }
        }

        func scrollToStart() {
            guard let sv = scrollView, let doc = docView else { return }
            let x = max(doc.frame.width - sv.contentView.bounds.width, 0)
            sv.contentView.scroll(to: NSPoint(x: x, y: 0))
            sv.reflectScrolledClipView(sv.contentView)
        }
    }
}
