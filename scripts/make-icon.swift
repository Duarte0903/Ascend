#!/usr/bin/env swift
// Renders the app icon and packages it as AppIcon.icns.
// The mark is a winged banknote on the app's marine accent.
//
// Usage: swift scripts/make-icon.swift

import AppKit
import Foundation

let outputDirectory = "Sources/Ascend/Resources"
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

    // The mark is a banknote with wings.
    //
    // Two things decide whether this reads as wings rather than horns: the
    // wings attach at the note's mid-height and sweep outward rather than
    // rising from its top edge, and the note carries no punched hole — a hole
    // in the centre turns the whole shape into a face.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.014),
                      blur: rect.width * 0.036,
                      color: NSColor(white: 0, alpha: 0.24).cgColor)

    // A wing: leading edge bowed up from root to tip, trailing edge scalloped
    // back into feathers.
    func drawWing(mirrored: Bool) {
        let rootX: CGFloat = 0.580, rootY: CGFloat = 0.415
        let tipX: CGFloat = 0.965, tipY: CGFloat = 0.665
        let depth: CGFloat = 0.163
        let feathers = 3

        func fx(_ v: CGFloat) -> CGFloat { mirrored ? 1 - v : v }

        let path = NSBezierPath()
        path.move(to: point(fx(rootX), rootY + depth * 0.5))
        path.curve(to: point(fx(tipX), tipY),
                   controlPoint1: point(fx(rootX + (tipX - rootX) * 0.35), rootY + depth * 0.98),
                   controlPoint2: point(fx(tipX - (tipX - rootX) * 0.18), tipY + depth * 0.36))

        var previous = CGPoint(x: tipX, y: tipY)
        for step in 1...feathers {
            let progress = CGFloat(step) / CGFloat(feathers)
            let nextX = tipX + (rootX - tipX) * progress
            let nextY = tipY + (rootY - tipY) * progress - depth * 0.30
            let scallopX = (previous.x + nextX) / 2
            let scallopY = (previous.y + nextY) / 2 - depth * 0.46
            path.curve(to: point(fx(nextX), nextY),
                       controlPoint1: point(fx(scallopX), scallopY),
                       controlPoint2: point(fx(scallopX), scallopY))
            previous = CGPoint(x: nextX, y: nextY)
        }
        path.close()
        NSColor.white.setFill()
        path.fill()
    }

    drawWing(mirrored: false)
    drawWing(mirrored: true)

    // The note, tilted a touch so the mark has some motion.
    let centre = point(0.50, 0.435)
    let noteBox = CGRect(x: centre.x - rect.width * 0.1975,
                         y: centre.y - rect.height * 0.136,
                         width: rect.width * 0.395,
                         height: rect.height * 0.272)
    let tilt = NSAffineTransform()
    tilt.translateX(by: centre.x, yBy: centre.y)
    tilt.rotate(byDegrees: -6)
    tilt.translateX(by: -centre.x, yBy: -centre.y)

    let note = NSBezierPath(roundedRect: noteBox,
                            xRadius: noteBox.height * 0.20,
                            yRadius: noteBox.height * 0.20)
    note.transform(using: tilt as AffineTransform)
    NSColor.white.setFill()
    note.fill()
    context.restoreGState()

    // Inner rule reads as banknote engraving at large sizes and simply
    // disappears at 16pt, where the silhouette carries the meaning.
    let innerBox = noteBox.insetBy(dx: noteBox.height * 0.19, dy: noteBox.height * 0.21)
    let inner = NSBezierPath(roundedRect: innerBox,
                             xRadius: innerBox.height * 0.3,
                             yRadius: innerBox.height * 0.3)
    inner.transform(using: tilt as AffineTransform)
    inner.lineWidth = rect.width * 0.015
    bottomColor.withAlphaComponent(0.55).setStroke()
    inner.stroke()

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
