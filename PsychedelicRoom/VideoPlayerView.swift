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

    var player: AVPlayer?
    private var videoAccessedURL: URL?
    private var loopObserver: Any?

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

        videoURL = url
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer

        // Loop observer
        if let old = loopObserver {
            NotificationCenter.default.removeObserver(old)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        // Load video size
        Task {
            await loadVideoSize(from: item)
            videoVersion += 1
        }
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
        slideshowImages = SlideshowEngine.loadImageList(from: url)
        slideshowCurrentIndex = 0

        if !slideshowImages.isEmpty {
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

        Task {
            do {
                let textures = try await SlideshowEngine.loadTextures(for: image)
                slideshowTexture = textures.leftTexture
                slideshowRightTexture = textures.rightTexture
                slideshowIsStereo = textures.isStereo
                slideshowDisplaySize = textures.displaySize
                slideshowTextureVersion += 1
            } catch {
                print("Failed to load slideshow image: \(error)")
            }
        }
    }
}
