#!/usr/bin/env swift
// Renders the app icon and packages it as AppIcon.icns.
//
// The mark is the 💸 glyph on the app's marine gradient. Earlier versions drew
// a winged banknote from bezier paths; three attempts each failed a different
// way — horns, a blade, then a curled ribbon — so this draws the system glyph
// instead of reconstructing it.
//
// Note: Apple Color Emoji is system artwork. Fine for a locally built personal
// app; if this were ever distributed publicly it would need original artwork.
//
// Usage: swift scripts/make-icon.swift

import AppKit
import Foundation

let outputDirectory = "Sources/Ascend/Resources"
let iconsetPath = "\(outputDirectory)/AppIcon.iconset"

// Marine gradient, the app's accent hue.
let topColor = NSColor(srgbRed: 0.208, green: 0.549, blue: 0.671, alpha: 1)     // #358CAB
let bottomColor = NSColor(srgbRed: 0.071, green: 0.290, blue: 0.400, alpha: 1)  // #124A66

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    NSGraphicsContext.current!.imageInterpolation = .high

    // macOS icons sit inside a margin rather than filling the canvas.
    let inset = size * 0.0977
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237  // squircle-ish corner

    context.saveGState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    NSGradient(starting: topColor, ending: bottomColor)!.draw(in: rect, angle: -90)
    // A soft top highlight keeps the face from looking flat.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.16), NSColor(white: 1, alpha: 0)])!
        .draw(in: CGRect(x: rect.minX, y: rect.midY,
                         width: rect.width, height: rect.height / 2), angle: -90)
    context.restoreGState()

    let glyphSide = rect.width * 0.74
    let font = NSFont(name: "Apple Color Emoji", size: glyphSide)
        ?? NSFont.systemFont(ofSize: glyphSide)
    let glyph = NSAttributedString(string: "💸", attributes: [.font: font])
    let glyphSize = glyph.size()

    context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.012),
                      blur: rect.width * 0.035,
                      color: NSColor(white: 0, alpha: 0.30).cgColor)
    glyph.draw(at: CGPoint(x: rect.midX - glyphSize.width / 2,
                           y: rect.midY - glyphSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.removeItem(atPath: iconsetPath)
try FileManager.default.createDirectory(atPath: iconsetPath,
                                        withIntermediateDirectories: true)

for (name, pixels) in sizes {
    try write(drawIcon(size: pixels), to: "\(iconsetPath)/\(name).png")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", "\(outputDirectory)/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.removeItem(atPath: iconsetPath)
print("Wrote \(outputDirectory)/AppIcon.icns")
