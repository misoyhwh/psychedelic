import SwiftUI
import AVKit
import UniformTypeIdentifiers

// AVPlayerViewController wrapper — uses delegate to prevent fullscreen/spatial transition
struct SpatialVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        // Prevent entering fullscreen/spatial mode to keep the immersive space intact
        @MainActor
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { context in
                if !context.isCancelled {
                    playerViewController.dismiss(animated: true)
                }
            }
        }
    }
}

struct VideoPlayerWindowView: View {
    @State private var player: AVPlayer?
    @State private var showFilePicker = false
    @State private var accessedURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            if let player {
                SpatialVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 20) {
                    Button {
                        player.seek(to: .zero)
                        player.play()
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Open Other", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 12)
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Spatial Videoを選択してください")
                        .font(.title2)
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("ファイルを選択", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadVideo(url: url)
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }

    private func loadVideo(url: URL) {
        if let prev = accessedURL {
            prev.stopAccessingSecurityScopedResource()
        }
        let accessing = url.startAccessingSecurityScopedResource()
        if accessing {
            accessedURL = url
        }
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.play()
    }
}
