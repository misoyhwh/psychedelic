import SwiftUI
import Observation

@Observable
class AppModel {
    // MARK: - Illust Server

    enum IllustServerPingStatus {
        case unknown
        case checking
        case ok(version: String)
        case failed(message: String)
    }

    private static let illustServerHostKey = "illustServerHost"
    // 画像用 (旧キーをそのまま画像用として継続利用)
    private static let illustServerLastTagsKey = "illustServerLastTags"
    private static let illustServerLastRatingsKey = "illustServerLastRatings"
    // 動画用
    private static let illustServerLastVideoTagsKey = "illustServerLastVideoTags"
    private static let illustServerLastVideoRatingsKey = "illustServerLastVideoRatings"
    // 日付フィルター (画像)
    private static let illustServerImageDateSourceKey = "illustServerImageDateSource"
    private static let illustServerImageDatePresetKey = "illustServerImageDatePreset"
    // 日付フィルター (動画)
    private static let illustServerVideoDateSourceKey = "illustServerVideoDateSource"
    private static let illustServerVideoDatePresetKey = "illustServerVideoDatePreset"
    private static let illustServerHostDefault = "http://misoyhwhmac-mini:8080/"

    var illustServerHost: String = {
        let stored = UserDefaults.standard.string(forKey: AppModel.illustServerHostKey) ?? ""
        return stored.isEmpty ? AppModel.illustServerHostDefault : stored
    }() {
        didSet {
            UserDefaults.standard.set(illustServerHost, forKey: AppModel.illustServerHostKey)
        }
    }

    /// 画像 (スライドショー) サーバ検索で最後に使ったタグ (カンマ区切り保存)
    var illustServerLastTags: String = UserDefaults.standard.string(forKey: AppModel.illustServerLastTagsKey) ?? "" {
        didSet {
            UserDefaults.standard.set(illustServerLastTags, forKey: AppModel.illustServerLastTagsKey)
        }
    }

    /// 画像 (スライドショー) サーバ検索で最後に使った rating (カンマ区切り保存)
    var illustServerLastRatings: String = UserDefaults.standard.string(forKey: AppModel.illustServerLastRatingsKey) ?? "safe" {
        didSet {
            UserDefaults.standard.set(illustServerLastRatings, forKey: AppModel.illustServerLastRatingsKey)
        }
    }

    /// 動画 (ビデオパネル) サーバ検索で最後に使ったタグ (カンマ区切り保存)
    var illustServerLastVideoTags: String = UserDefaults.standard.string(forKey: AppModel.illustServerLastVideoTagsKey) ?? "" {
        didSet {
            UserDefaults.standard.set(illustServerLastVideoTags, forKey: AppModel.illustServerLastVideoTagsKey)
        }
    }

    /// 動画 (ビデオパネル) サーバ検索で最後に使った rating (カンマ区切り保存)
    var illustServerLastVideoRatings: String = UserDefaults.standard.string(forKey: AppModel.illustServerLastVideoRatingsKey) ?? "safe" {
        didSet {
            UserDefaults.standard.set(illustServerLastVideoRatings, forKey: AppModel.illustServerLastVideoRatingsKey)
        }
    }

    /// 画像サーバ検索の日付ソース ("posted" / "added")。DateSource の rawValue を保存。
    var illustServerImageDateSource: String = UserDefaults.standard.string(forKey: AppModel.illustServerImageDateSourceKey) ?? "posted" {
        didSet {
            UserDefaults.standard.set(illustServerImageDateSource, forKey: AppModel.illustServerImageDateSourceKey)
        }
    }

    /// 画像サーバ検索の期間ショートカット ("all" / "today" / "thisWeek" / "thisMonth" / "thisYear")。
    var illustServerImageDatePreset: String = UserDefaults.standard.string(forKey: AppModel.illustServerImageDatePresetKey) ?? "all" {
        didSet {
            UserDefaults.standard.set(illustServerImageDatePreset, forKey: AppModel.illustServerImageDatePresetKey)
        }
    }

