// Draws the app icon from the retro skin: its nameplate, with "qlm." in
// the skin's logo font, on the panel's color, at every size macOS asks
// for, into qlm/App/Assets.xcassets/AppIcon.appiconset.
//
//   swift tools/make-app-icon.swift
//
// A first icon, made from the skin's own material. Replace it freely.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let skin = root.appendingPathComponent("qlm/App/Skins/retro")
let output = root.appendingPathComponent("qlm/App/Assets.xcassets/AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func bitmap(_ url: URL) -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
        fail("can't read \(url.path)")
    }
    return rep
}

// The panel's color: the mean of its middle, where only the cabinet's
// surface shows.
func panelColor() -> NSColor {
    let panel = bitmap(skin.appendingPathComponent("png/panel-background@2x.png"))
    var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
    let width = panel.pixelsWide, height = panel.pixelsHigh
    for y in stride(from: height * 2 / 5, to: height * 3 / 5, by: 2) {
        for x in stride(from: width * 2 / 5, to: width * 3 / 5, by: 2) {
            guard let color = panel.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            red += color.redComponent
            green += color.greenComponent
            blue += color.blueComponent
            count += 1
        }
    }
    return NSColor(srgbRed: red / count, green: green / count, blue: blue / count, alpha: 1)
}

let panel = panelColor()
guard let plate = NSImage(contentsOf: skin.appendingPathComponent("masters/nameplate.png")) else {
    fail("no nameplate master")
}
// skin.json's logo slot: Helvetica Neue, bold, italic, 24 points in a 78
// point plate, in badgeInk.
let ink = NSColor(srgbRed: 0x34 / 255.0, green: 0x35 / 255.0, blue: 0x2b / 255.0, alpha: 1)
let logoFont: (CGFloat) -> NSFont = { size in
    let base = NSFont(name: "Helvetica Neue", size: size) ?? NSFont.systemFont(ofSize: size)
    return NSFontManager.shared.convert(base, toHaveTrait: [.boldFontMask, .italicFontMask])
}

// On Apple's 1024 grid: an 824 point body with a 185 point radius. In
// sRGB, so the output is the same on any Mac.
func draw(pixels: Int) -> Data {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let bitmap = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("can't make a bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
    let unit = CGFloat(pixels) / 1024

    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    panel.setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit).fill()

    let plateWidth = 640 * unit
    let plateHeight = plateWidth * plate.size.height / plate.size.width
    let plateRect = NSRect(x: (CGFloat(pixels) - plateWidth) / 2, y: (CGFloat(pixels) - plateHeight) / 2,
                           width: plateWidth, height: plateHeight)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 24 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    plate.draw(in: plateRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // The logo's ink centers in the slot's frame: 3 points down the 38
    // point plate, 32 high.
    let scale = plateWidth / 78
    let text = NSAttributedString(string: "qlm.", attributes: [.font: logoFont(24 * scale), .foregroundColor: ink])
    let line = CTLineCreateWithAttributedString(text)
    let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let slot = NSRect(x: plateRect.minX, y: plateRect.maxY - (3 + 32) * scale, width: plateWidth, height: 32 * scale)
    let context = NSGraphicsContext.current!.cgContext
    context.textPosition = CGPoint(x: slot.midX - glyphs.midX, y: slot.midY - glyphs.midY)
    CTLineDraw(line, context)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = bitmap.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fail("can't encode a PNG")
    }
    return png
}

var images: [[String: String]] = []
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        do {
            try draw(pixels: points * scale).write(to: output.appendingPathComponent(name))
        } catch {
            fail("can't write \(name): \(error)")
        }
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("wrote \(output.path)")
