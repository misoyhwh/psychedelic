import SwiftUI
import AVFoundation
import CoreVideo
import RealityKit
import RealityKitContent

@Observable
@MainActor
class MediaPanelViewModel {
    // MARK: - Video Panel
    var videoEnabled: Bool = false
    var videoURL: URL? = nil
    var isVideoPlaying: Bool = false
    var videoSize: CGSize = CGSize(width: 1.92, height: 1.08)
    var videoRotationH: Float = 0
    var videoRotationV: Float = 0
    var videoBobEnabled: Bool = false
    var videoBobAmplitude: Float = 0.3    // vertical meters (0.05...1.0)
    var videoBobSpeed: Float = 0.2        // cycles per second (0.02...0.5)
    var videoSurgeEnabled: Bool = false
    var videoSurgeAmplitude: Float = 0.3  // forward/back meters (0.05...1.0)
    var videoSurgeSpeed: Float = 0.2      // cycles per second (0.02...0.5)
    var videoSwayEnabled: Bool = false
    var videoSwayAmplitude: Float = 0.3   // left/right meters (0.05...1.0)
    var videoSwaySpeed: Float = 0.2       // cycles per second (0.02...0.5)
    var videoVersion: Int = 0

    var videoCurrentTime: Double = 0
    var videoDuration: Double = 0
    var isSeeking: Bool = false

    // Video color sampling
    var videoColorTop: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var videoColorMiddle: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var videoColorBottom: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    var player: AVPlayer?
    private var videoAccessedURL: URL?
    private var loopObserver: Any?
    private var timeObserver: Any?
    private var videoOutput: AVPlayerItemVideoOutput?

    // Slideshow color sampling
    var slideshowColorTop: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var slideshowColorMiddle: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var slideshowColorBottom: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    // MARK: - Slideshow Panel
    var slideshowEnabled: Bool = false
    var slideshowFolderURL: URL? = nil
    var slideshowImages: [SlideshowImage] = []
    var slideshowCurrentIndex: Int = 0
    var slideshowIsPlaying: Bool = false
    var slideshowInterval: Float = 5.0
    var slideshowRotationH: Float = 0
    var slideshowRotationV: Float = 0
    var slideshowTexture: TextureResource?
    var slideshowRightTexture: TextureResource?
    var slideshowIsStereo: Bool = false
    var slideshowDisplaySize: CGSize = CGSize(width: 1.92, height: 1.08)
    var slideshowTextureVersion: Int = 0

    private var slideshowAccessedURL: URL?
    private var slideshowTimer: Timer?
    private var slideshowLoadTask: Task<Void, Never>?

    // MARK: - Video Methods

    func loadVideo(url: URL) {
        // Release previous security-scoped resource
        if let prev = videoAccessedURL {
            prev.stopAccessingSecurityScopedResource()
        }

        let accessing = url.startAccessingSecurityScopedResource()
        if accessing {
            videoAccessedURL = url
        }

        // Clean up old player BEFORE creating new one
        cleanupPlayer()

        videoURL = url
        let item = AVPlayerItem(url: url)

        // Add video output for color sampling
        let outputAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputAttrs)
        item.add(output)
        videoOutput = output

        let newPlayer = AVPlayer(playerItem: item)

