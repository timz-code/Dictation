// Reproducible native artwork; no fonts, downloaded assets or runtime dependencies.
import AppKit

let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func roundRect(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func artwork() {
    let tile = roundRect(NSRect(x: 62, y: 62, width: 900, height: 900), 206)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.01, 0.04, 0.08, 0.32)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.035, 0.09, 0.13).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.025, 0.065, 0.11), color(0.06, 0.22, 0.25)])!.draw(in: tile, angle: 65)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: color(0.26, 0.94, 0.75, 0.22), ending: color(0.08, 0.25, 0.3, 0))!
        .draw(fromCenter: NSPoint(x: 250, y: 920), radius: 0, toCenter: NSPoint(x: 250, y: 920), radius: 750, options: [])
    NSGraphicsContext.restoreGraphicsState()
    tile.lineWidth = 2
    color(0.65, 0.93, 0.88, 0.18).setStroke()
    tile.stroke()

    // Stand and cradle form one clear silhouette even at Finder's small sizes.
    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: 512, y: 320))
    stand.line(to: NSPoint(x: 512, y: 220))
    stand.move(to: NSPoint(x: 420, y: 214))
    stand.line(to: NSPoint(x: 604, y: 214))
    stand.lineWidth = 38
    stand.lineCapStyle = .round
    color(0.37, 0.89, 0.77).setStroke()
    stand.stroke()
    let cradle = NSBezierPath()
    cradle.move(to: NSPoint(x: 308, y: 568))
    cradle.line(to: NSPoint(x: 308, y: 535))
    cradle.curve(to: NSPoint(x: 512, y: 331), controlPoint1: NSPoint(x: 308, y: 418), controlPoint2: NSPoint(x: 395, y: 331))
    cradle.curve(to: NSPoint(x: 716, y: 535), controlPoint1: NSPoint(x: 629, y: 331), controlPoint2: NSPoint(x: 716, y: 418))
    cradle.line(to: NSPoint(x: 716, y: 568))
    cradle.lineWidth = 38
    cradle.lineCapStyle = .round
    color(0.46, 0.97, 0.83).setStroke()
    cradle.stroke()

    let capsule = roundRect(NSRect(x: 379, y: 425, width: 266, height: 400), 133)
    NSGraphicsContext.saveGraphicsState()
    let micShadow = NSShadow()
    micShadow.shadowColor = color(0, 0.04, 0.07, 0.45)
    micShadow.shadowBlurRadius = 24
    micShadow.shadowOffset = NSSize(width: 0, height: -8)
    micShadow.set()
    color(0.65, 0.94, 0.87).setFill()
    capsule.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.44, 0.83, 0.76), color(0.84, 0.98, 0.93), color(0.98, 1, 0.98)])!
        .draw(in: capsule, angle: 75)
    color(1, 1, 1, 0.65).setStroke()
    capsule.lineWidth = 2
    capsule.stroke()

    for index in 0..<5 {
        let width: CGFloat = index == 4 ? 112 : 150
        let slot = roundRect(NSRect(x: 512 - width / 2, y: 602 + CGFloat(index) * 32, width: width, height: 13), 6.5)
        color(0.07, 0.22, 0.24, 0.83).setFill()
        slot.fill()
    }
    let led = NSBezierPath(ovalIn: NSRect(x: 502, y: 476, width: 20, height: 20))
    color(0.025, 0.38, 0.33).setFill()
    led.fill()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        artwork()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let path = URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }
}
