import AppKit

enum AppKind: String, CaseIterable {
    case finder = "Finder"
    case terminal = "Terminal"
    case textEdit = "TextEdit"
    case activity = "Activity Monitor"
    case preview = "Preview"
    case settings = "System Settings"
    case wren = "wren"
}

/// Procedurally drawn icons (no bundled art).
enum Icons {
    static func squircle(_ r: CGRect) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.height * 0.225, transform: nil)
    }

    static func app(_ kind: AppKind, in rect: CGRect, ctx: CGContext) {
        let r = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: r.height * 0.03), blur: r.height * 0.06,
                      color: NSColor(white: 0, alpha: 0.35).cgColor)
        ctx.addPath(squircle(r))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(squircle(r))
        ctx.clip()
        let s = r.width
        switch kind {
        case .finder:
            Draw.gradient(ctx, r, Draw.hex(0x6CC4FF), Draw.hex(0x1E6FE0))
            Draw.fill(ctx, CGRect(x: r.minX, y: r.midY, width: s, height: s / 2), NSColor(white: 1, alpha: 0.06))
            Draw.symbol("folder.fill", in: r.insetBy(dx: s * 0.2, dy: s * 0.22), color: .white)
        case .terminal:
            Draw.gradient(ctx, r, Draw.hex(0x3A3A3C), Draw.hex(0x1C1C1E))
            Draw.stroke(ctx, r.insetBy(dx: s * 0.06, dy: s * 0.06), NSColor(white: 1, alpha: 0.25), radius: s * 0.12, width: s * 0.02)
            Draw.text(">_", at: CGPoint(x: r.minX + s * 0.17, y: r.minY + s * 0.14),
                      font: Draw.mono(s * 0.34, .bold), color: Draw.hex(0x5BE37D))
        case .textEdit:
            Draw.gradient(ctx, r, Draw.hex(0xFFFFFF), Draw.hex(0xE7E7EA))
            for i in 0..<6 {
                let y = r.minY + s * (0.24 + CGFloat(i) * 0.1)
                Draw.line(ctx, CGPoint(x: r.minX + s * 0.18, y: y), CGPoint(x: r.maxX - s * (i == 5 ? 0.45 : 0.18), y: y),
                          NSColor(white: 0.72, alpha: 1), width: s * 0.025)
            }
            Draw.symbol("pencil", in: CGRect(x: r.midX, y: r.midY, width: s * 0.42, height: s * 0.42),
                        color: Draw.hex(0xF0A030), weight: .bold)
        case .activity:
            Draw.gradient(ctx, r, Draw.hex(0x2B2B2E), Draw.hex(0x0E0E10))
            Draw.symbol("waveform.path.ecg", in: r.insetBy(dx: s * 0.16, dy: s * 0.24), color: Draw.hex(0x45E36A), weight: .semibold)
        case .preview:
            Draw.gradient(ctx, r, Draw.hex(0x9FD3FF), Draw.hex(0x4A90E2))
            Draw.symbol("photo.on.rectangle.angled", in: r.insetBy(dx: s * 0.18, dy: s * 0.2), color: .white)
        case .settings:
            Draw.gradient(ctx, r, Draw.hex(0xD9D9DE), Draw.hex(0x8E8E93))
            Draw.symbol("gearshape.fill", in: r.insetBy(dx: s * 0.14, dy: s * 0.14), color: Draw.hex(0x3A3A3C))
        case .wren:
            Draw.gradient(ctx, r, Draw.hex(0x151515), Draw.hex(0x000000))
            Draw.symbol("eye.fill", in: r.insetBy(dx: s * 0.2, dy: s * 0.28), color: Draw.hex(0xB3121E))
        }
        ctx.restoreGState()
    }

    static func trash(full: Bool, in rect: CGRect, ctx: CGContext) {
        let s = rect.width
        let body = CGRect(x: rect.minX + s * 0.22, y: rect.minY + s * 0.2, width: s * 0.56, height: s * 0.68)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: s * 0.03), blur: s * 0.05, color: NSColor(white: 0, alpha: 0.3).cgColor)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: body.minX, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - s * 0.05, y: body.maxY))
        p.addQuadCurve(to: CGPoint(x: body.minX + s * 0.05, y: body.maxY), control: CGPoint(x: body.midX, y: body.maxY + s * 0.04))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(NSColor(white: 0.93, alpha: 0.92).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        // ridges
        for i in 0..<7 {
            let x = body.minX + s * 0.05 + CGFloat(i) * (body.width - s * 0.1) / 6
            Draw.line(ctx, CGPoint(x: x, y: body.minY + s * 0.04), CGPoint(x: body.midX + (x - body.midX) * 0.85, y: body.maxY - s * 0.02),
                      NSColor(white: 0.7, alpha: 0.9), width: s * 0.012)
        }
        if full {
            let papers: [(CGFloat, CGFloat, CGFloat)] = [(0.3, 0.1, -0.3), (0.45, 0.06, 0.2), (0.58, 0.1, 0.5)]
            for (x, y, a) in papers {
                ctx.saveGState()
                ctx.translateBy(x: rect.minX + s * x + s * 0.08, y: rect.minY + s * y + s * 0.1)
                ctx.rotate(by: a)
                Draw.fill(ctx, CGRect(x: -s * 0.08, y: -s * 0.1, width: s * 0.16, height: s * 0.2), .white, radius: s * 0.01)
                Draw.stroke(ctx, CGRect(x: -s * 0.08, y: -s * 0.1, width: s * 0.16, height: s * 0.2), NSColor(white: 0.75, alpha: 1),
                            radius: s * 0.01, width: s * 0.008)
                ctx.restoreGState()
            }
        }
        // rim
        Draw.fill(ctx, CGRect(x: body.minX - s * 0.02, y: body.minY - s * 0.02, width: body.width + s * 0.04, height: s * 0.05),
                  NSColor(white: 0.85, alpha: 1), radius: s * 0.025)
    }

    static func folder(in rect: CGRect, ctx: CGContext, tint: NSColor? = nil) {
        let s = rect.width
        let back = CGRect(x: rect.minX + s * 0.06, y: rect.minY + s * 0.18, width: s * 0.88, height: s * 0.66)
        let topC = tint ?? Draw.hex(0x5FAEEC)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: s * 0.015), blur: s * 0.03, color: NSColor(white: 0, alpha: 0.25).cgColor)
        // tab
        Draw.fill(ctx, CGRect(x: back.minX, y: back.minY - s * 0.07, width: s * 0.36, height: s * 0.14), topC.blended(withFraction: 0.1, of: .black)!, radius: s * 0.04)
        Draw.fill(ctx, back, topC.blended(withFraction: 0.1, of: .black)!, radius: s * 0.05)
        ctx.restoreGState()
        let front = CGRect(x: back.minX, y: back.minY + s * 0.08, width: back.width, height: back.height - s * 0.08)
        Draw.gradient(ctx, front, (tint ?? Draw.hex(0x8ACDFB)), (tint ?? Draw.hex(0x5DB0F0)).blended(withFraction: 0.05, of: .black)!, radius: s * 0.05)
        Draw.fill(ctx, CGRect(x: front.minX, y: front.minY, width: front.width, height: s * 0.015), NSColor(white: 1, alpha: 0.5))
    }

    static func page(in rect: CGRect, ctx: CGContext, fill: NSColor = .white) -> CGRect {
        let s = rect.width
        let r = CGRect(x: rect.minX + s * 0.18, y: rect.minY + s * 0.06, width: s * 0.64, height: s * 0.86)
        let fold = s * 0.16
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: s * 0.01), blur: s * 0.03, color: NSColor(white: 0, alpha: 0.3).cgColor)
        ctx.addPath(p)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(p)
        ctx.setStrokeColor(NSColor(white: 0.75, alpha: 1).cgColor)
        ctx.setLineWidth(max(0.5, s * 0.008))
        ctx.strokePath()
        // fold
        let f = CGMutablePath()
        f.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
        f.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
        f.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        f.closeSubpath()
        ctx.addPath(f)
        ctx.setFillColor(NSColor(white: 0.86, alpha: 1).cgColor)
        ctx.fillPath()
        return r
    }

    static func file(_ node: FSNode, in rect: CGRect, ctx: CGContext) {
        let s = rect.width
        switch node.kind {
        case .folder:
            folder(in: rect, ctx: ctx, tint: node.name.hasPrefix(".") ? Draw.hex(0x6A7C8E) : nil)
        case .text:
            let r = page(in: rect, ctx: ctx)
            let lines = node.content.split(separator: "\n", omittingEmptySubsequences: false).prefix(12)
            var y = r.minY + s * 0.08
            for l in lines {
                let w = min(r.width - s * 0.12, CGFloat(l.count) * s * 0.012 + (l.isEmpty ? 0 : s * 0.05))
                if w > 0 {
                    Draw.line(ctx, CGPoint(x: r.minX + s * 0.06, y: y), CGPoint(x: r.minX + s * 0.06 + w, y: y),
                              NSColor(white: 0.55, alpha: 1), width: max(0.5, s * 0.014))
                }
                y += s * 0.055
                if y > r.maxY - s * 0.06 { break }
            }
        case .image:
            let r = page(in: rect, ctx: ctx)
            let ir = r.insetBy(dx: s * 0.04, dy: s * 0.04)
            ctx.saveGState()
            ctx.clip(to: ir)
            Pictures.draw(node.content, in: ir, ctx: ctx)
            ctx.restoreGState()
        case .lock:
            let r = page(in: rect, ctx: ctx, fill: Draw.hex(0xF4F1EA))
            Draw.symbol("lock.fill", in: r.insetBy(dx: r.width * 0.25, dy: r.height * 0.3), color: Draw.hex(0x8E2B2B))
        case .soul:
            let r = page(in: rect, ctx: ctx, fill: Draw.hex(0x101014))
            Draw.symbol("figure.stand", in: r.insetBy(dx: r.width * 0.25, dy: r.height * 0.2), color: NSColor(white: 0.85, alpha: 0.9))
        case .pdf:
            let r = page(in: rect, ctx: ctx)
            Draw.fill(ctx, CGRect(x: r.minX - s * 0.04, y: r.maxY - s * 0.3, width: s * 0.36, height: s * 0.16), Draw.hex(0xE0322B), radius: s * 0.02)
            Draw.text("PDF", in: CGRect(x: r.minX - s * 0.04, y: r.maxY - s * 0.3 + s * 0.015, width: s * 0.36, height: s * 0.16),
                      font: Draw.font(s * 0.11, .bold), color: .white, align: .center)
        case .dmg:
            Draw.symbol("externaldrive.fill", in: rect.insetBy(dx: s * 0.12, dy: s * 0.2), color: NSColor(white: 0.62, alpha: 1))
        case .app:
            app(.wren, in: rect, ctx: ctx)
        }
    }

    /// macOS-style arrow pointer.
    static func cursor(ctx: CGContext) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 17))
        p.addLine(to: CGPoint(x: 4.2, y: 13.2))
        p.addLine(to: CGPoint(x: 7, y: 19.6))
        p.addLine(to: CGPoint(x: 9.8, y: 18.4))
        p.addLine(to: CGPoint(x: 7.1, y: 12.2))
        p.addLine(to: CGPoint(x: 12.4, y: 12.2))
        p.closeSubpath()
        ctx.saveGState()
        ctx.translateBy(x: 2, y: 2)
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: NSColor(white: 0, alpha: 0.4).cgColor)
        ctx.addPath(p)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 2, y: 2)
        ctx.addPath(p)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// Procedural "photos".
