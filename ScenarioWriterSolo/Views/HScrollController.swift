import SwiftUI
import AppKit

/// 横スクロールの位置の読み書き（縦書きの列配置用）。
///
/// macOS 15 以降は SwiftUI の ScrollPosition / onScrollGeometryChange を使う。macOS 14 にはそれが無いので、
/// ScrollView の中身の背景に ScrollProbe を置き、中の NSScrollView を直接見て・動かす。
/// どちらの場合も「見えている範囲」は中身の座標で、左の余白（サイドバーの下）を含む（左端で minX = −余白）。
/// macOS 15 以降でも `defaults write com.ictcacao.ScenarioWriterSolo legacyScroll -bool YES` で 14 の道を試せる。
@MainActor
final class HScrollController: ObservableObject {
    static let legacy: Bool = {
        if #available(macOS 15, *) { return UserDefaults.standard.bool(forKey: "legacyScroll") }
        return true
    }()

    /// macOS 15 以降: ScrollPosition.scrollTo(x:)（nil = 右端へ）。ModernHScroll が登録する
    fileprivate var modernScroll: ((CGFloat?) -> Void)?
    /// macOS 14: 中身の背景に置いた目印
    fileprivate weak var probe: ScrollProbeView?

    /// 見えている範囲の左端（visibleRect.minX）を x にする。offsetDelta は左の余白（scrollTo(x:) は余白の内側から数える）
    func scroll(visibleX x: CGFloat, offsetDelta: CGFloat, animation: Animation? = nil) {
        if let probe { probe.scroll(visibleX: x, animated: animation != nil); return }
        withAnimation(animation) { modernScroll?(x + offsetDelta) }
    }

    /// 先頭（右端）へ
    func scrollToTrailing() {
        if let probe { probe.scroll(visibleX: nil, animated: false); return }
        modernScroll?(nil)
    }
}

extension View {
    /// ScrollView に付ける。左の余白と見えている範囲が変わるたびに知らせる
    func hScrollTracking(_ controller: HScrollController, insets: @escaping (CGFloat) -> Void,
                         visible: @escaping (CGRect) -> Void) -> some View {
        modifier(HScrollTracking(controller: controller, insets: insets, visible: visible))
    }

    /// ScrollView の中身に付ける（macOS 14 の道でだけ働く）
    func hScrollProbe(_ controller: HScrollController, insets: @escaping (CGFloat) -> Void,
                      visible: @escaping (CGRect) -> Void) -> some View {
        background {
            if HScrollController.legacy {
                ScrollProbe(controller: controller, insets: insets, visible: visible)
            }
        }
    }
}

private struct HScrollTracking: ViewModifier {
    let controller: HScrollController
    let insets: (CGFloat) -> Void
    let visible: (CGRect) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *), !HScrollController.legacy {
            content.modifier(ModernHScroll(controller: controller, insets: insets, visible: visible))
        } else {
            content
        }
    }
}

@available(macOS 15, *)
private struct ModernHScroll: ViewModifier {
    let controller: HScrollController
    let insets: (CGFloat) -> Void
    let visible: (CGRect) -> Void
    @State private var pos = ScrollPosition(edge: .trailing)

    func body(content: Content) -> some View {
        content
            .scrollPosition($pos)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.leading } action: { _, d in insets(d) }
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, r in visible(r) }
            .onAppear {
                let p = $pos
                controller.modernScroll = { x in
                    if let x { p.wrappedValue.scrollTo(x: x) } else { p.wrappedValue.scrollTo(edge: .trailing) }
                }
            }
    }
}

// MARK: - macOS 14

private struct ScrollProbe: NSViewRepresentable {
    let controller: HScrollController
    let insets: (CGFloat) -> Void
    let visible: (CGRect) -> Void

    func makeNSView(context: Context) -> ScrollProbeView { ScrollProbeView() }

    func updateNSView(_ v: ScrollProbeView, context: Context) {
        v.insets = insets; v.visible = visible
        controller.probe = v
    }
}

/// ScrollView の中身と同じ大きさの透明なビュー。自分を包む NSScrollView のスクロールを見張る。
///
/// 内容の幅が変わったときに右端からの距離を保つのもここでする（macOS 15 以降は VerticalColumnsView の
/// onChange(of: totalW) がする）。SwiftUI の onChange の時点では文書ビューの幅がまだ古く、
/// そこで動かすと左端へ飛ぶので、文書ビューの幅が実際に変わったときに動かす
final class ScrollProbeView: NSView {
    var insets: ((CGFloat) -> Void)?
    var visible: ((CGRect) -> Void)?
    private weak var clip: NSClipView?
    /// 文書ビューの幅（最後に見たとき）と、そのときの右端からの距離
    private var docW: CGFloat = 0
    private var fromRight: CGFloat = 0

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    override func layout() {
        super.layout()
        attach()
        report()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func attach() {
        guard let sv = enclosingScrollView, clip !== sv.contentView else { return }
        NotificationCenter.default.removeObserver(self)
        let c = sv.contentView
        c.postsBoundsChangedNotifications = true
        c.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.boundsDidChangeNotification, object: c)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.frameDidChangeNotification, object: c)
        if let doc = sv.documentView {
            doc.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(docResized), name: NSView.frameDidChangeNotification, object: doc)
        }
        clip = c
        LineTextView.log("scroll: legacy probe attached insets=\(sv.contentInsets.left)")
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    @objc private func changed() {
        // 文書ビューの幅が変わる途中（クリップビューが範囲に収め直したときなど）の位置は覚えない
        if let clip, let doc = enclosingScrollView?.documentView, doc.frame.width == docW {
            fromRight = docW - clip.bounds.maxX
        }
        report()
    }

    @objc private func docResized() {
        guard let clip, let sv = enclosingScrollView, let doc = sv.documentView, doc.frame.width != docW else { return }
        let w = doc.frame.width
        let x = max(-sv.contentInsets.left, w - fromRight - clip.bounds.width)
        LineTextView.log("scroll: legacy docW \(docW) -> \(w) keepRight x \(clip.bounds.minX) -> \(x)")
        docW = w
        clip.setBoundsOrigin(NSPoint(x: x, y: clip.bounds.origin.y))
        sv.reflectScrolledClipView(clip)
    }

    /// 見えている範囲を中身（このビュー）の座標で。左の余白の部分も含む
    private func report() {
        guard let clip, let sv = enclosingScrollView else { return }
        let r = convert(clip.bounds, from: clip)
        let inset = sv.contentInsets.left
        // SwiftUI の状態を変えるので、AppKit の描画・配置の途中を避ける
        DispatchQueue.main.async { [weak self] in
            self?.insets?(inset)
            self?.visible?(r)
        }
    }

    /// x は中身の座標（nil = 右端）。右への上限は呼ぶ側で収めてある（内容の幅が変わった直後は、
    /// 文書ビューの幅がまだ古いことがあるので、ここでは右端へ行くときだけ文書の幅で収める）
    func scroll(visibleX x: CGFloat?, animated: Bool) {
        guard let clip, let sv = enclosingScrollView, let doc = sv.documentView else { return }
        let inset = sv.contentInsets.left
        let target = x.map { clip.convert(NSPoint(x: $0, y: 0), from: self).x } ?? (doc.frame.width - clip.bounds.width)
        let origin = NSPoint(x: max(-inset, target), y: clip.bounds.origin.y)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                clip.animator().setBoundsOrigin(origin)
            } completionHandler: {
                sv.reflectScrolledClipView(clip)
            }
        } else {
            clip.setBoundsOrigin(origin)
            sv.reflectScrolledClipView(clip)
        }
    }
}
