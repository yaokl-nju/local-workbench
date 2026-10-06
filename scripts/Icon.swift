import AppKit

let root = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: s)
        transform.concat()
        let bg = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205)
        NSColor(calibratedRed: 0.94, green: 0.70, blue: 0.19, alpha: 1).setFill(); bg.fill()
        let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.shadowBlurRadius = 28; shadow.shadowColor = NSColor.black.withAlphaComponent(0.13); shadow.set()
        let page = NSBezierPath(roundedRect: NSRect(x: 225, y: 185, width: 574, height: 664), xRadius: 40, yRadius: 40)
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.95, alpha: 1).setFill(); page.fill()
        NSShadow().set()
        NSColor(calibratedRed: 0.73, green: 0.50, blue: 0.08, alpha: 1).setStroke()
        let check = NSBezierPath(); check.lineWidth = 22; check.lineCapStyle = .round; check.lineJoinStyle = .round
        check.move(to: NSPoint(x: 320, y: 666)); check.line(to: NSPoint(x: 350, y: 635)); check.line(to: NSPoint(x: 403, y: 695)); check.stroke()
        let lines: [(CGFloat, CGFloat)] = [(665, 275), (510, 375), (405, 375), (300, 250)]
        for (y, width) in lines {
            let line = NSBezierPath(); line.lineWidth = 18; line.lineCapStyle = .round
            let x: CGFloat = y == 665 ? 462 : 323
            line.move(to: NSPoint(x: x, y: y)); line.line(to: NSPoint(x: x + width, y: y))
            NSColor(calibratedWhite: 0.65, alpha: 0.45).setStroke(); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: root).appendingPathComponent(name))
    }
}
