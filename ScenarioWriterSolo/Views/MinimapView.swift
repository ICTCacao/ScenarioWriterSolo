import SwiftUI

/// ツールバーのミニマップの中身。縦書きの台本（VerticalColumnsView）と「読む」（WebView）が書き込み、
/// MinimapView だけが見る。位置はどれも「先頭から」の割合（0〜1）。縦書きは右が先頭なので右から左へ描く。
///
/// スクロールのたびに visible が変わるので、AppModel には入れない（台本の画面ごと描き直しになる）。
/// 書き込む側は shared を直接触り、@ObservedObject にしない
final class MinimapModel: ObservableObject {
    static let shared = MinimapModel()

    struct Mark: Equatable {
        /// 先頭からの位置と長さ（割合）
        var pos: CGFloat
        var len: CGFloat
        /// 行の中身の詰まり具合（0〜1）。縦書きなら列の高さのうち本文が占める割合
        var fill: CGFloat
        /// nil = ふつうの文字色
        var color: Color?
        /// 柱（場面の見出し）
        var heading = false
    }

    /// ミニマップを出すか（縦書きの台本、または「読む」）
    @Published var active = false
    @Published var rightToLeft = true
    @Published var marks: [Mark] = []
    /// 見えている範囲（先頭からの割合）
    @Published var visible: ClosedRange<CGFloat> = 0...1
    /// 先頭からの割合 f が画面の中央に来るようにスクロールする
    var jump: ((CGFloat) -> Void)?
    /// いま書き込んでいる画面（別の画面が消えるときに消さないように）
    private(set) var owner: String?

    func attach(_ owner: String, rightToLeft: Bool, jump: @escaping (CGFloat) -> Void) {
        self.owner = owner
        self.jump = jump
        if self.rightToLeft != rightToLeft { self.rightToLeft = rightToLeft }
        if !active { active = true }
    }

    func detach(_ owner: String) {
        guard self.owner == owner else { return }
        self.owner = nil
        jump = nil
        active = false
        marks = []
    }

    func setMarks(_ m: [Mark]) { if m != marks { marks = m } }

    func setVisible(_ lo: CGFloat, _ hi: CGFloat) {
        let lo = min(max(lo, 0), 1), hi = min(max(hi, lo), 1)
        // 小さな揺れで描き直さない
        if abs(lo - visible.lowerBound) > 0.0005 || abs(hi - visible.upperBound) > 0.0005 { visible = lo...hi }
    }
}

/// ツールバーのミニマップ。全体を 1 本の帯にして、行を種別の色の細い棒で並べ、見えている範囲を枠で示す。
/// クリック・ドラッグでその位置へ飛ぶ
struct MinimapView: View {
    @ObservedObject var map = MinimapModel.shared
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 260, height: 26)

    var body: some View {
        if map.active {
            strip
                .help("全体のどこを見ているか（\(map.rightToLeft ? "右端" : "左端")が先頭）。クリック・ドラッグでその位置へ")
        }
    }

    private var strip: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let inset: CGFloat = 3
            let bodyH = h - inset * 2
            // 先頭からの割合 → x
            func x(_ pos: CGFloat, _ len: CGFloat) -> CGFloat { map.rightToLeft ? (1 - pos - len) * w : pos * w }

            // 本文（ふつうの文字色）は灰色、色の付いた種別（ト書・歌詞など）は薄めの色で。濃いと帯が重たく見える
            func shading(_ c: Color?) -> GraphicsContext.Shading { c.map { .color($0.opacity(0.55)) } ?? .color(.primary.opacity(0.28)) }
            // 縦書きは上から下へ、横書きは左から右へ書くが、帯の中ではどちらも上から伸ばす
            func barH(_ fill: CGFloat) -> CGFloat { max(2, bodyH * min(max(fill, 0), 1)) }

            // 幅が 2pt 未満の行（「読む」の作品全体など、行がとても多いとき）は 1pt ごとにまとめて 1 本だけ描く。
            // 重ねて描くと半透明が積もって帯が黒く潰れる。色の付いた行を優先し、高さはいちばん長い行に
            let cols = max(Int(w.rounded(.up)), 1)
            var colFill = [CGFloat](repeating: -1, count: cols)
            var colColor = [Color?](repeating: nil, count: cols)
            var headCols = Set<Int>()
            for m in map.marks {
                let mx = x(m.pos, m.len), mw = m.len * w
                if m.heading {
                    headCols.insert(min(max(Int((mx + mw / 2).rounded(.down)), 0), cols - 1))
                    continue
                }
                if mw >= 2 {
                    ctx.fill(Path(CGRect(x: mx, y: inset, width: mw - 0.5, height: barH(m.fill))), with: shading(m.color))
                    continue
                }
                let c = min(max(Int((mx + mw / 2).rounded(.down)), 0), cols - 1)
                if colFill[c] < 0 || (colColor[c] == nil && m.color != nil) { colColor[c] = m.color }
                colFill[c] = max(colFill[c], m.fill)
            }
            for c in 0..<cols where colFill[c] >= 0 {
                ctx.fill(Path(CGRect(x: CGFloat(c), y: inset, width: 1, height: barH(colFill[c]))), with: shading(colColor[c]))
            }
            // 柱（場面の区切り）は上下いっぱいの細い線
            for c in headCols {
                ctx.fill(Path(CGRect(x: CGFloat(c), y: 1, width: 1, height: h - 2)), with: .color(.primary.opacity(0.5)))
            }

            // 見えている範囲
            let v = map.visible
            let vx = x(v.lowerBound, v.upperBound - v.lowerBound)
            let vw = max((v.upperBound - v.lowerBound) * w, 4)
            let frame = CGRect(x: min(vx, w - vw), y: 0.5, width: vw, height: h - 1)
            ctx.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(.accentColor.opacity(0.14)))
            ctx.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(.accentColor.opacity(0.9)), lineWidth: 1.2)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let f = min(max(g.location.x / Self.size.width, 0), 1)
            map.jump?(map.rightToLeft ? 1 - f : f)
        })
    }
}

extension Color {
    /// "rgb(r, g, b)" / "rgba(r, g, b, a)"（WebView の getComputedStyle）から
    /// plainAsNil: 黒に近い色（ふつうの文字色 #222 など）は nil（ミニマップでは灰色）
    init?(cssRGB s: String, plainAsNil: Bool = false) {
        let nums = s.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        guard nums.count >= 3 else { return nil }
        if plainAsNil && nums[0] < 60 && nums[1] < 60 && nums[2] < 60 { return nil }
        self.init(red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255)
    }
}
