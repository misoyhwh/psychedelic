import Metal
import RealityKit
import CoreGraphics
import CoreVideo

struct PsychedelicParams {
    var time: Float
    var speed: Float
    var intensity: Float
    var styleIndex: Int32
    var width: Int32
    var height: Int32
    var hasVideoTexture: Int32
    var historyCount: Int32
}

@MainActor
class TextureGenerator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let textureSize = 256
    private var lowLevelTexture: LowLevelTexture?
    private(set) var textureResource: TextureResource?
    /// 動画フレーム (CVPixelBuffer) を MTLTexture 化するためのキャッシュ (Video Kaleido/Tunnel 用)
    private var videoTextureCache: CVMetalTextureCache?
    /// 静止画 (スライドショー) の変換キャッシュ。同じ CGImage インスタンスの間は再変換しない。
    private var cachedStillTexture: MTLTexture?
    private var cachedStillImageID: ObjectIdentifier?

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

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)

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

    /// 静止画 (スライド) を ≤1024px の RGBA8 MTLTexture に変換する。1 スライドにつき 1 回だけ。
    private func stillTexture(for image: CGImage) -> MTLTexture? {
        let id = ObjectIdentifier(image)
        if cachedStillImageID == id, let cachedStillTexture {
            return cachedStillTexture
        }
        let maxDim = 1024
        let scale = min(CGFloat(maxDim) / CGFloat(image.width), CGFloat(maxDim) / CGFloat(image.height), 1.0)
        let w = max(Int(CGFloat(image.width) * scale), 1)
        let h = max(Int(CGFloat(image.height) * scale), 1)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: w * 4
        )
        cachedStillTexture = texture
        cachedStillImageID = id
        return texture
    }

    func updateTexture(
        time: Float,
        speed: Float,
        intensity: Float,
        styleIndex: Int,
        videoPixelBuffer: CVPixelBuffer? = nil,
        stillImage: CGImage? = nil,
        colorHistory: [SIMD3<Float>] = []
    ) {
        guard let lowLevelTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let mtlTexture = lowLevelTexture.replace(using: commandBuffer)

        // 動画フレームを MTLTexture 化 (Video Kaleido / Tunnel 用)。
        // CVMetalTexture は GPU が読み終わるまで生かす必要があるため completed handler で保持する。
        var videoMTLTexture: MTLTexture? = nil
        if let buffer = videoPixelBuffer,
           let cache = videoTextureCache,
           CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA {
            var cvTexture: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture
            )
            if result == kCVReturnSuccess, let cvTexture {
                videoMTLTexture = CVMetalTextureGetTexture(cvTexture)
                commandBuffer.addCompletedHandler { _ in
                    _ = cvTexture  // GPU 完了までテクスチャの寿命を保証
                }
            }
        }

        // 動画フレームが無ければ静止画 (スライド) をソースにする
        if videoMTLTexture == nil, let stillImage {
            videoMTLTexture = stillTexture(for: stillImage)
        }

        var params = PsychedelicParams(
            time: time,
            speed: speed,
            intensity: intensity,
            styleIndex: Int32(styleIndex),
            width: Int32(textureSize),
            height: Int32(textureSize),
            hasVideoTexture: videoMTLTexture != nil ? 1 : 0,
            historyCount: Int32(colorHistory.count)
        )

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(mtlTexture, index: 0)
        encoder.setTexture(videoMTLTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<PsychedelicParams>.stride, index: 0)

        // 色履歴 (Video Ripple 用)。空でもダミー 1 要素をバインドしてシェーダ引数を満たす。
        var history = colorHistory
        if history.isEmpty {
            history = [SIMD3<Float>(0.1, 0.1, 0.1)]
        }
        history.withUnsafeBytes { raw in
            encoder.setBytes(raw.baseAddress!, length: raw.count, index: 1)
        }

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
