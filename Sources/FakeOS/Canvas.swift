import AppKit
import Metal

enum GPU {
    static var device: MTLDevice!
    static var queue: MTLCommandQueue!
}

/// A Core Graphics bitmap (top-left origin, in points) mirrored into a Metal texture.
/// All the fake OS chrome and text is painted into canvases, then composited by Metal.
final class Canvas {
    let size: CGSize
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let ctx: CGContext
    let texture: MTLTexture
    let mipmapped: Bool

    init(size: CGSize, scale: CGFloat, mipmapped: Bool = false) {
        self.size = CGSize(width: max(1, size.width), height: max(1, size.height))
        self.scale = scale
        self.mipmapped = mipmapped
        pixelWidth = max(1, Int(ceil(self.size.width * scale)))
        pixelHeight = max(1, Int(ceil(self.size.height * scale)))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                        bytesPerRow: pixelWidth * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldSmoothFonts(false)
        ctx.interpolationQuality = .high

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pixelWidth,
                                                            height: pixelHeight, mipmapped: mipmapped)
        desc.usage = [.shaderRead]
        desc.storageMode = GPU.device.hasUnifiedMemory ? .shared : .managed
        texture = GPU.device.makeTexture(descriptor: desc)!
    }

    /// Clear, run the drawing closure with an AppKit graphics context installed, then upload.
    func draw(_ body: (CGContext) -> Void) {
        ctx.saveGState()
        ctx.clear(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
        upload()
    }

    private func upload() {
        guard let data = ctx.data else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0,
                        withBytes: data, bytesPerRow: pixelWidth * 4)
        if mipmapped, let cb = GPU.queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cb.commit()
        }
    }
}
