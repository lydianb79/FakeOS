import AppKit

/// The Fake OS application icon, drawn in code so the Dock icon at runtime and the exported
/// .icns are identical. A macOS-style squircle holding the game's own dusk wallpaper, a tiny
/// menu bar and Dock, and a window that is glitching apart around a staring eye (wren).
///
/// Coordinates: 1024×1024 design space, origin bottom-left (plain Core Graphics).
enum AppIconArt {
    static func image() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(ctx) }
            return true
        }
    }

    /// Writes AppIcon.iconset PNGs (16…1024) into `dir`.
    static func exportIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for mult in [1, 2] {
                let px = base * mult
                let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png(pixels: px).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
    }

    static func png(pixels px: Int) -> Data {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(ctx)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: - Art

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func squircle(_ r: CGRect) -> CGPath {
        // macOS app-icon tile: 824pt body with ~185pt continuous-looking corners.
        CGPath(roundedRect: r, cornerWidth: r.width * 0.2245, cornerHeight: r.width * 0.2245, transform: nil)
    }

    private static func radial(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        let clear = color.copy(alpha: 0)!
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func linear(_ ctx: CGContext, _ from: CGPoint, _ to: CGPoint, _ colors: [CGColor], _ locs: [CGFloat]? = nil) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func rr(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: CGColor) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    static func draw(_ ctx: CGContext) {
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = squircle(body)

        // drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: c(0, 0, 0, 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(c(0.05, 0.04, 0.12))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()

        // the dusk wallpaper from the game
        linear(ctx, CGPoint(x: 0, y: body.maxY), CGPoint(x: 0, y: body.minY),
               [c(0.20, 0.15, 0.50), c(0.10, 0.08, 0.30), c(0.03, 0.03, 0.12)], [0, 0.55, 1])
        radial(ctx, CGPoint(x: 300, y: 760), 470, c(0.62, 0.33, 0.80, 0.85))
        radial(ctx, CGPoint(x: 820, y: 900), 380, c(1.00, 0.62, 0.56, 0.75))
        radial(ctx, CGPoint(x: 760, y: 260), 420, c(0.22, 0.30, 0.85, 0.55))
        // soft ribbon
        ctx.saveGState()
        let ribbon = CGMutablePath()
        ribbon.move(to: CGPoint(x: 60, y: 420))
        ribbon.addCurve(to: CGPoint(x: 980, y: 760), control1: CGPoint(x: 380, y: 720), control2: CGPoint(x: 620, y: 420))
        ctx.addPath(ribbon)
        ctx.setLineWidth(150)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(c(1, 0.85, 0.95, 0.07))
        ctx.strokePath()
        ctx.addPath(ribbon)
        ctx.setLineWidth(40)
        ctx.setStrokeColor(c(1, 0.9, 0.95, 0.08))
        ctx.strokePath()
        ctx.restoreGState()

        // menu bar
        ctx.setFillColor(c(1, 1, 1, 0.13))
        ctx.fill(CGRect(x: body.minX, y: body.maxY - 58, width: body.width, height: 58))
        drawHexagon(ctx, center: CGPoint(x: 290, y: body.maxY - 29), radius: 13, color: c(1, 1, 1, 0.9))
        for (x, w) in [(326.0, 70.0), (412.0, 42.0), (470.0, 46.0)] as [(CGFloat, CGFloat)] {
            rr(ctx, CGRect(x: x, y: body.maxY - 35, width: w, height: 12), 6, c(1, 1, 1, x == 326 ? 0.85 : 0.5))
        }
        rr(ctx, CGRect(x: 640, y: body.maxY - 35, width: 100, height: 12), 6, c(1, 1, 1, 0.75))

        // dock
        let dock = CGRect(x: 512 - 230, y: 132, width: 460, height: 78)
        rr(ctx, dock, 26, c(1, 1, 1, 0.2))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: dock, cornerWidth: 26, cornerHeight: 26, transform: nil))
        ctx.setStrokeColor(c(1, 1, 1, 0.25))
        ctx.setLineWidth(2)
        ctx.strokePath()
        ctx.restoreGState()
        let dockColors: [(CGColor, CGColor)] = [
            (c(0.42, 0.77, 1.0), c(0.12, 0.44, 0.88)), (c(0.25, 0.25, 0.27), c(0.11, 0.11, 0.12)),
            (c(0.98, 0.98, 0.98), c(0.85, 0.85, 0.88)), (c(0.18, 0.18, 0.2), c(0.05, 0.05, 0.06)),
            (c(0.1, 0.1, 0.1), c(0.0, 0.0, 0.0)), (c(0.88, 0.88, 0.9), c(0.62, 0.62, 0.66)),
        ]
        for (i, cols) in dockColors.enumerated() {
            let r = CGRect(x: dock.minX + 18 + CGFloat(i) * 72, y: dock.minY + 12, width: 54, height: 54)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 13, cornerHeight: 13, transform: nil))
            ctx.clip()
            linear(ctx, CGPoint(x: 0, y: r.maxY), CGPoint(x: 0, y: r.minY), [cols.0, cols.1])
            if i == 4 { // wren, in the dock
                ctx.setFillColor(c(0.82, 0.08, 0.14))
                ctx.fillEllipse(in: CGRect(x: r.midX - 12, y: r.midY - 7, width: 24, height: 14))
                ctx.setFillColor(c(0, 0, 0))
                ctx.fillEllipse(in: CGRect(x: r.midX - 4, y: r.midY - 4, width: 8, height: 8))
            }
            ctx.restoreGState()
        }

        // the window, glitching
        let win = CGRect(x: 214, y: 292, width: 596, height: 452)
        let layer = windowLayer(size: win.size)
        // shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: c(0, 0, 0, 0.55))
        rr(ctx, win, 34, c(0, 0, 0, 0.9))
        ctx.restoreGState()
        // chromatic fringes
        let cyan = tinted(layer, c(0.1, 0.95, 1.0))
        let red = tinted(layer, c(1.0, 0.12, 0.25))
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.setAlpha(0.75)
        ctx.draw(cyan, in: win.offsetBy(dx: -14, dy: 2))
        ctx.draw(red, in: win.offsetBy(dx: 14, dy: -2))
        ctx.restoreGState()
        // main image with displaced slices
        let bands: [(CGFloat, CGFloat, CGFloat)] = [(612, 20, 30), (468, 12, -26), (330, 10, -18)] // y, h, dx
        var keep: [CGRect] = []
        var y = win.minY - 40
        for b in bands.sorted(by: { $0.0 < $1.0 }) {
            keep.append(CGRect(x: 0, y: y, width: 1024, height: b.0 - y))
            y = b.0 + b.1
        }
        keep.append(CGRect(x: 0, y: y, width: 1024, height: win.maxY + 40 - y))
        ctx.saveGState()
        ctx.clip(to: keep)
        ctx.draw(layer, in: win)
        ctx.restoreGState()
        for (by, bh, dx) in bands {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: by, width: 1024, height: bh))
            ctx.setBlendMode(.screen)
            ctx.setAlpha(0.8)
            ctx.draw(dx > 0 ? red : cyan, in: win.offsetBy(dx: dx + (dx > 0 ? 10 : -10), dy: 0))
            ctx.restoreGState()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: by, width: 1024, height: bh))
            ctx.draw(layer, in: win.offsetBy(dx: dx, dy: 0))
            ctx.restoreGState()
        }

        // scanlines + vignette
        ctx.setFillColor(c(0, 0, 0, 0.06))
        var sy: CGFloat = body.minY
        while sy < body.maxY { ctx.fill(CGRect(x: body.minX, y: sy, width: body.width, height: 2)); sy += 7 }
        let center = CGPoint(x: 512, y: 512)
        let vg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [c(0, 0, 0, 0), c(0, 0, 0, 0.35)] as CFArray, locations: [0.55, 1])!
        ctx.drawRadialGradient(vg, startCenter: center, startRadius: 0, endCenter: center, endRadius: 600, options: [.drawsAfterEndLocation])
        ctx.restoreGState()

        // rim light
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.addPath(shape)
        ctx.setStrokeColor(c(1, 1, 1, 0.16))
        ctx.setLineWidth(5)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawHexagon(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
        let p = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 + .pi / 6
            let pt = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    /// The fake window (title bar + dark content + eye), rendered on its own so it can be sliced.
    private static func windowLayer(size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(origin: .zero, size: size)
        let shape = CGPath(roundedRect: r, cornerWidth: 34, cornerHeight: 34, transform: nil)
        ctx.addPath(shape)
        ctx.clip()
        // content
        linear(ctx, CGPoint(x: 0, y: r.maxY), CGPoint(x: 0, y: 0), [c(0.10, 0.07, 0.11), c(0.03, 0.02, 0.04)])
        // title bar
        let tb = CGRect(x: 0, y: r.maxY - 76, width: r.width, height: 76)
        ctx.saveGState()
        ctx.clip(to: tb)
        linear(ctx, CGPoint(x: 0, y: tb.maxY), CGPoint(x: 0, y: tb.minY), [c(0.95, 0.95, 0.96), c(0.88, 0.88, 0.9)])
        ctx.restoreGState()
        ctx.setFillColor(c(0, 0, 0, 0.18))
        ctx.fill(CGRect(x: 0, y: tb.minY - 2, width: r.width, height: 2))
        let lights = [c(1, 0.373, 0.341), c(0.996, 0.737, 0.18), c(0.157, 0.784, 0.251)]
        for (i, col) in lights.enumerated() {
            ctx.setFillColor(col)
            ctx.fillEllipse(in: CGRect(x: 34 + CGFloat(i) * 46, y: tb.midY - 15, width: 30, height: 30))
        }
        rr(ctx, CGRect(x: r.midX - 70, y: tb.midY - 8, width: 140, height: 16), 8, c(0.55, 0.55, 0.58, 0.6))

        // the eye
        let eyeC = CGPoint(x: r.midX, y: (tb.minY) / 2 - 4)
        let ew: CGFloat = 330, eh: CGFloat = 170
        let almond = CGMutablePath()
        almond.move(to: CGPoint(x: eyeC.x - ew / 2, y: eyeC.y))
        almond.addQuadCurve(to: CGPoint(x: eyeC.x + ew / 2, y: eyeC.y), control: CGPoint(x: eyeC.x, y: eyeC.y + eh))
        almond.addQuadCurve(to: CGPoint(x: eyeC.x - ew / 2, y: eyeC.y), control: CGPoint(x: eyeC.x, y: eyeC.y - eh))
        almond.closeSubpath()
        radial(ctx, eyeC, 260, c(0.85, 0.05, 0.12, 0.45))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: c(1, 0.15, 0.2, 0.9))
        ctx.addPath(almond)
        ctx.setFillColor(c(0.93, 0.89, 0.88))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(almond)
        ctx.clip()
        radial(ctx, eyeC, 190, c(0.7, 0.55, 0.55, 0.0))
        linear(ctx, CGPoint(x: 0, y: eyeC.y + eh / 2), CGPoint(x: 0, y: eyeC.y - eh / 2),
               [c(0.55, 0.42, 0.44, 0.55), c(0, 0, 0, 0), c(0.4, 0.3, 0.32, 0.3)], [0, 0.45, 1])
        // iris
        let ir: CGFloat = 70
        let irisG = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [c(1.0, 0.36, 0.38), c(0.82, 0.07, 0.15), c(0.35, 0.0, 0.04)] as CFArray, locations: [0, 0.6, 1])!
        ctx.drawRadialGradient(irisG, startCenter: eyeC, startRadius: 0, endCenter: eyeC, endRadius: ir, options: [])
        // iris fibres
        ctx.setStrokeColor(c(0.4, 0.0, 0.05, 0.45))
        ctx.setLineWidth(2)
        for i in 0..<36 {
            let a = CGFloat(i) * .pi / 18
            ctx.move(to: CGPoint(x: eyeC.x + cos(a) * 30, y: eyeC.y + sin(a) * 30))
            ctx.addLine(to: CGPoint(x: eyeC.x + cos(a) * (ir - 4), y: eyeC.y + sin(a) * (ir - 4)))
        }
        ctx.strokePath()
        ctx.setFillColor(c(0.02, 0.0, 0.01))
        ctx.fillEllipse(in: CGRect(x: eyeC.x - 30, y: eyeC.y - 30, width: 60, height: 60))
        ctx.setFillColor(c(1, 1, 1, 0.9))
        ctx.fillEllipse(in: CGRect(x: eyeC.x + 14, y: eyeC.y + 16, width: 20, height: 20))
        ctx.restoreGState()
        ctx.addPath(almond)
        ctx.setStrokeColor(c(0.25, 0.02, 0.05, 0.9))
        ctx.setLineWidth(5)
        ctx.strokePath()

        // terminal-ish prompt lines under the eye
        rr(ctx, CGRect(x: 44, y: 40, width: 18, height: 26), 3, c(0.36, 0.89, 0.49, 0.9))
        rr(ctx, CGRect(x: 76, y: 46, width: 150, height: 14), 7, c(0.85, 0.85, 0.9, 0.35))
        return ctx.makeImage()!
    }

    private static func tinted(_ img: CGImage, _ color: CGColor) -> CGImage {
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.draw(img, in: r)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color)
        ctx.fill(r)
        return ctx.makeImage()!
    }
}
