import SwiftUI
import Observation

@Observable
class AppModel {
    var immersiveSpaceIsShown = false
    var speed: Float = 1.0
    var intensity: Float = 1.0
    var patternStyle: PatternStyle = .psychedelic
    var opacity: Float = 0.75  // 0.0...1.0
    var particlesEnabled: Bool = true
    var audioReactiveEnabled: Bool = false
    var audioSensitivity: Float = 1.0  // 0.1...3.0
    var autoPulseEnabled: Bool = false
    var autoPulseBPM: Float = 120.0    // 60...200

    // Mesh classification filter
    var meshClassificationFilterEnabled: Bool = false  // OFF = cover all surfaces
    var meshFilterWall: Bool = true
    var meshFilterFloor: Bool = true
    var meshFilterCeiling: Bool = true
    var meshFilterTable: Bool = true
    var meshFilterSeat: Bool = true
    var meshFilterWindow: Bool = true
    var meshFilterDoor: Bool = true
    var meshFilterOther: Bool = true

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

        var id: String { rawValue }
    }
}
