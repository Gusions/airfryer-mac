// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
import AppKit

// Generates the app icon PNG (air fryer, macOS style) and the menu bar template icons.
// Usage: swiftc make_icon.swift -o make_icon && ./make_icon <output_folder>
let S: CGFloat = 1024
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
func fill(_ p: NSBezierPath, _ colors: [NSColor], angle: CGFloat) { NSGradient(colors: colors)!.draw(in: p, angle: angle) }

func draw() {
    // macOS tile (100 px margin) with shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = rounded(tile, 185)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = rgb(0, 0, 0, 0.35); sh.shadowOffset = NSSize(width: 0, height: -14); sh.shadowBlurRadius = 28
    sh.set()
    rgb(255, 120, 40).setFill(); tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    fill(tilePath, [rgb(255, 196, 94), rgb(255, 130, 44), rgb(236, 82, 24)], angle: -80)
    // Soft light at the top.
    NSGradient(colors: [rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0)])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

    // Ground shadow.
    NSGraphicsContext.saveGraphicsState()
    let ground = NSShadow()
    ground.shadowColor = rgb(90, 20, 0, 0.45); ground.shadowOffset = .zero; ground.shadowBlurRadius = 34
    ground.set()
    rgb(90, 20, 0, 0.35).setFill()
    NSBezierPath(ovalIn: NSRect(x: 300, y: 196, width: 424, height: 34)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Body.
    let bodyPath = NSBezierPath()
    let tl = NSPoint(x: 284, y: 804), tr = NSPoint(x: 740, y: 804), br = NSPoint(x: 706, y: 214), bl = NSPoint(x: 318, y: 214)
    bodyPath.move(to: NSPoint(x: 512, y: 804))
    bodyPath.appendArc(from: tr, to: br, radius: 120)
    bodyPath.appendArc(from: br, to: bl, radius: 150)
    bodyPath.appendArc(from: bl, to: tl, radius: 150)
    bodyPath.appendArc(from: tl, to: tr, radius: 120)
    bodyPath.close()
    NSGraphicsContext.saveGraphicsState()
    let bs = NSShadow()
    bs.shadowColor = rgb(80, 20, 0, 0.4); bs.shadowOffset = NSSize(width: 0, height: -10); bs.shadowBlurRadius = 24
    bs.set()
    rgb(30, 30, 34).setFill(); bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    fill(bodyPath, [rgb(66, 68, 76), rgb(28, 29, 33), rgb(14, 14, 17)], angle: 0)

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    // Vertical highlight on the left.
    NSGradient(colors: [rgb(255, 255, 255, 0.26), rgb(255, 255, 255, 0)])!
        .draw(in: NSRect(x: 292, y: 214, width: 150, height: 590), angle: 0)
    // Top band of the control panel.
    let panel = NSRect(x: 292, y: 626, width: 440, height: 178)
    NSGradient(colors: [rgb(52, 54, 60), rgb(22, 23, 27)])!.draw(in: panel, angle: -90)
    // Basket separation line.
    rgb(0, 0, 0, 0.7).setFill(); NSRect(x: 292, y: 620, width: 440, height: 8).fill()
    rgb(255, 255, 255, 0.10).setFill(); NSRect(x: 292, y: 612, width: 440, height: 3).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Glossy edge.
    rgb(255, 255, 255, 0.16).setStroke(); bodyPath.lineWidth = 3; bodyPath.stroke()

    // Display.
    let display = rounded(NSRect(x: 366, y: 668, width: 292, height: 96), 26)
    rgb(4, 5, 7).setFill(); display.fill()
    rgb(255, 255, 255, 0.12).setStroke(); display.lineWidth = 2; display.stroke()
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = rgb(255, 140, 20, 0.95); glow.shadowOffset = .zero; glow.shadowBlurRadius = 18
    glow.set()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 82, weight: .semibold),
        .foregroundColor: rgb(255, 156, 32), .paragraphStyle: para]
    NSString(string: "180").draw(in: NSRect(x: 366, y: 668, width: 292, height: 96), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    // Small buttons beside the display.
    for x in [330.0, 694.0] {
        let b = NSBezierPath(ovalIn: NSRect(x: x - 11, y: 706, width: 22, height: 22))
        fill(b, [rgb(120, 122, 130), rgb(48, 49, 55)], angle: -90)
    }

    // Basket handle.
    let handle = rounded(NSRect(x: 452, y: 300, width: 120, height: 250), 60)
    NSGraphicsContext.saveGraphicsState()
    let hs = NSShadow()
    hs.shadowColor = rgb(0, 0, 0, 0.7); hs.shadowOffset = NSSize(width: 0, height: -8); hs.shadowBlurRadius = 14
    hs.set()
    rgb(20, 20, 24).setFill(); handle.fill()
    NSGraphicsContext.restoreGraphicsState()
    fill(handle, [rgb(88, 90, 98), rgb(36, 37, 42), rgb(18, 18, 21)], angle: 0)
    NSGraphicsContext.saveGraphicsState()
    handle.addClip()
    NSGradient(colors: [rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0)])!
        .draw(in: NSRect(x: 452, y: 300, width: 50, height: 250), angle: 0)
    NSGraphicsContext.restoreGraphicsState()
    rgb(255, 255, 255, 0.18).setStroke(); handle.lineWidth = 2; handle.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
draw()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/icon_1024.png"))
print("icon_1024.png written to", out)

// Monochrome menu bar icon (template image: macOS tints it for light/dark mode).
func menuBarIcon(pixels: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 36.0 * 0.0505 // from the 1024 px drawing to the icon side
    let xf = NSAffineTransform()
    xf.translateX(by: (CGFloat(pixels) - 456 * scale) / 2 - 284 * scale, yBy: (CGFloat(pixels) - 590 * scale) / 2 - 214 * scale)
    xf.scale(by: scale)
    let body = NSBezierPath()
    let tl = NSPoint(x: 284, y: 804), tr = NSPoint(x: 740, y: 804), br = NSPoint(x: 706, y: 214), bl = NSPoint(x: 318, y: 214)
    body.move(to: NSPoint(x: 512, y: 804))
    body.appendArc(from: tr, to: br, radius: 120)
    body.appendArc(from: br, to: bl, radius: 150)
    body.appendArc(from: bl, to: tl, radius: 150)
    body.appendArc(from: tl, to: tr, radius: 120)
    body.close()
    body.transform(using: xf as AffineTransform)
    NSColor.black.setFill(); body.fill()
    NSGraphicsContext.current!.compositingOperation = .clear
    for (rect, radius) in [(NSRect(x: 366, y: 668, width: 292, height: 96), CGFloat(26)),
                           (NSRect(x: 452, y: 300, width: 120, height: 250), CGFloat(60)),
                           (NSRect(x: 280, y: 612, width: 460, height: 14), CGFloat(0))] {
        let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        p.transform(using: xf as AffineTransform)
        p.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
menuBarIcon(pixels: 18, to: out + "/MenuBarIcon.png")
menuBarIcon(pixels: 36, to: out + "/MenuBarIcon@2x.png")
print("MenuBarIcon.png and @2x written to", out)