enum Pictures {
    static func draw(_ id: String, in r: CGRect, ctx: CGContext) {
        switch id {
        case "screenshot": screenshot(r, ctx)
        case "beach": beach(r, ctx)
        case "cat": cat(r, ctx)
        case "window": window(r, ctx)
        case "fridge": fridge(r, ctx)
        case "us": us(r, ctx)
        case "tooth": tooth(r, ctx)
        default: Draw.fill(ctx, r, NSColor(white: 0.5, alpha: 1))
        }
    }

    /// A screenshot of this very desktop… with someone standing next to the Dock.
    static func screenshot(_ r: CGRect, _ ctx: CGContext) {
        Draw.gradient(ctx, r, Draw.hex(0x3A2F7A), Draw.hex(0xC07A8A))
        Draw.fill(ctx, CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.035), NSColor(white: 1, alpha: 0.35))
        let dock = CGRect(x: r.midX - r.width * 0.28, y: r.maxY - r.height * 0.11, width: r.width * 0.56, height: r.height * 0.08)
        Draw.fill(ctx, dock, NSColor(white: 1, alpha: 0.3), radius: r.height * 0.02)
        for i in 0..<7 {
            let x = dock.minX + dock.width * (0.06 + CGFloat(i) * 0.13)
            Draw.fill(ctx, CGRect(x: x, y: dock.minY + dock.height * 0.15, width: dock.height * 0.7, height: dock.height * 0.7),
                      NSColor(white: 1, alpha: 0.7), radius: dock.height * 0.15)
        }
        Draw.fill(ctx, CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.18, width: r.width * 0.45, height: r.height * 0.4),
                  NSColor(white: 0.97, alpha: 1), radius: r.height * 0.02)
        // the figure
        let fx = dock.maxX + r.width * 0.03
        let fy = r.maxY - r.height * 0.06
        let h = r.height * 0.42
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.02, alpha: 0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: fx - h * 0.07, y: fy - h, width: h * 0.14, height: h * 0.16))
        let body = CGMutablePath()
        body.move(to: CGPoint(x: fx - h * 0.1, y: fy - h * 0.82))
        body.addLine(to: CGPoint(x: fx + h * 0.1, y: fy - h * 0.82))
        body.addLine(to: CGPoint(x: fx + h * 0.13, y: fy))
        body.addLine(to: CGPoint(x: fx - h * 0.13, y: fy))
        body.closeSubpath()
        ctx.addPath(body)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func beach(_ r: CGRect, _ ctx: CGContext) {
        Draw.gradient(ctx, CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.6), Draw.hex(0xF6B48B), Draw.hex(0xF7D9A8))
        Draw.circle(ctx, CGPoint(x: r.midX + r.width * 0.15, y: r.minY + r.height * 0.52), r.height * 0.12, Draw.hex(0xFFE3A3))
        Draw.gradient(ctx, CGRect(x: r.minX, y: r.minY + r.height * 0.55, width: r.width, height: r.height * 0.2), Draw.hex(0x5E8FB8), Draw.hex(0x3C6C93))
        Draw.gradient(ctx, CGRect(x: r.minX, y: r.minY + r.height * 0.75, width: r.width, height: r.height * 0.25), Draw.hex(0xE8D3AE), Draw.hex(0xCDB08A))
        // two people, close
        for (dx, hh) in [(-0.3, 0.2), (-0.26, 0.18)] as [(CGFloat, CGFloat)] {
            let x = r.midX + r.width * dx, y = r.minY + r.height * 0.86
            Draw.fill(ctx, CGRect(x: x - r.width * 0.012, y: y - r.height * hh, width: r.width * 0.024, height: r.height * hh), Draw.hex(0x3A2A2A), radius: r.width * 0.01)
            Draw.circle(ctx, CGPoint(x: x, y: y - r.height * hh - r.height * 0.02), r.width * 0.016, Draw.hex(0x3A2A2A))
        }
        // and one far away, in the water, facing the camera
        let x = r.midX + r.width * 0.33, y = r.minY + r.height * 0.66
        Draw.fill(ctx, CGRect(x: x - r.width * 0.005, y: y - r.height * 0.06, width: r.width * 0.01, height: r.height * 0.06), NSColor(white: 0.03, alpha: 1))
        Draw.circle(ctx, CGPoint(x: x, y: y - r.height * 0.068), r.width * 0.007, NSColor(white: 0.03, alpha: 1))
    }

    static func cat(_ r: CGRect, _ ctx: CGContext) {
        Draw.gradient(ctx, r, Draw.hex(0xC9B79C), Draw.hex(0x8C7A63))
        Draw.fill(ctx, CGRect(x: r.minX, y: r.minY + r.height * 0.7, width: r.width, height: r.height * 0.3), Draw.hex(0x6B5845))
        // doorway, dark
        Draw.fill(ctx, CGRect(x: r.maxX - r.width * 0.3, y: r.minY + r.height * 0.1, width: r.width * 0.2, height: r.height * 0.6), Draw.hex(0x15110E))
        // cat, staring at the doorway
        let c = CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.72)
        ctx.setFillColor(Draw.hex(0x222222).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r.width * 0.12, y: c.y - r.height * 0.18, width: r.width * 0.24, height: r.height * 0.2))
        ctx.fillEllipse(in: CGRect(x: c.x + r.width * 0.04, y: c.y - r.height * 0.3, width: r.width * 0.12, height: r.height * 0.13))
        let ear = CGMutablePath()
        ear.move(to: CGPoint(x: c.x + r.width * 0.06, y: c.y - r.height * 0.27))
        ear.addLine(to: CGPoint(x: c.x + r.width * 0.07, y: c.y - r.height * 0.35))
        ear.addLine(to: CGPoint(x: c.x + r.width * 0.1, y: c.y - r.height * 0.28))
        ear.move(to: CGPoint(x: c.x + r.width * 0.11, y: c.y - r.height * 0.28))
        ear.addLine(to: CGPoint(x: c.x + r.width * 0.15, y: c.y - r.height * 0.35))
        ear.addLine(to: CGPoint(x: c.x + r.width * 0.155, y: c.y - r.height * 0.26))
        ctx.addPath(ear)
        ctx.fillPath()
        // two pale points in the doorway
        Draw.circle(ctx, CGPoint(x: r.maxX - r.width * 0.215, y: r.minY + r.height * 0.3), r.width * 0.006, NSColor(white: 0.9, alpha: 0.8))
        Draw.circle(ctx, CGPoint(x: r.maxX - r.width * 0.185, y: r.minY + r.height * 0.3), r.width * 0.006, NSColor(white: 0.9, alpha: 0.8))
    }

    /// Fridge door with magnet letters. The bright ones spell LUMEN.
    static func fridge(_ r: CGRect, _ ctx: CGContext) {
        Draw.gradient(ctx, r, Draw.hex(0xEDEFF2), Draw.hex(0xCDD1D6))
        Draw.fill(ctx, CGRect(x: r.minX + r.width * 0.86, y: r.minY + r.height * 0.2, width: r.width * 0.03, height: r.height * 0.5),
                  Draw.hex(0xA9AEB5), radius: r.width * 0.01)
        Draw.line(ctx, CGPoint(x: r.minX, y: r.minY + r.height * 0.08), CGPoint(x: r.maxX, y: r.minY + r.height * 0.08), Draw.hex(0xB8BCC2), width: 2)
        let letters: [(String, CGFloat, CGFloat, UInt32, CGFloat)] = [
            ("L", 0.2, 0.4, 0xE0322B, -0.12), ("U", 0.32, 0.43, 0x2E7CF6, 0.08), ("M", 0.45, 0.39, 0xF5B400, -0.05),
            ("E", 0.59, 0.44, 0x28C840, 0.1), ("N", 0.71, 0.4, 0x9B59D0, -0.08),
            ("a", 0.25, 0.72, 0x8E8E93, 0.3), ("x", 0.55, 0.78, 0x8E8E93, -0.2), ("o", 0.68, 0.7, 0x8E8E93, 0.1), ("k", 0.12, 0.62, 0x8E8E93, -0.3),
        ]
        for (l, x, y, col, a) in letters {
            ctx.saveGState()
            ctx.translateBy(x: r.minX + r.width * x, y: r.minY + r.height * y)
            ctx.rotate(by: a)
            ctx.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: NSColor(white: 0, alpha: 0.35).cgColor)
            Draw.text(l, at: CGPoint(x: -r.height * 0.06, y: -r.height * 0.09), font: NSFont.systemFont(ofSize: r.height * 0.16, weight: .black), color: Draw.hex(col))
            ctx.restoreGState()
        }
        // a note under a magnet
        ctx.saveGState()
        ctx.translateBy(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.6)
        ctx.rotate(by: 0.06)
        Draw.fill(ctx, CGRect(x: 0, y: 0, width: r.width * 0.2, height: r.height * 0.22), Draw.hex(0xFFF3A6))
        Draw.text("vet thurs\nmilk\ncall mom", at: CGPoint(x: r.width * 0.015, y: r.height * 0.02), font: Draw.hand(r.height * 0.04), color: Draw.hex(0x333366))
        ctx.restoreGState()
    }

    /// Two people on a sofa. One face is scratched out.
    static func us(_ r: CGRect, _ ctx: CGContext) {
        Draw.gradient(ctx, r, Draw.hex(0xE9B98A), Draw.hex(0xA8714E))
        Draw.fill(ctx, CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.55, width: r.width * 0.76, height: r.height * 0.3), Draw.hex(0x5B6B7A), radius: r.height * 0.05)
        for (dx, col) in [(0.38, 0x3B2A24), (0.6, 0x2A2A33)] as [(CGFloat, UInt32)] {
            let x = r.minX + r.width * dx
            Draw.fill(ctx, CGRect(x: x - r.width * 0.07, y: r.minY + r.height * 0.42, width: r.width * 0.14, height: r.height * 0.3), Draw.hex(col), radius: r.width * 0.04)
            Draw.circle(ctx, CGPoint(x: x, y: r.minY + r.height * 0.34), r.width * 0.055, Draw.hex(0xE8C3A0))
        }
        // scratches over the second face
        let c = CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.34)
        for i in 0..<14 {
            let a = CGFloat(i) * 0.37
            Draw.line(ctx, CGPoint(x: c.x - cos(a) * r.width * 0.07, y: c.y - sin(a) * r.width * 0.06),
                      CGPoint(x: c.x + cos(a + 0.4) * r.width * 0.07, y: c.y + sin(a + 0.4) * r.width * 0.06), Draw.hex(0x111111), width: 2.2)
        }
    }

    static func tooth(_ r: CGRect, _ ctx: CGContext) {
        Draw.fill(ctx, r, Draw.hex(0x15151A))
        let c = CGPoint(x: r.midX, y: r.midY)
        let s = r.height * 0.25
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - s, y: c.y - s * 0.6))
        p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y - s * 0.6), control: CGPoint(x: c.x, y: c.y - s * 1.3))
        p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s))
        p.addLine(to: CGPoint(x: c.x + s * 0.2, y: c.y + s * 0.4))
        p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.4))
        p.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y + s))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(Draw.hex(0xF1EDE3).cgColor)
        ctx.fillPath()
    }

    static func window(_ r: CGRect, _ ctx: CGContext) {
        Draw.fill(ctx, r, Draw.hex(0x0B0D14))
        let w = CGRect(x: r.midX - r.width * 0.22, y: r.minY + r.height * 0.15, width: r.width * 0.44, height: r.height * 0.6)
        Draw.gradient(ctx, w, Draw.hex(0x1C2740), Draw.hex(0x0F1626))
        Draw.line(ctx, CGPoint(x: w.midX, y: w.minY), CGPoint(x: w.midX, y: w.maxY), Draw.hex(0x2A2A2A), width: r.width * 0.01)
        Draw.line(ctx, CGPoint(x: w.minX, y: w.midY), CGPoint(x: w.maxX, y: w.midY), Draw.hex(0x2A2A2A), width: r.width * 0.01)
        // a handprint on the glass
        let h = CGPoint(x: w.minX + w.width * 0.28, y: w.minY + w.height * 0.68)
        ctx.setFillColor(NSColor(white: 0.8, alpha: 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: h.x - r.width * 0.03, y: h.y - r.width * 0.03, width: r.width * 0.06, height: r.width * 0.07))
        for i in 0..<5 {
            let a = -0.9 + CGFloat(i) * 0.38
            let fx = h.x + cos(a - .pi / 2) * r.width * 0.06
            let fy = h.y + sin(a - .pi / 2) * r.width * 0.06
            ctx.fillEllipse(in: CGRect(x: fx - r.width * 0.008, y: fy - r.width * 0.02, width: r.width * 0.016, height: r.width * 0.04))
        }
    }
}
