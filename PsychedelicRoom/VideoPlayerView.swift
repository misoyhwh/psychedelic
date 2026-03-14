import SwiftUI
import AVFoundation
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
    var videoVersion: Int = 0

    var videoCurrentTime: Double = 0
    var videoDuration: Double = 0
    var isSeeking: Bool = false

    var player: AVPlayer?
    private var videoAccessedURL: URL?
    private var loopObserver: Any?
    private var timeObserver: Any?

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
}
