import AppKit
import MetalKit
import simd

struct Uniforms {
    var a = SIMD4<Float>(0, 0, 0, 0)
    var b = SIMD4<Float>(0, 1, 0, 0)
    var c = SIMD4<Float>(0, 0, 0, 1)
    var d = SIMD4<Float>(0, 0, 0, 0)
}

struct QuadData {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var uv: SIMD4<Float>
    var params: SIMD4<Float>
}

typealias RGBA = SIMD4<Float>

extension SIMD4 where Scalar == Float {
    static func rgba(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) -> RGBA { RGBA(r, g, b, a) }
    static let white = RGBA(1, 1, 1, 1)
}

/// Immediate-mode compositor: the world queues quads each frame, then they are drawn into an
/// offscreen scene texture which a post-process pass distorts (glitches, brightness, ghost writing).
final class Renderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private var quadPipeline: MTLRenderPipelineState!
    private var postPipeline: MTLRenderPipelineState!
    private var sampler: MTLSamplerState!
    private var sceneTex: MTLTexture?
    private var whiteTex: MTLTexture!
    private var lastCommandBuffer: MTLCommandBuffer?

    private struct Cmd {
        var data: QuadData
        var texture: MTLTexture?
    }
    private var cmds: [Cmd] = []
    var uniforms = Uniforms()
    var ghostTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
        queue = device.makeCommandQueue()!
        GPU.device = device
        GPU.queue = queue
        buildPipelines()
    }

    private func buildPipelines() {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            fatalError("Shader compile failed: \(error)")
        }
        let q = MTLRenderPipelineDescriptor()
        q.vertexFunction = library.makeFunction(name: "quad_vs")
        q.fragmentFunction = library.makeFunction(name: "quad_fs")
        q.colorAttachments[0].pixelFormat = .bgra8Unorm
        q.colorAttachments[0].isBlendingEnabled = true
        q.colorAttachments[0].sourceRGBBlendFactor = .one
        q.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        q.colorAttachments[0].sourceAlphaBlendFactor = .one
        q.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        quadPipeline = try! device.makeRenderPipelineState(descriptor: q)

        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = library.makeFunction(name: "post_vs")
        p.fragmentFunction = library.makeFunction(name: "post_fs")
        p.colorAttachments[0].pixelFormat = .bgra8Unorm
        postPipeline = try! device.makeRenderPipelineState(descriptor: p)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)

        let wd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        whiteTex = device.makeTexture(descriptor: wd)
        var px: UInt32 = 0xFFFF_FFFF
        whiteTex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
    }

    /// Called before the world mutates canvases, so we never overwrite a texture the GPU is reading.
    func waitForGPU() {
        lastCommandBuffer?.waitUntilCompleted()
    }

    // MARK: - Queueing

    private func r4(_ r: CGRect) -> SIMD4<Float> {
        SIMD4(Float(r.minX), Float(r.minY), Float(r.width), Float(r.height))
    }

    func quad(_ rect: CGRect, _ color: RGBA, radius: CGFloat = 0, alpha: Float = 1) {
        cmds.append(Cmd(data: QuadData(rect: r4(rect), color: color, uv: SIMD4(0, 0, 1, 1),
                                       params: SIMD4(Float(radius), 0, 0, alpha)), texture: nil))
    }

    func image(_ canvas: Canvas, _ rect: CGRect, radius: CGFloat = 0, alpha: Float = 1, tint: RGBA = .white) {
        cmds.append(Cmd(data: QuadData(rect: r4(rect), color: tint, uv: SIMD4(0, 0, 1, 1),
                                       params: SIMD4(Float(radius), 1, 0, alpha)), texture: canvas.texture))
    }

    func shadow(_ rect: CGRect, radius: CGFloat, blur: CGFloat, opacity: Float) {
        cmds.append(Cmd(data: QuadData(rect: r4(rect), color: SIMD4(0, 0, 0, opacity), uv: SIMD4(0, 0, 1, 1),
                                       params: SIMD4(Float(radius), 2, Float(blur), 1)), texture: nil))
    }

    func frosted(_ rect: CGRect, tint: RGBA, radius: CGFloat, alpha: Float = 1) {
        cmds.append(Cmd(data: QuadData(rect: r4(rect), color: tint, uv: SIMD4(0, 0, 1, 1),
                                       params: SIMD4(Float(radius), 3, 0, alpha)), texture: nil))
    }

    func wallpaper(_ rect: CGRect, alpha: Float = 1) {
        cmds.append(Cmd(data: QuadData(rect: r4(rect), color: .white, uv: SIMD4(0, 0, 1, 1),
                                       params: SIMD4(0, 4, 0, alpha)), texture: nil))
    }

    // MARK: - Frame

    func render(world: World, in view: MTKView) {
        cmds.removeAll(keepingCapacity: true)
        world.draw(self)

        guard let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }

        let w = drawable.texture.width, h = drawable.texture.height
        if sceneTex == nil || sceneTex!.width != w || sceneTex!.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            sceneTex = device.makeTexture(descriptor: d)
        }

        // Scene pass
        let sp = MTLRenderPassDescriptor()
        sp.colorAttachments[0].texture = sceneTex
        sp.colorAttachments[0].loadAction = .clear
        sp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        sp.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: sp) {
            enc.setRenderPipelineState(quadPipeline)
            enc.setFragmentSamplerState(sampler, index: 0)
            var u = uniforms
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            for var c in cmds {
                enc.setVertexBytes(&c.data, length: MemoryLayout<QuadData>.stride, index: 0)
                enc.setFragmentBytes(&c.data, length: MemoryLayout<QuadData>.stride, index: 0)
                enc.setFragmentTexture(c.texture ?? whiteTex, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            enc.endEncoding()
        }

        // Post pass
        if let enc = cb.makeRenderCommandEncoder(descriptor: passDesc) {
            enc.setRenderPipelineState(postPipeline)
            var u = uniforms
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.setFragmentTexture(sceneTex, index: 0)
            enc.setFragmentTexture(ghostTexture ?? whiteTex, index: 1)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        cb.present(drawable)
        cb.commit()
        lastCommandBuffer = cb
    }
}
