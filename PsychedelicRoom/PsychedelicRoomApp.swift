import SwiftUI

@main
struct PsychedelicRoomApp: App {
    @State private var appModel = AppModel()
    @State private var audioEngine = AudioReactiveEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(audioEngine)
        }
        .defaultSize(width: 500, height: 1100)

        WindowGroup(id: "BrowserWindow") {
            BrowserWindowView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)

        WindowGroup(id: "VideoPlayerWindow") {
            VideoPlayerWindowView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)

        ImmersiveSpace(id: "PsychedelicSpace") {
            ImmersiveView()
                .environment(appModel)
                .environment(audioEngine)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
