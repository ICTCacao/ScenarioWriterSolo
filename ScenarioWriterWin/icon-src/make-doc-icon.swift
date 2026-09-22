// .scwd 書類のアイコン（Windows 用）。白い書類の上に Mac 版と同じアプリのアイコンを載せる。
// 使い方: swift make-doc-icon.swift <app-icon-1024.png> <out.png>
import Foundation
import AppKit
let appIcon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
// 書類（角を折った白い紙）
let page = NSRect(x: 176, y: 72, width: 672, height: 880)
let fold: CGFloat = 170
let path = NSBezierPath()
path.move(to: NSPoint(x: page.minX, y: page.minY))
path.line(to: NSPoint(x: page.maxX, y: page.minY))
path.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
path.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
path.line(to: NSPoint(x: page.minX, y: page.maxY))
path.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setFill(); path.fill()
ctx.restoreGState()
NSColor(calibratedWhite: 0.78, alpha: 1).setStroke(); path.lineWidth = 6; path.stroke()
// 折り返し
let tri = NSBezierPath()
tri.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
tri.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
tri.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
tri.close()
NSColor(calibratedWhite: 0.90, alpha: 1).setFill(); tri.fill()
NSColor(calibratedWhite: 0.78, alpha: 1).setStroke(); tri.lineWidth = 6; tri.stroke()
// アプリのアイコン
let size: CGFloat = 420
appIcon.draw(in: NSRect(x: (canvas - size) / 2, y: 340, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
// 拡張子
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 96, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1), .paragraphStyle: para]
("SCWD" as NSString).draw(in: NSRect(x: page.minX, y: 150, width: page.width, height: 120), withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
