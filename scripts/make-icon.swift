// Generates the app icon set from the Two-Macs glyph. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let u = px / 1024          // design units
    let r = NSRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u)      // macOS icon grid: 824 of 1024
    let bg = NSBezierPath(roundedRect: r, xRadius: 185*u, yRadius: 185*u)
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.26, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 1)])!
    grad.draw(in: bg, angle: -90)
    // subtle inner highlight
    NSColor.white.withAlphaComponent(0.06).setStroke(); bg.lineWidth = 6*u; bg.stroke()

    func stroke(_ p: NSBezierPath, _ w: CGFloat, _ c: NSColor = .white) { c.setStroke(); p.lineWidth = w*u; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke() }
    func laptop(_ ox: CGFloat, _ oy: CGFloat, color: NSColor) {
        let screen = NSBezierPath(roundedRect: NSRect(x: ox*u, y: (oy+40)*u, width: 250*u, height: 165*u), xRadius: 28*u, yRadius: 28*u)
        stroke(screen, 34, color)
        let base = NSBezierPath(); base.move(to: NSPoint(x: (ox-30)*u, y: oy*u)); base.line(to: NSPoint(x: (ox+280)*u, y: oy*u)); stroke(base, 34, color)
    }
    let accent = NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1)
    laptop(200, 300, color: .white)
    laptop(575, 540, color: .white)
    // link, dashed and cut
    let link = NSBezierPath(); link.move(to: NSPoint(x: 470*u, y: 420*u)); link.line(to: NSPoint(x: 580*u, y: 585*u))
    link.setLineDash([40*u, 44*u], count: 2, phase: 0); stroke(link, 30, accent)
    let cut = NSBezierPath(); cut.move(to: NSPoint(x: 600*u, y: 430*u)); cut.line(to: NSPoint(x: 450*u, y: 575*u)); stroke(cut, 38, accent)
    img.unlockFocus()
    return img
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AWDLess/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, Int, Int)] = [("16x16",16,1),("16x16",16,2),("32x32",32,1),("32x32",32,2),("128x128",128,1),("128x128",128,2),("256x256",256,1),("256x256",256,2),("512x512",512,1),("512x512",512,2)]
var entries: [[String: String]] = []
for (name, pt, scale) in sizes {
    let px = CGFloat(pt * scale)
    let img = render(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px)); NSGraphicsContext.restoreGraphicsState()
    let file = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(file)"))
    entries.append(["idiom": "mac", "size": name, "scale": "\(scale)x", "filename": file])
}
let json = try! JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted])
try! json.write(to: URL(fileURLWithPath: "\(out)/Contents.json"))
// also a 1024 preview for the website
let big = render(1024); let rep = NSBitmapImageRep(data: big.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon-1024.png"))
print("icon set written to \(out)")
