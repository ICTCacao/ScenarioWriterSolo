// アプリアイコンを描く。使い方: swift make-icon.swift <out.png>
// ブラウン（ICTCacao）の背景に、縦書きの原稿（クリーム色の紙）と朱の柱線。
import Foundation
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: a)
}
let cacaoTop = rgb(139, 82, 58)
let cacaoBottom = rgb(92, 50, 34)
let cream = rgb(246, 233, 220)
let ink = rgb(70, 45, 35)
let orange = rgb(247, 147, 30)      // Web 版のアクセント色
let green = rgb(0, 100, 0)          // ト書の色

// 背景（macOS の角丸）
let bgRect = NSRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 100, dy: 100)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 190, yRadius: 190)
NSGradient(starting: cacaoTop, ending: cacaoBottom)!.draw(in: bg, angle: -90)

// 影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
let paper = NSRect(x: 232, y: 190, width: 560, height: 660)
let paperPath = NSBezierPath(roundedRect: paper, xRadius: 28, yRadius: 28)
cream.setFill()
paperPath.fill()
ctx.restoreGState()

// 紙の縁
paperPath.lineWidth = 8
ink.withAlphaComponent(0.25).setStroke()
paperPath.stroke()

// 縦書きの行（右から左へ）。柱（場面名）は朱、ト書は緑、台詞は墨
struct Col { let color: NSColor; let top: CGFloat; let len: CGFloat; let width: CGFloat }
let cols: [Col] = [
    Col(color: orange, top: 60, len: 260, width: 34),
    Col(color: ink, top: 60, len: 520, width: 26),
    Col(color: ink, top: 130, len: 400, width: 26),
    Col(color: green, top: 60, len: 330, width: 26),
    Col(color: ink, top: 60, len: 560, width: 26),
    Col(color: ink, top: 130, len: 300, width: 26),
    Col(color: green, top: 60, len: 420, width: 26),
]
var x = paper.maxX - 70
for c in cols {
    let r = NSRect(x: x - c.width, y: paper.maxY - c.top - c.len, width: c.width, height: c.len)
    c.color.withAlphaComponent(c.color == orange ? 1 : 0.85).setFill()
    NSBezierPath(roundedRect: r, xRadius: c.width / 2, yRadius: c.width / 2).fill()
    x -= c.width + 44
}

// 左下に「」の印（台詞の象徴）
let mark = "「」" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HiraMinProN-W6", size: 150) ?? NSFont.systemFont(ofSize: 150, weight: .bold),
    .foregroundColor: orange,
]
mark.draw(at: NSPoint(x: paper.minX + 40, y: paper.minY + 30), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
