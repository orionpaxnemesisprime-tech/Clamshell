// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import MetalKit

/// Draws the two emulated screens into an `MTKView` at the rects of a `ScreenLayout`.
///
/// Frames come from a `FrameStore`, so drawing never waits on the emulation thread. Each of
/// the three in-flight frames has its own pair of textures, so the CPU never writes a texture
/// the GPU may still be sampling.
final class DualScreenRenderer: NSObject, MTKViewDelegate {
    private static let maxFramesInFlight = 3

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let nearest: MTLSamplerState
    private let linear: MTLSamplerState
    private let textureSets: [(top: MTLTexture, bottom: MTLTexture)]
    private var uploadedGeneration: [UInt64]
    private var setIndex = 0
    private let inFlight = DispatchSemaphore(value: maxFramesInFlight)

    var frames: FrameStore?
    var layout = ScreenLayout(top: .zero, bottom: .zero)

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Screens"
        descriptor.vertexFunction = library.makeFunction(name: "screen_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "screen_fragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        func sampler(_ filter: MTLSamplerMinMagFilter) -> MTLSamplerState? {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = filter
            descriptor.magFilter = filter
            return device.makeSamplerState(descriptor: descriptor)
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: ScreenFrame.width, height: ScreenFrame.height, mipmapped: false)
        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .shared

        var sets: [(MTLTexture, MTLTexture)] = []
        for _ in 0..<Self.maxFramesInFlight {
            guard let top = device.makeTexture(descriptor: textureDescriptor),
                  let bottom = device.makeTexture(descriptor: textureDescriptor)
            else { return nil }
            sets.append((top, bottom))
        }
        guard let nearest = sampler(.nearest), let linear = sampler(.linear) else { return nil }

        commandQueue = queue
        self.pipeline = pipeline
        self.nearest = nearest
        self.linear = linear
        textureSets = sets
        uploadedGeneration = Array(repeating: 0, count: Self.maxFramesInFlight)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        inFlight.wait()
        let index = setIndex
        setIndex = (setIndex + 1) % Self.maxFramesInFlight
        let textures = textureSets[index]

        // Bring this set up to date with the newest emulated frame, if it is behind.
        if let frames {
            let region = MTLRegionMake2D(0, 0, ScreenFrame.width, ScreenFrame.height)
            let bytesPerRow = ScreenFrame.width * MemoryLayout<UInt32>.size
            if let generation = frames.withLatestFrame(newerThan: uploadedGeneration[index], { top, bottom, generation in
                textures.top.replace(region: region, mipmapLevel: 0, withBytes: top.baseAddress!, bytesPerRow: bytesPerRow)
                textures.bottom.replace(region: region, mipmapLevel: 0, withBytes: bottom.baseAddress!, bytesPerRow: bytesPerRow)
                return generation
            }) {
                uploadedGeneration[index] = generation
            }
        }

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else {
            inFlight.signal()
            return
        }

        if uploadedGeneration[index] > 0 {
            let scale = view.contentScaleFactor
            encoder.setRenderPipelineState(pipeline)
            for (rect, texture) in [(layout.top, textures.top), (layout.bottom, textures.bottom)] where !rect.isEmpty {
                let pixelScale = rect.width * scale / CGFloat(ScreenFrame.width)
                let isInteger = abs(pixelScale - pixelScale.rounded()) < 0.01
                encoder.setViewport(MTLViewport(originX: rect.minX * scale, originY: rect.minY * scale,
                                                width: rect.width * scale, height: rect.height * scale,
                                                znear: 0, zfar: 1))
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(isInteger ? nearest : linear, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        encoder.endEncoding()

        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
