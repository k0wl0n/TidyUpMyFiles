import AppKit

/// The app icon, drawn in code so the Dock, the packaged .icns and the sidebar logo always match.
/// Original artwork: gradient squircle, white folder, check mark and a sparkle (no SF Symbols, which
/// Apple doesn't allow in app icons).
enum IconArt {
    /// Draws the icon on a 1024×1024 canvas (top-left origin) into the current graphics context.
    private static func draw() {
        // Background squircle on the macOS icon grid, with a soft shadow.
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 90, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor(red: 0.55, green: 0.36, blue: 0.97, alpha: 1).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [
            NSColor(red: 1.00, green: 0.42, blue: 0.66, alpha: 1),
            NSColor(red: 0.72, green: 0.36, blue: 0.95, alpha: 1),
            NSColor(red: 0.36, green: 0.40, blue: 1.00, alpha: 1),
        ])?.draw(in: tile, angle: -50)

        // Soft highlight in the top-left corner.
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])?
            .draw(in: tile, relativeCenterPosition: NSPoint(x: -0.55, y: -0.55))
        NSGraphicsContext.restoreGraphicsState()

        // Folder: tab plus body.
        let folder = NSBezierPath(roundedRect: NSRect(x: 252, y: 322, width: 230, height: 120), xRadius: 42, yRadius: 42)
        folder.append(NSBezierPath(roundedRect: NSRect(x: 252, y: 372, width: 520, height: 372), xRadius: 54, yRadius: 54))
        NSGraphicsContext.saveGraphicsState()
        let folderShadow = NSShadow()
        folderShadow.shadowColor = NSColor(red: 0.25, green: 0.1, blue: 0.45, alpha: 0.35)
        folderShadow.shadowBlurRadius = 18
        folderShadow.shadowOffset = NSSize(width: 0, height: -8)
        folderShadow.set()
        NSColor.white.withAlphaComponent(0.97).setFill()
        folder.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Check mark inside the folder.
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 392, y: 560))
        check.line(to: NSPoint(x: 478, y: 642))
        check.line(to: NSPoint(x: 636, y: 478))
        check.lineWidth = 58
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(red: 0.62, green: 0.33, blue: 0.96, alpha: 1).setStroke()
        check.stroke()

        // Four-point sparkle, top right.
        NSColor.white.setFill()
        sparkle(center: NSPoint(x: 742, y: 262), radius: 78).fill()
        sparkle(center: NSPoint(x: 838, y: 372), radius: 34).fill()
    }

    private static func sparkle(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        let inner = radius * 0.24
        let path = NSBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 - .pi / 2
            let length = index.isMultiple(of: 2) ? radius : inner
            let point = NSPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }

    /// A bitmap of the icon at `pixels`×`pixels`.
    static func bitmap(pixels: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        // Flip to a top-left origin and scale the 1024 design canvas to the requested size.
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: CGFloat(pixels))
        transform.scaleX(by: CGFloat(pixels) / 1024, yBy: -CGFloat(pixels) / 1024)
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func image(pixels: Int = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        if let rep = bitmap(pixels: pixels) { image.addRepresentation(rep) }
        return image
    }

    /// Writes an `.iconset` folder for `iconutil` (used by scripts/build-app.sh).
    static func exportIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 1 ? "" : "@2x"
                guard let png = bitmap(pixels: points * scale)?.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }
}
