import SwiftUI

@main
struct PsychedelicRoomApp: App {
    @State private var appModel = AppModel()
    @State private var audioEngine = AudioReactiveEngine()
    @State private var mediaVM = MediaPanelViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(audioEngine)
                .environment(mediaVM)
        }
        .defaultSize(width: 500, height: 1100)

        WindowGroup(id: "BrowserWindow") {
            BrowserWindowView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)

        ImmersiveSpace(id: "PsychedelicSpace") {
            ImmersiveView()
                .environment(appModel)
                .environment(audioEngine)
                .environment(mediaVM)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
