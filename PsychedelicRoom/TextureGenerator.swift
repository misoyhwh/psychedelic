import Metal
import RealityKit
import CoreGraphics

struct PsychedelicParams {
    var time: Float
    var speed: Float
    var intensity: Float
    var styleIndex: Int32
    var width: Int32
    var height: Int32
}

@MainActor
class TextureGenerator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let textureSize = 256
    private var lowLevelTexture: LowLevelTexture?
    private(set) var textureResource: TextureResource?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "generatePsychedelicTexture"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }
        self.pipelineState = pipeline

        setupLowLevelTexture()
    }

    private func setupLowLevelTexture() {
        do {
            var desc = LowLevelTexture.Descriptor()
            desc.textureType = .type2D
            desc.pixelFormat = .rgba8Unorm
            desc.width = textureSize
            desc.height = textureSize
            desc.depth = 1
            desc.mipmapLevelCount = 1
            desc.textureUsage = [.shaderRead, .shaderWrite]

            let llt = try LowLevelTexture(descriptor: desc)
            self.lowLevelTexture = llt
            self.textureResource = try TextureResource(from: llt)
        } catch {
            print("Failed to create LowLevelTexture: \(error)")
        }
    }

    func updateTexture(time: Float, speed: Float, intensity: Float, styleIndex: Int) {
        guard let lowLevelTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let mtlTexture = lowLevelTexture.replace(using: commandBuffer)

        var params = PsychedelicParams(
            time: time,
            speed: speed,
            intensity: intensity,
            styleIndex: Int32(styleIndex),
            width: Int32(textureSize),
            height: Int32(textureSize)
        )

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(mtlTexture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<PsychedelicParams>.stride, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (textureSize + 15) / 16,
            height: (textureSize + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        // Non-blocking: GPU processes asynchronously, LowLevelTexture updates automatically
    }
}
