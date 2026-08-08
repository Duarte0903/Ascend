#!/usr/bin/env swift
// Renders the app icon and packages it as AppIcon.icns.
// The mark is the dashboard's own rising sparkline, so the icon and the app
// share a shape rather than the icon being unrelated decoration.
//
// Usage: swift scripts/make-icon.swift

import AppKit
import Foundation

let outputDirectory = "Sources/FinanceTracker/Resources"
let iconsetPath = "\(outputDirectory)/AppIcon.iconset"

// Marine gradient, the app's accent hue.
let topColor = NSColor(srgbRed: 0.208, green: 0.549, blue: 0.671, alpha: 1)     // #35 8C AB
let bottomColor = NSColor(srgbRed: 0.071, green: 0.290, blue: 0.400, alpha: 1)  // #12 4A 66

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inside a margin rather than filling the canvas.
    let inset = size * 0.0977
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237  // squircle-ish corner

    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    context.saveGState()
    squircle.addClip()
    let gradient = NSGradient(starting: topColor, ending: bottomColor)!
    gradient.draw(in: rect, angle: -90)

    // A soft top highlight keeps the face from looking flat.
    let highlight = NSGradient(colors: [NSColor(white: 1, alpha: 0.20),
                                        NSColor(white: 1, alpha: 0.0)])!
    highlight.draw(in: CGRect(x: rect.minX, y: rect.midY,
                              width: rect.width, height: rect.height / 2), angle: -90)
    context.restoreGState()

    // The rising line, in the app's own proportions.
    let points: [CGPoint] = [
        CGPoint(x: 0.20, y: 0.36), CGPoint(x: 0.38, y: 0.45),
        CGPoint(x: 0.55, y: 0.40), CGPoint(x: 0.78, y: 0.70),
    ].map { CGPoint(x: rect.minX + rect.width * $0.x, y: rect.minY + rect.height * $0.y) }

    let line = NSBezierPath()
    line.move(to: points[0])
    for point in points.dropFirst() { line.line(to: point) }
    line.lineWidth = rect.width * 0.088  // heavy enough to hold at 16pt
    line.lineCapStyle = .round
    line.lineJoinStyle = .round

    // Drop shadow gives the mark a little lift off the gradient.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.012),
                      blur: rect.width * 0.03,
                      color: NSColor(white: 0, alpha: 0.28).cgColor)
    NSColor.white.setStroke()
    line.stroke()

    // Endpoint dot — the same emphasis the dashboard sparkline uses.
    let dotRadius = rect.width * 0.072
    let dot = NSBezierPath(ovalIn: CGRect(x: points[3].x - dotRadius, y: points[3].y - dotRadius,
                                          width: dotRadius * 2, height: dotRadius * 2))
    NSColor.white.setFill()
    dot.fill()
    context.restoreGState()

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
