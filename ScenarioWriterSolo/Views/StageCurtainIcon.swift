import AppKit
import SwiftUI

/// 「場面」のアイコン: 劇場の幕（上に波打つ飾り幕、左右に絞った幕）。SF Symbols に劇場の幕が無いので自前で描く。
/// テンプレート画像なので、サイドバーの選択色や外観（ライト / ダーク）に合わせて色が付く
enum StageCurtainIcon {
    /// 24×24 のグリッドで描く（y は上向き）
    static func path() -> NSBezierPath {
        let p = NSBezierPath()
        // 飾り幕（バランス）: 横長の帯、下端は 4 つの弧
        p.move(to: NSPoint(x: 1.5, y: 22.5)); p.line(to: NSPoint(x: 22.5, y: 22.5)); p.line(to: NSPoint(x: 22.5, y: 19.5))
        let n = 4, w = 21.0 / Double(n)
        for i in 0..<n {
            let x1 = 22.5 - Double(i) * w, x0 = x1 - w
            p.curve(to: NSPoint(x: x0, y: 19.5), controlPoint1: NSPoint(x: x1 - w * 0.2, y: 17.6), controlPoint2: NSPoint(x: x0 + w * 0.2, y: 17.6))
        }
        p.close()
        // 左の幕: 上は幅広、途中で絞られ、下で広がる
        p.move(to: NSPoint(x: 1.5, y: 19)); p.line(to: NSPoint(x: 7, y: 19))
        p.curve(to: NSPoint(x: 4.2, y: 10.5), controlPoint1: NSPoint(x: 6.7, y: 15), controlPoint2: NSPoint(x: 5.5, y: 12))
        p.curve(to: NSPoint(x: 5.2, y: 1.5), controlPoint1: NSPoint(x: 3.6, y: 7), controlPoint2: NSPoint(x: 5.2, y: 3.5))
        p.line(to: NSPoint(x: 1.5, y: 1.5)); p.close()
        // 右の幕（左右対称）
        p.move(to: NSPoint(x: 22.5, y: 19)); p.line(to: NSPoint(x: 17, y: 19))
        p.curve(to: NSPoint(x: 19.8, y: 10.5), controlPoint1: NSPoint(x: 17.3, y: 15), controlPoint2: NSPoint(x: 18.5, y: 12))
        p.curve(to: NSPoint(x: 18.8, y: 1.5), controlPoint1: NSPoint(x: 20.4, y: 7), controlPoint2: NSPoint(x: 18.8, y: 3.5))
        p.line(to: NSPoint(x: 22.5, y: 1.5)); p.close()
        return p
    }

    /// side pt 四方のテンプレート画像
    static func image(side: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let p = path()
            p.transform(using: AffineTransform(scale: rect.width / 24))
            // ほかのサイドバーのアイコン（SF Symbols の regular）と同じく線で描く
            p.lineWidth = 1.6 * rect.width / 24
            p.lineJoinStyle = .round
            p.lineCapStyle = .round
            NSColor.black.setStroke()
            p.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "場面"
        return img
    }

    /// サイドバー（SF Symbols の本文サイズとほぼ同じ見た目の大きさ）
    static let sidebar = image(side: 21)
    /// 「場面がありません」などの大きな表示
    static let large = image(side: 48)
}
