import AppKit
import Foundation

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in iconSizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(pixels)
    let box = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor(calibratedRed: 0.055, green: 0.095, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: box, xRadius: side * 0.22, yRadius: side * 0.22).fill()
    drawOrbitMark(in: box)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let destination = iconsetURL.appendingPathComponent(name)
    try rep.representation(using: .png, properties: [:])!.write(to: destination)
}

func drawOrbitMark(in box: NSRect) {
    let side = min(box.width, box.height)
    let center = CGPoint(x: box.midX, y: box.midY)
    let radii = [side * 0.21, side * 0.34, side * 0.47]
    let gapCenters: [CGFloat] = [25, 145, 265]
    let accent = NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.96, alpha: 1)
    for (index, radius) in radii.enumerated() {
        let path = NSBezierPath()
        path.lineWidth = max(1.15, side * 0.027)
        path.lineCapStyle = .round
        path.appendArc(withCenter: center, radius: radius, startAngle: gapCenters[index] + 9, endAngle: gapCenters[index] + 351, clockwise: false)
        accent.withAlphaComponent(0.72 + CGFloat(index) * 0.09).setStroke()
        path.stroke()
    }
    let dot = side * 0.105
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)).fill()
}
