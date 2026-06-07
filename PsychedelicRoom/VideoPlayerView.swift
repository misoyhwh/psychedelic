import SwiftUI
import AVFoundation
import CoreVideo
import RealityKit
import RealityKitContent

// MARK: - Server search sort / filter

/// サーバ検索結果の並び順。`.filename` はクライアント側で `localizedStandardCompare` ソート、
/// `.posted` / `.added` はサーバ側 sort パラメータでソートする。
///
/// 注意: illust-server の after/before フィルタは常に COALESCE(posted_at, added_at) に適用される。
/// 「追加日」並びを選んでも期間フィルタは厳密には posted_at 寄りで効く (個人収集物では実用上問題なし)。
enum ServerSortOrder: String, CaseIterable, Identifiable, Sendable {
    case filename
    case posted
    case added

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filename: return "ファイル名"
        case .posted: return "投稿日"
        case .added: return "追加日"
        }
    }

    /// `/api/search` の sort パラメータ値。`.filename` は nil (サーバ側ソート無効 → クライアント側で並べ替え)。
    var serverSortValue: String? {
        switch self {
        case .filename: return nil
        case .posted: return "posted_at_desc"
        case .added: return "added_at_desc"
        }
    }
}

/// サーバ検索の期間ショートカット。after=<epoch> として送る。
enum DateRangePreset: String, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case thisWeek
    case thisMonth
    case thisYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .today: return "今日"
        case .thisWeek: return "今週"
        case .thisMonth: return "今月"
        case .thisYear: return "今年"
        }
    }

    /// 期間開始時刻 (00:00) の unix epoch (秒) を返す。.all は nil。
    func afterEpoch(from now: Date = Date(), calendar: Calendar = .current) -> Int? {
        switch self {
        case .all:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            return Int(start.timeIntervalSince1970)
        case .thisWeek:
            // weekOfYear 単位の startOfDay
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            guard let start = calendar.date(from: comps) else { return nil }
            return Int(start.timeIntervalSince1970)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: comps) else { return nil }
            return Int(start.timeIntervalSince1970)
        case .thisYear:
            let comps = calendar.dateComponents([.year], from: now)
            guard let start = calendar.date(from: comps) else { return nil }
            return Int(start.timeIntervalSince1970)
        }
    }
}

@Observable
@MainActor
class MediaPanelViewModel {
    // MARK: - Video Panel

    enum VideoSourceMode: String, CaseIterable, Identifiable {
        case localFile = "Local File"
        case serverSearch = "Server Search"
        var id: String { rawValue }
    }

    var videoEnabled: Bool = false
    var videoSourceMode: VideoSourceMode = .localFile
    var videoURL: URL? = nil
    var isVideoPlaying: Bool = false
    var videoSize: CGSize = CGSize(width: 1.92, height: 1.08)

    // 動画 背景透過 (試作)。立体視フレームを自前テクスチャ化し StereoImageMaterial のクロマキーで抜く。
    var videoBackgroundRemovalEnabled: Bool = false
    var videoChromaKeyColor: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var videoChromaThreshold: Float = 0.4
    var videoChromaSmoothness: Float = 0.1

    // 動画 前景抽出 (試作)。Vision の被写体マスクを数フレームに1回・非同期生成して背景を抜く。
    var videoForegroundKeyEnabled: Bool = false
    var videoForegroundThreshold: Float = 0.5
    var videoForegroundFeather: Float = 0.05
    var videoRotationH: Float = 0
    var videoRotationV: Float = 0
    /// パネル湾曲量。0 = フラット、正値 = こちら向きに弧 (concave)、負値 = 奥向きに弧 (convex)。範囲は -1.0...1.0。
    var videoCurveAmount: Float = 0
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

