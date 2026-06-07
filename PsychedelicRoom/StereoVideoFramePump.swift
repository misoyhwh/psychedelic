import RealityKit
import AVFoundation
import Metal
import CoreVideo
import CoreMedia
import QuartzCore
import Vision
import CoreImage

/// 立体視動画(MV-HEVC)の左右フレームを毎フレーム取り出し、2枚の TextureResource を更新する。
/// VideoMaterial では透過シェーダを被せられないため、ここで自前テクスチャ化して
/// StereoImageMaterial(LeftImage/RightImage) に流す。
///
/// CoreMedia の tagged buffer 抽出は Swift から呼べないため、左右の CVPixelBuffer 取り出しは
/// Objective-C シム([StereoFrameExtractor])に委譲している。
@MainActor
final class StereoVideoFramePump {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?

    private var output: AVPlayerVideoOutput?
    private weak var player: AVPlayer?
    private var displayLink: CADisplayLink?

    private var leftLLT: LowLevelTexture?
    private var rightLLT: LowLevelTexture?
    private(set) var leftTexture: TextureResource?
    private(set) var rightTexture: TextureResource?
    private var textureSize: (w: Int, h: Int)?

    /// 最初のフレームでテクスチャが用意できた時に 1 回呼ばれる。マテリアルへのバインドに使う。
    var onTexturesReady: (() -> Void)?

    // 前景抽出 (Vision)。重いので数フレームに1回・非同期生成。左右個別にマスクを作る (視差に沿った縁)。
    var foregroundEnabled = false
    private(set) var maskLeftTexture: TextureResource?
    private(set) var maskRightTexture: TextureResource?
    /// マスクが更新された時に呼ばれる。マテリアルへの再バインドに使う。
    var onMaskUpdated: (() -> Void)?
    private var frameCounter = 0
    private var maskInFlight = false
    private let maskInterval = 6 // 約 N 表示フレームに1回マスク生成

    var isActive: Bool { output != nil }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    // MARK: - Lifecycle

    func attach(to player: AVPlayer) {
        detach()
        guard let output = StereoFrameExtractor.makeStereoscopicOutput() else {
            print("StereoVideoFramePump: failed to create stereoscopic AVPlayerVideoOutput")
            return
        }
        player.videoOutput = output
        self.output = output
        self.player = player
        startDisplayLink()
    }

    func detach() {
        displayLink?.invalidate()
        displayLink = nil
        if let player, player.videoOutput === output {
            player.videoOutput = nil
        }
        output = nil
        player = nil
        leftLLT = nil
        rightLLT = nil
        leftTexture = nil
        rightTexture = nil
        textureSize = nil
        maskLeftTexture = nil
        maskRightTexture = nil
        frameCounter = 0
    }

    private func startDisplayLink() {
        let target = DisplayLinkTarget { [weak self] in
            Task { @MainActor in self?.step() }
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        displayLink = link
    }

    // MARK: - Per-frame

    private func step() {
        guard let output, let cache = textureCache else { return }
        // 前フレームのキャッシュテクスチャを回収 (GPU 完了済みのもののみ解放される)。
        CVMetalTextureCacheFlush(cache, 0)
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        guard let pair = StereoFrameExtractor.copyStereoFrame(from: output, hostTime: hostTime) else {
            return // 新規フレーム無し
        }
        let left = pair.left
        let right = pair.right ?? pair.left // モノラルは両眼へ同一フレーム

        // 最初のフレームでサイズ確定 → テクスチャ生成 → バインド通知。
        if textureSize == nil, let left {
            let w = CVPixelBufferGetWidth(left)
            let h = CVPixelBufferGetHeight(left)
            createTextures(width: w, height: h)
            onTexturesReady?()
        }

        if let left { updateTexture(leftLLT, from: left) }
        if let right { updateTexture(rightLLT, from: right) }

        maybeGenerateMask(left: left, right: pair.right)
    }

    // MARK: - Foreground mask (throttled, async, per-eye)

    private func maybeGenerateMask(left: CVPixelBuffer?, right: CVPixelBuffer?) {
        guard foregroundEnabled, let left else { return }
        frameCounter &+= 1
        guard frameCounter % maskInterval == 0, !maskInFlight else { return }
        maskInFlight = true
        nonisolated(unsafe) let lb = left
        nonisolated(unsafe) let rb = right
        // 外側は MainActor (self 触れる)、Vision (左右2回) だけ detached でバックグラウンドへ。
        Task { [weak self] in
            let masks = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?) in
                let l = StereoVideoFramePump.computeMaskCGImage(from: lb)
                let r: CGImage?
                if let rb { r = StereoVideoFramePump.computeMaskCGImage(from: rb) } else { r = nil }
                return (l, r)
            }.value
            var lt: TextureResource?
            var rt: TextureResource?
            if let lcg = masks.0 {
                lt = try? await TextureResource(image: lcg, options: .init(semantic: .raw))
            }
            if let rcg = masks.1 {
                rt = try? await TextureResource(image: rcg, options: .init(semantic: .raw))
            }
            guard let self else { return }
            if lt != nil || rt != nil {
                self.maskLeftTexture = lt
                self.maskRightTexture = rt
                self.onMaskUpdated?()
            }
            self.maskInFlight = false
        }
    }

    /// 被写体マスクを生成して CGImage で返す。重い同期処理 (バックグラウンドで呼ぶこと)。
    nonisolated private static func computeMaskCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        let context = CIContext(options: nil)
        // ~1024px に縮小して Vision コストを抑える。
        let ci = CIImage(cvPixelBuffer: buffer)
        let maxDim = max(ci.extent.width, ci.extent.height)
        let scale = maxDim > 1024 ? 1024.0 / maxDim : 1.0
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let mci = CIImage(cvPixelBuffer: mask)
            return context.createCGImage(mci, from: mci.extent)
        } catch {
            return nil
        }
    }

    private func createTextures(width: Int, height: Int) {
        textureSize = (width, height)
        leftLLT = makeLowLevelTexture(width: width, height: height)
        rightLLT = makeLowLevelTexture(width: width, height: height)
        if let leftLLT { leftTexture = try? TextureResource(from: leftLLT) }
        if let rightLLT { rightTexture = try? TextureResource(from: rightLLT) }
    }

    private func makeLowLevelTexture(width: Int, height: Int) -> LowLevelTexture? {
        var desc = LowLevelTexture.Descriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .bgra8Unorm
        desc.width = width
        desc.height = height
        desc.depth = 1
        desc.mipmapLevelCount = 1
        desc.textureUsage = [.shaderRead, .shaderWrite]
        return try? LowLevelTexture(descriptor: desc)
    }

    private func updateTexture(_ llt: LowLevelTexture?, from pixelBuffer: CVPixelBuffer) {
        guard let llt, let cache = textureCache else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, w, h, 0, &cvTexture)
        guard result == kCVReturnSuccess,
              let cvTexture,
              let src = CVMetalTextureGetTexture(cvTexture),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let dst = llt.replace(using: commandBuffer)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let copyW = min(w, dst.width)
        let copyH = min(h, dst.height)
        blit.copy(
            from: src,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: copyW, height: copyH, depth: 1),
            to: dst,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        // src(MTLTexture) は commit 済みコマンドバッファが GPU 完了まで保持するため、
        // ここで cvTexture が解放されても描画は安全。
        withExtendedLifetime(cvTexture) {}
    }
}

// MARK: - CADisplayLink target

private final class DisplayLinkTarget: NSObject {
    private let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    @objc func tick(_ link: CADisplayLink) { callback() }
}
