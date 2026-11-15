import AppKit

/// Small Core Graphics / AppKit drawing kit used by every fake UI element.
enum Draw {
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    static func hand(_ size: CGFloat) -> NSFont {
        for name in ["Bradley Hand Bold", "BradleyHandITCTT-Bold", "Noteworthy-Bold", "Chalkduster", "Marker Felt"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: .light)
    }

    static func attrs(_ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left,
                      lineBreak: NSLineBreakMode = .byWordWrapping, lineSpacing: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = lineBreak
        p.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }

    @discardableResult
    static func text(_ s: String, at p: CGPoint, font: NSFont, color: NSColor) -> CGSize {
        let a = attrs(font, color)
        (s as NSString).draw(at: p, withAttributes: a)
        return (s as NSString).size(withAttributes: a)
    }

    static func text(_ s: String, in r: CGRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left,
                     lineBreak: NSLineBreakMode = .byWordWrapping, lineSpacing: CGFloat = 0) {
        (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: attrs(font, color, align: align, lineBreak: lineBreak, lineSpacing: lineSpacing))
    }

    static func size(_ s: String, font: NSFont) -> CGSize {
        (s as NSString).size(withAttributes: [.font: font])
    }

    static func textHeight(_ s: String, width: CGFloat, font: NSFont, lineSpacing: CGFloat = 0) -> CGFloat {
        let r = (s as NSString).boundingRect(with: CGSize(width: width, height: 100000),
                                             options: [.usesLineFragmentOrigin],
                                             attributes: attrs(font, .black, lineSpacing: lineSpacing))
        return ceil(r.height)
    }

    static func fill(_ ctx: CGContext, _ r: CGRect, _ color: NSColor, radius: CGFloat = 0) {
        ctx.setFillColor(color.cgColor)
        if radius > 0 {
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        } else {
            ctx.fill(r)
        }
    }

    static func stroke(_ ctx: CGContext, _ r: CGRect, _ color: NSColor, radius: CGFloat = 0, width: CGFloat = 1) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    static func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ color: NSColor, width: CGFloat = 1) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    static func circle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static func gradient(_ ctx: CGContext, _ r: CGRect, _ top: NSColor, _ bottom: NSColor, radius: CGFloat = 0) {
        ctx.saveGState()
        if radius > 0 {
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        } else {
            ctx.addRect(r)
        }
        ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
        ctx.restoreGState()
    }

    /// Draw an SF Symbol tinted with a single colour, fitted inside `r`.
    static func symbol(_ name: String, in r: CGRect, color: NSColor, weight: NSFont.Weight = .regular) {
        let cfg = NSImage.SymbolConfiguration(pointSize: r.height, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let img = base.withSymbolConfiguration(cfg) else { return }
        let s = img.size
        guard s.width > 0, s.height > 0 else { return }
        let k = min(r.width / s.width, r.height / s.height)
        let w = s.width * k, h = s.height * k
        let dst = CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        img.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The red/yellow/green window buttons.
    static func trafficLights(_ ctx: CGContext, y: CGFloat, active: Bool, hover: Bool) {
        let colors: [NSColor] = active || hover
            ? [NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1),
               NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1),
               NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)]
            : Array(repeating: NSColor(white: 0.82, alpha: 1), count: 3)
        let glyphs = ["xmark", "minus", "plus"]
        for i in 0..<3 {
            let c = CGPoint(x: 20 + CGFloat(i) * 20, y: y)
            circle(ctx, c, 6, colors[i])
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.12).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            if hover {
                symbol(glyphs[i], in: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4),
                       color: NSColor(white: 0, alpha: 0.55), weight: .bold)
            }
        }
    }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    static let accent = hex(0x0A84FF)
    static let selection = hex(0x0064E1)
    static let label = NSColor(white: 0.1, alpha: 1)
    static let secondary = NSColor(white: 0.45, alpha: 1)
}