    /// 動画サーバ検索の日付ソース ("posted" / "added")。
    var illustServerVideoDateSource: String = UserDefaults.standard.string(forKey: AppModel.illustServerVideoDateSourceKey) ?? "posted" {
        didSet {
            UserDefaults.standard.set(illustServerVideoDateSource, forKey: AppModel.illustServerVideoDateSourceKey)
        }
    }

    /// 動画サーバ検索の期間ショートカット。
    var illustServerVideoDatePreset: String = UserDefaults.standard.string(forKey: AppModel.illustServerVideoDatePresetKey) ?? "all" {
        didSet {
            UserDefaults.standard.set(illustServerVideoDatePreset, forKey: AppModel.illustServerVideoDatePresetKey)
        }
    }

    var illustServerPingStatus: IllustServerPingStatus = .unknown

    @MainActor
    func pingIllustServer() async {
        illustServerPingStatus = .checking
        guard let client = IllustServerClient.from(host: illustServerHost) else {
            illustServerPingStatus = .failed(message: "URL が無効です")
            return
        }
        do {
            let h = try await client.health()
            illustServerPingStatus = .ok(version: h.version ?? "?")
        } catch let e as IllustServerError {
            illustServerPingStatus = .failed(message: e.errorDescription ?? "通信失敗")
        } catch {
            illustServerPingStatus = .failed(message: error.localizedDescription)
        }
    }

    var immersiveSpaceIsShown = false
    var speed: Float = 1.0
    var intensity: Float = 1.0
    var patternStyle: PatternStyle = .psychedelic
    var opacity: Float = 0.75  // 0.0...1.0
    var particlesEnabled: Bool = false
    var audioReactiveEnabled: Bool = false
    var audioSensitivity: Float = 1.0  // 0.1...3.0
    var autoPulseEnabled: Bool = false
    var autoPulseBPM: Float = 120.0    // 60...200

    // Mesh classification filter
    var meshClassificationFilterEnabled: Bool = false  // OFF = cover all surfaces
    var meshFilterWall: Bool = true
    var meshFilterFloor: Bool = true
    var meshFilterStairs: Bool = true
    var meshFilterBed: Bool = true
    var meshFilterCeiling: Bool = true
    var meshFilterTable: Bool = true
    var meshFilterSeat: Bool = true
    var meshFilterCabinet: Bool = true
    var meshFilterWindow: Bool = true
    var meshFilterDoor: Bool = true
    var meshFilterHomeAppliance: Bool = true
    var meshFilterTV: Bool = true
    var meshFilterPlant: Bool = true
    var meshFilterOther: Bool = true

    // Video color mode
    var videoColorMode: Bool = false
    var colorSource: ColorSource = .video

    enum ColorSource: String, CaseIterable, Identifiable {
        case video = "Video"
        case slideshow = "Slideshow"
        var id: String { rawValue }
    }

    // Occlusion panel
    var occlusionPanelEnabled: Bool = false
    var occlusionPanelWidth: Float = 1.0    // meters
    var occlusionPanelHeight: Float = 0.6   // meters
    var occlusionPanelRotation: Float = 0   // degrees, Y-axis

    enum PatternStyle: String, CaseIterable, Identifiable {
        case psychedelic = "Psychedelic"
        case fractal = "Fractal"
        case miku39 = "39"
        case rainbow = "Rainbow Wave"
        case aurora = "Aurora"
        case voronoi = "Voronoi"
        case interference = "Interference"
        case hexTunnel = "Hex Tunnel"
        case organic = "Organic"
        case sparkles = "Sparkles"
        case hearts = "Hearts"
        case caustic = "Caustic"
        case videoPsychedelic = "Video Psychedelic"
        case videoInterference = "Video Interference"
        case videoRainbow = "Video Rainbow"
        case videoAurora = "Video Aurora"
        case occlusion = "Occlusion"

        var id: String { rawValue }
    }
}