    // Server video playlist state
    var videoPlaylist: [IllustServerAsset] = []
    var videoPlaylistIndex: Int = 0
    var videoServerSearchInProgress: Bool = false
    var videoServerSearchError: String? = nil
    var videoServerTotalCount: Int = 0
    var videoServerLastTags: String = ""
    var videoSortOrder: ServerSortOrder = .filename
    var videoDatePreset: DateRangePreset = .all
    private var videoServerSearchTask: Task<Void, Never>?
    /// 直近の検索で使った client を保持。プレイリスト遷移時に mediaURL を組み立てるため。
    private var videoServerClient: IllustServerClient?

    // Video color sampling
    var videoColorTop: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var videoColorMiddle: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var videoColorBottom: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    var player: AVPlayer?
    private var videoAccessedURL: URL?
    private var loopObserver: Any?
    private var timeObserver: Any?
    private var videoOutput: AVPlayerItemVideoOutput?
    /// AVPlayerItem.status を KVO で監視するための保持枠 (HTTP 動画は loadVideo 直後は .unknown のため、
    /// .readyToPlay 後に play() を呼ぶ)
    private var itemStatusObservation: NSKeyValueObservation?
    /// アイテム未準備の間に playVideo が呼ばれたら true。準備完了 KVO で発火させる。
    private var pendingAutoplay: Bool = false
    /// player が ready になったか (KVO 発火後 true)。
    private var itemReadyForEntity: Bool = false
    /// 動画サイズが取得できたか (loadVideoSize 完了後 true)。
    private var sizeReadyForEntity: Bool = false

    // Slideshow color sampling
    var slideshowColorTop: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var slideshowColorMiddle: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    var slideshowColorBottom: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    // MARK: - Slideshow Panel

    enum SlideshowSourceMode: String, CaseIterable, Identifiable {
        case localFolder = "Local Folder"
        case serverSearch = "Server Search"
        var id: String { rawValue }
    }

    var slideshowEnabled: Bool = false
    var slideshowSourceMode: SlideshowSourceMode = .localFolder
    var slideshowFolderURL: URL? = nil
    var slideshowImages: [SlideshowImage] = []
    var slideshowCurrentIndex: Int = 0
    var slideshowIsPlaying: Bool = false
    var slideshowInterval: Float = 5.0
    var slideshowRotationH: Float = 0
    var slideshowRotationV: Float = 0
    /// パネル湾曲量。0 = フラット、正値 = こちら向きに弧 (concave)、負値 = 奥向きに弧 (convex)。範囲は -1.0...1.0。
    var slideshowCurveAmount: Float = 0
    var slideshowTexture: TextureResource?
    var slideshowRightTexture: TextureResource?
    var slideshowIsStereo: Bool = false
    var slideshowDisplaySize: CGSize = CGSize(width: 1.92, height: 1.08)
    var slideshowTextureVersion: Int = 0

    // Slideshow chroma key (背景透過)。立体視を保ったままキー色付近を透明化する。
    var slideshowChromaKeyEnabled: Bool = false
    /// キー色 (透明化したい背景色)。線形ではなく sRGB の 0...1 RGB。
    var slideshowChromaKeyColor: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    /// この距離以内をキー色とみなして完全透明にする (0...1)。
    var slideshowChromaThreshold: Float = 0.4
    /// 透明 -> 不透明へ遷移する境界の幅 (大きいほど縁がなだらか)。
    var slideshowChromaSmoothness: Float = 0.1

    // Slideshow 前景抽出 (Vision 被写体マスクで背景を透過)。
    var slideshowForegroundKeyEnabled: Bool = false
    /// マットのしきい値 (0...1)。大きいほど前景判定が厳しく背景が広く透過。
    var slideshowForegroundThreshold: Float = 0.5
    /// マット境界のぼかし幅。
    var slideshowForegroundFeather: Float = 0.05
    /// 前景マスク (左/モノ)。機能オフ/生成失敗時は nil。
    var slideshowForegroundMask: TextureResource?
    /// 前景マスク (右ステレオ)。
    var slideshowForegroundMaskRight: TextureResource?