        // Loop observer
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        // Time observer for seek bar
        videoCurrentTime = 0
        videoDuration = 0
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isSeeking else { return }
                self.videoCurrentTime = time.seconds
                if let duration = self.player?.currentItem?.duration, duration.isNumeric {
                    self.videoDuration = duration.seconds
                }
                self.sampleVideoColors()
            }
        }

        // Set player AFTER observers are configured
        self.player = newPlayer

        // Immediately signal entity creation with default 16:9 size
        videoVersion += 1

        // Then update size asynchronously and recreate with correct aspect ratio
        Task {
            await loadVideoSize(from: item)
            videoVersion += 1
        }
    }

    private func cleanupPlayer() {
        // Remove video output
        if let output = videoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        videoOutput = nil

        // Remove time observer from OLD player
        if let obs = timeObserver, let oldPlayer = player {
            oldPlayer.removeTimeObserver(obs)
        }
        timeObserver = nil

        // Remove loop observer
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        loopObserver = nil

        // Stop old player
        player?.pause()
        player = nil
        isVideoPlaying = false
    }

    func playVideo() {
        player?.play()
        isVideoPlaying = true
    }

    func pauseVideo() {
        player?.pause()
        isVideoPlaying = false
    }

    func stopVideo() {
        player?.pause()
        player?.seek(to: .zero)
        isVideoPlaying = false
        videoCurrentTime = 0
    }

    func seekVideo(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loadVideoSize(from item: AVPlayerItem) async {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = naturalSize.applying(transform)
            let w = abs(transformed.width)
            let h = abs(transformed.height)
            guard w > 0, h > 0 else { return }
            let maxDim: CGFloat = 2.0
            let scale = min(maxDim / w, maxDim / h)
            videoSize = CGSize(width: w * scale, height: h * scale)
        } catch {
            print("Failed to load video size: \(error)")
        }
    }

    // MARK: - Video Color Sampling

    private func sampleVideoColors() {
        guard let output = videoOutput, let player = player else { return }
        let time = player.currentTime()

        // Use autoreleasepool to ensure timely release of large pixel buffers
        autoreleasepool {
            guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

            // Verify pixel format is BGRA (spatial/MV-HEVC may use different formats)
            let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
            guard pixelFormat == kCVPixelFormatType_32BGRA else { return }

            // Reject planar buffers (MV-HEVC may return multi-plane buffers)
            guard !CVPixelBufferIsPlanar(buffer) else { return }

            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let bpr = CVPixelBufferGetBytesPerRow(buffer)
            guard w > 0, h > 0, bpr >= w * 4 else { return }

            let bufferSize = bpr * h

            // Top edge center strip → ceiling
            let sampledTop = sampleRegionColor(base, bpr: bpr, w: w, h: h, bufferSize: bufferSize, cx: w / 2, cy: 2, rx: w / 4, ry: 2)
            // Right edge middle strip → walls
            let sampledMiddle = sampleRegionColor(base, bpr: bpr, w: w, h: h, bufferSize: bufferSize, cx: w - 3, cy: h / 2, rx: 2, ry: h / 4)
            // Bottom edge center strip → floor
            let sampledBottom = sampleRegionColor(base, bpr: bpr, w: w, h: h, bufferSize: bufferSize, cx: w / 2, cy: h - 3, rx: w / 4, ry: 2)

            // Smooth transition
            let blend: Float = 0.3
            videoColorTop = videoColorTop * (1.0 - blend) + sampledTop * blend
            videoColorMiddle = videoColorMiddle * (1.0 - blend) + sampledMiddle * blend
            videoColorBottom = videoColorBottom * (1.0 - blend) + sampledBottom * blend
        }
    }

    private func sampleRegionColor(_ base: UnsafeMutableRawPointer, bpr: Int, w: Int, h: Int,
                                    bufferSize: Int,
                                    cx: Int, cy: Int, rx: Int, ry: Int) -> SIMD3<Float> {
        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0
        var count: Float = 0
        let stepX = max(1, rx / 4)
        let stepY = max(1, ry / 4)
        for dy in stride(from: -ry, through: ry, by: stepY) {
            for dx in stride(from: -rx, through: rx, by: stepX) {
                let x = min(max(cx + dx, 0), w - 1)
                let y = min(max(cy + dy, 0), h - 1)
                let offset = y * bpr + x * 4
                // Bounds check to prevent out-of-range access
                guard offset >= 0, offset + 3 < bufferSize else { continue }
                let ptr = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                // BGRA format
                bSum += Float(ptr[0]) / 255.0
                gSum += Float(ptr[1]) / 255.0
                rSum += Float(ptr[2]) / 255.0
                count += 1
            }
        }
        guard count > 0 else { return SIMD3<Float>(0.1, 0.1, 0.1) }
        return SIMD3<Float>(rSum / count, gSum / count, bSum / count)
    }

    // MARK: - Slideshow Methods

    func loadSlideshowFolder(url: URL) {
        if let prev = slideshowAccessedURL {
            prev.stopAccessingSecurityScopedResource()
        }

        let accessing = url.startAccessingSecurityScopedResource()
        if accessing {
            slideshowAccessedURL = url
        }

        slideshowFolderURL = url

        let images = SlideshowEngine.loadImageList(from: url)
        slideshowImages = images
        slideshowCurrentIndex = 0
        if !images.isEmpty {
            loadCurrentSlideshowImage()
        }
    }

    func slideshowNext() {
        guard !slideshowImages.isEmpty else { return }
        slideshowCurrentIndex = (slideshowCurrentIndex + 1) % slideshowImages.count
        loadCurrentSlideshowImage()
    }

    func slideshowPrev() {
        guard !slideshowImages.isEmpty else { return }
        slideshowCurrentIndex = (slideshowCurrentIndex - 1 + slideshowImages.count) % slideshowImages.count
        loadCurrentSlideshowImage()
    }

    func slideshowJump(by offset: Int) {
        guard !slideshowImages.isEmpty else { return }
        let count = slideshowImages.count
        slideshowCurrentIndex = ((slideshowCurrentIndex + offset) % count + count) % count
        loadCurrentSlideshowImage()
    }

    func startSlideshow() {
        guard !slideshowImages.isEmpty else { return }
        slideshowIsPlaying = true
        slideshowTimer?.invalidate()
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(slideshowInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.slideshowNext()
            }
        }
    }

    func stopSlideshow() {
        slideshowIsPlaying = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }

    func loadCurrentSlideshowImage() {
        guard slideshowCurrentIndex < slideshowImages.count else { return }
        let image = slideshowImages[slideshowCurrentIndex]

        // Cancel previous load if still in progress
        slideshowLoadTask?.cancel()

        slideshowLoadTask = Task {
            do {
                let textures = try await SlideshowEngine.loadTextures(for: image)

                guard !Task.isCancelled else { return }

                // Sample colors from the image before assigning textures
                if let cgImage = self.loadCGImage(from: image.url) {
                    self.sampleSlideshowColors(from: cgImage)
                }

                // Release old textures before assigning new ones
                slideshowTexture = nil
                slideshowRightTexture = nil

                slideshowTexture = textures.leftTexture
                slideshowRightTexture = textures.rightTexture
                slideshowIsStereo = textures.isStereo
                slideshowDisplaySize = textures.displaySize
                slideshowTextureVersion += 1
            } catch {
                if !Task.isCancelled {
                    print("Failed to load slideshow image: \(error)")
                }
            }
        }
    }

    // MARK: - Slideshow Color Sampling

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Request a downsampled thumbnail for color sampling to reduce memory usage
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func sampleSlideshowColors(from cgImage: CGImage) {
        let origW = cgImage.width
        let origH = cgImage.height
        guard origW > 0, origH > 0 else { return }

        // Downsample to small size for color sampling to avoid large memory allocation
        let maxSampleDim = 64
        let scale = min(Double(maxSampleDim) / Double(origW), Double(maxSampleDim) / Double(origH), 1.0)
        let w = max(Int(Double(origW) * scale), 1)
        let h = max(Int(Double(origH) * scale), 1)

        guard let context = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return }

        // RGBA format (premultipliedLast)
        // Top edge center strip → ceiling
        let sampledTop = sampleImageRegion(data, bpr: w * 4, w: w, h: h, cx: w / 2, cy: 2, rx: w / 4, ry: 2)
        // Right edge middle strip → walls
        let sampledMiddle = sampleImageRegion(data, bpr: w * 4, w: w, h: h, cx: w - 3, cy: h / 2, rx: 2, ry: h / 4)
        // Bottom edge center strip → floor
        let sampledBottom = sampleImageRegion(data, bpr: w * 4, w: w, h: h, cx: w / 2, cy: h - 3, rx: w / 4, ry: 2)

        slideshowColorTop = sampledTop
        slideshowColorMiddle = sampledMiddle
        slideshowColorBottom = sampledBottom
    }

    private func sampleImageRegion(_ base: UnsafeMutableRawPointer, bpr: Int, w: Int, h: Int,
                                    cx: Int, cy: Int, rx: Int, ry: Int) -> SIMD3<Float> {
        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0
        var count: Float = 0
        let stepX = max(1, rx / 4)
        let stepY = max(1, ry / 4)
        for dy in stride(from: -ry, through: ry, by: stepY) {
            for dx in stride(from: -rx, through: rx, by: stepX) {
                let x = min(max(cx + dx, 0), w - 1)
                let y = min(max(cy + dy, 0), h - 1)
                let ptr = base.advanced(by: y * bpr + x * 4).assumingMemoryBound(to: UInt8.self)
                // RGBA format
                rSum += Float(ptr[0]) / 255.0
                gSum += Float(ptr[1]) / 255.0
                bSum += Float(ptr[2]) / 255.0
                count += 1
            }
        }
        guard count > 0 else { return SIMD3<Float>(0.1, 0.1, 0.1) }
        return SIMD3<Float>(rSum / count, gSum / count, bSum / count)
    }
}