    // Server search state
    var slideshowServerSearchInProgress: Bool = false
    var slideshowServerSearchError: String? = nil
    var slideshowServerTotalCount: Int = 0
    var slideshowServerLastTags: String = ""
    var slideshowSortOrder: ServerSortOrder = .filename
    var slideshowDatePreset: DateRangePreset = .all

    private var slideshowAccessedURL: URL?
    private var slideshowTimer: Timer?
    private var slideshowLoadTask: Task<Void, Never>?
    private var slideshowServerSearchTask: Task<Void, Never>?

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

        // Reset entity-creation gating flags for the new video
        itemReadyForEntity = false
        sizeReadyForEntity = false

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

        // End-of-playback observer: Local モードはループ、Server モードは次の動画へ
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onVideoEnded()
            }
        }

        // AVPlayerItem.status KVO: HTTP 動画は作成直後 .unknown のため、
        // .readyToPlay 後に保留中の autoplay を発火させる。
        // .failed の場合は Server プレイリストなら次へスキップ。
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    if self.pendingAutoplay {
                        self.player?.playImmediately(atRate: 1.0)
                        self.isVideoPlaying = true
                        self.pendingAutoplay = false
                    }
                    // ready になったので entity 作成条件を更新
                    self.itemReadyForEntity = true
                    self.tryCreateVideoEntity()
                case .failed:
                    print("Video item failed: \(item.error?.localizedDescription ?? "unknown")")
                    self.pendingAutoplay = false
                    if self.videoSourceMode == .serverSearch && !self.videoPlaylist.isEmpty {
                        self.videoPlaylistNext()
                    }
                default:
                    break
                }
            }
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

        // entity は item.status == .readyToPlay && サイズ取得完了 の両方が揃った時点で作る。
        // ここでは bump しない (古い entity は次の作成タイミングまで残るが、それで OK)。
        Task {
            await loadVideoSize(from: item)
            sizeReadyForEntity = true
            tryCreateVideoEntity()
        }
    }

    /// player が ready かつ サイズ取得済みのときだけ videoVersion を bump して entity を 1 回だけ作り直す。
    /// 中途半端な状態で entity を作ると VideoMaterial がフレームを描画してくれないため。
    private func tryCreateVideoEntity() {
        guard itemReadyForEntity, sizeReadyForEntity else { return }
        videoVersion += 1
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

        // Invalidate item-status KVO
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        pendingAutoplay = false

        // Stop old player
        player?.pause()
        player = nil
        isVideoPlaying = false
    }

    @MainActor
    private func onVideoEnded() {
        if videoSourceMode == .serverSearch && !videoPlaylist.isEmpty {
            // 次の動画へ自動切替
            videoPlaylistNext()
        } else {
            // Local: 同じ動画をループ
            player?.seek(to: .zero)
            player?.play()
        }
    }

    func playVideo() {
        // アイテム未準備なら autoplay フラグを立てて KVO に任せる。
        // (HTTP 動画は loadVideo 直後 .unknown 状態で、play() を呼んでも実際の再生が走らない場合がある)
        if let item = player?.currentItem, item.status == .readyToPlay {
            player?.playImmediately(atRate: 1.0)
            isVideoPlaying = true
            pendingAutoplay = false
        } else {
            pendingAutoplay = true
            isVideoPlaying = true  // 意図表示のため即時更新 (実再生は ready 後)
        }
    }

    func pauseVideo() {
        player?.pause()
        isVideoPlaying = false
        pendingAutoplay = false
    }

    func stopVideo() {
        player?.pause()
        player?.seek(to: .zero)
        isVideoPlaying = false
        pendingAutoplay = false
        videoCurrentTime = 0
    }

    func seekVideo(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Video Server Playlist

    /// illust-server からタグ検索で動画プレイリストを構築し、先頭から再生開始。
    /// `sortOrder == .filename` のときは取得後にクライアント側で `localizedStandardCompare` ソート。
    func loadVideoPlaylistFromServer(
        host: String,
        tags: [String],
        ratings: [String],
        after: Int? = nil,
        sortOrder: ServerSortOrder = .filename
    ) {
        videoServerSearchTask?.cancel()

        guard let client = IllustServerClient.from(host: host) else {
            videoServerSearchError = "サーバ URL が無効です"
            return
        }
        videoServerClient = client

        videoServerSearchInProgress = true
        videoServerSearchError = nil
        videoServerLastTags = tags.joined(separator: ", ")

        videoServerSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                var assets = try await self.fetchAllAssets(
                    client: client,
                    tags: tags,
                    ratings: ratings,
                    mediaType: "video",
                    after: after,
                    sort: sortOrder.serverSortValue,
                    cap: 500
                )
                if Task.isCancelled { return }
                if sortOrder == .filename {
                    assets.sort { lhs, rhs in
                        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    }
                }
                self.videoPlaylist = assets
                self.videoPlaylistIndex = 0
                self.videoServerTotalCount = assets.count
                self.videoServerSearchInProgress = false
                if !assets.isEmpty {
                    self.loadCurrentPlaylistVideo()
                }
            } catch let e as IllustServerError {
                if !Task.isCancelled {
                    self.videoServerSearchError = e.errorDescription
                    self.videoServerSearchInProgress = false
                }
            } catch {
                if !Task.isCancelled {
                    self.videoServerSearchError = error.localizedDescription
                    self.videoServerSearchInProgress = false
                }
            }
        }
    }

    func videoPlaylistNext() {
        guard !videoPlaylist.isEmpty else { return }
        videoPlaylistIndex = (videoPlaylistIndex + 1) % videoPlaylist.count
        loadCurrentPlaylistVideo()
    }

    func videoPlaylistPrev() {
        guard !videoPlaylist.isEmpty else { return }
        videoPlaylistIndex = (videoPlaylistIndex - 1 + videoPlaylist.count) % videoPlaylist.count
        loadCurrentPlaylistVideo()
    }

    func videoPlaylistJump(by offset: Int) {
        guard !videoPlaylist.isEmpty else { return }
        let count = videoPlaylist.count
        videoPlaylistIndex = ((videoPlaylistIndex + offset) % count + count) % count
        loadCurrentPlaylistVideo()
    }

    private func loadCurrentPlaylistVideo() {
        guard videoPlaylistIndex < videoPlaylist.count,
              let client = videoServerClient else { return }
        let asset = videoPlaylist[videoPlaylistIndex]
        let url = client.mediaURL(hash: asset.hash)
        loadVideo(url: url)
        playVideo()
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
        // Cancel any in-flight server search when switching to local
        slideshowServerSearchTask?.cancel()
        slideshowServerSearchTask = nil
        slideshowServerSearchInProgress = false

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

    /// illust-server からタグ検索で画像リストを構築する。
    /// 既存スライドショーは置き換えられる (リモート → リモート切替時も再検索)。
    /// `sortOrder == .filename` のときは取得後にクライアント側で `localizedStandardCompare` ソート。
    func loadSlideshowFromServer(
        host: String,
        tags: [String],
        ratings: [String],
        after: Int? = nil,
        sortOrder: ServerSortOrder = .filename
    ) {
        slideshowServerSearchTask?.cancel()

        guard let client = IllustServerClient.from(host: host) else {
            slideshowServerSearchError = "サーバ URL が無効です"
            return
        }

        // Release any previously held local folder
        if let prev = slideshowAccessedURL {
            prev.stopAccessingSecurityScopedResource()
            slideshowAccessedURL = nil
        }
        slideshowFolderURL = nil

        slideshowServerSearchInProgress = true
        slideshowServerSearchError = nil
        slideshowServerLastTags = tags.joined(separator: ", ")

        slideshowServerSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let assets = try await self.fetchAllAssets(
                    client: client,
                    tags: tags,
                    ratings: ratings,
                    mediaType: "image",
                    after: after,
                    sort: sortOrder.serverSortValue,
                    cap: 2000
                )
                if Task.isCancelled { return }

                var images = assets.map { asset -> SlideshowImage in
                    SlideshowImage(
                        url: client.mediaURL(hash: asset.hash),
                        displayName: asset.displayName
                    )
                }
                if sortOrder == .filename {
                    images.sort { lhs, rhs in
                        let a = lhs.displayName ?? ""
                        let b = rhs.displayName ?? ""
                        return a.localizedStandardCompare(b) == .orderedAscending
                    }
                }
                self.slideshowImages = images
                self.slideshowCurrentIndex = 0
                self.slideshowServerTotalCount = images.count
                self.slideshowServerSearchInProgress = false
                if !images.isEmpty {
                    self.loadCurrentSlideshowImage()
                }
            } catch let e as IllustServerError {
                if !Task.isCancelled {
                    self.slideshowServerSearchError = e.errorDescription
                    self.slideshowServerSearchInProgress = false
                }
            } catch {
                if !Task.isCancelled {
                    self.slideshowServerSearchError = error.localizedDescription
                    self.slideshowServerSearchInProgress = false
                }
            }
        }
    }

    /// limit を超えるまで /api/search をページングして集める。cap で上限を切る。
    /// mediaType は "image" or "video"。`after` / `sort` は optional。
    private func fetchAllAssets(
        client: IllustServerClient,
        tags: [String],
        ratings: [String],
        mediaType: String,
        after: Int? = nil,
        sort: String? = nil,
        cap: Int
    ) async throws -> [IllustServerAsset] {
        var results: [IllustServerAsset] = []
        var offset = 0
        let pageSize = 100
        while results.count < cap {
            if Task.isCancelled { break }
            let resp = try await client.search(
                tags: tags,
                ratings: ratings,
                mediaType: mediaType,
                after: after,
                sort: sort,
                limit: pageSize,
                offset: offset
            )
            results.append(contentsOf: resp.items)
            if !resp.page.hasMore || resp.items.isEmpty { break }
            offset += resp.items.count
        }
        if results.count > cap {
            results = Array(results.prefix(cap))
        }
        return results
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
                // Phase 1: 表示テクスチャを先に出す (マスク生成を待たない)。
                let textures = try await SlideshowEngine.loadTextures(for: image)

                guard !Task.isCancelled else { return }

                // Sample colors using the small thumbnail produced by loadTextures
                // (avoids a second download/decode of the full HEIC).
                if let cgImage = textures.colorSamplingImage {
                    self.sampleSlideshowColors(from: cgImage)
                }

                // Release old textures before assigning new ones
                slideshowTexture = nil
                slideshowRightTexture = nil
                slideshowForegroundMask = nil
                slideshowForegroundMaskRight = nil

                slideshowTexture = textures.leftTexture
                slideshowRightTexture = textures.rightTexture
                slideshowIsStereo = textures.isStereo
                slideshowDisplaySize = textures.displaySize
                slideshowTextureVersion += 1   // ← この時点でスライドは即座に切り替わる

                // Phase 2: 前景マスクを後追い生成。重い/失敗してもスライド送りはブロックしない。
                if slideshowForegroundKeyEnabled, let leftCG = textures.leftDisplayImage {
                    let masks = await SlideshowEngine.foregroundMaskTextures(
                        leftImage: leftCG,
                        rightImage: textures.rightDisplayImage
                    )
                    guard !Task.isCancelled else { return }
                    slideshowForegroundMask = masks.left
                    slideshowForegroundMaskRight = masks.right
                    // マスクが取れたら再バインドして切り抜きを適用。
                    if masks.left != nil {
                        slideshowTextureVersion += 1
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Failed to load slideshow image: \(error)")
                }
            }
        }
    }

    // MARK: - Slideshow Color Sampling

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
