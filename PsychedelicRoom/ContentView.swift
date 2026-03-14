import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AudioReactiveEngine.self) private var audioEngine
    @Environment(MediaPanelViewModel.self) private var mediaVM
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow

    @State private var showVideoFilePicker = false
    @State private var showSlideshowFolderPicker = false

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
        VStack(spacing: 24) {
            Text("Psychedelic Room")
                .font(.extraLargeTitle)

            Text("部屋をサイケデリックな模様で彩ります")
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            // Pattern style picker
            Picker("Pattern", selection: $appModel.patternStyle) {
                ForEach(AppModel.PatternStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)

            // Speed control
            VStack(alignment: .leading) {
                Text("Speed: \(appModel.speed, specifier: "%.1f")x")
                Slider(value: $appModel.speed, in: 0.1...3.0, step: 0.1)
            }

            // Intensity control
            VStack(alignment: .leading) {
                Text("Intensity: \(appModel.intensity, specifier: "%.1f")")
                Slider(value: $appModel.intensity, in: 0.1...2.0, step: 0.1)
            }

            // Particles toggle
            Toggle("Particles", isOn: $appModel.particlesEnabled)
                .toggleStyle(.switch)

            Divider()

            // Audio reactive section
            VStack(spacing: 12) {
                Toggle("Audio Reactive", isOn: $appModel.audioReactiveEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: appModel.audioReactiveEnabled) { _, enabled in
                        Task {
                            if enabled {
                                audioEngine.start()
                            } else {
                                audioEngine.stop()
                            }
                        }
                    }

                if appModel.audioReactiveEnabled {
                    Toggle("Auto Pulse (BPMモード)", isOn: $appModel.autoPulseEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: appModel.autoPulseEnabled) { _, enabled in
                            audioEngine.autoPulseEnabled = enabled
                            audioEngine.stop()
                            Task {
                                audioEngine.start()
                            }
                        }

                    if appModel.autoPulseEnabled {
                        VStack(alignment: .leading) {
                            Text("BPM: \(Int(appModel.autoPulseBPM))")
                            Slider(value: $appModel.autoPulseBPM, in: 60...200, step: 1)
                                .onChange(of: appModel.autoPulseBPM) { _, value in
                                    audioEngine.autoPulseBPM = value
                                }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(appModel.audioSensitivity, specifier: "%.1f")x")
                        Slider(value: $appModel.audioSensitivity, in: 0.1...3.0, step: 0.1)
                            .onChange(of: appModel.audioSensitivity) { _, value in
                                audioEngine.sensitivity = value
                            }
                    }

                    HStack(spacing: 16) {
                        AudioLevelBar(label: "Vol", level: audioEngine.audioLevel)
                        AudioLevelBar(label: "Bass", level: audioEngine.bassLevel)
                        AudioLevelBar(label: "Treble", level: audioEngine.trebleLevel)
                    }
                    .frame(height: 60)
                }
            }

            // Browser button
            Button {
                openWindow(id: "BrowserWindow")
            } label: {
                Label("Browser", systemImage: "globe")
            }
            .buttonStyle(.bordered)

            Divider()

            // MARK: - Video Panel Section
            videoPanelSection

            Divider()

            // MARK: - Slideshow Panel Section
            slideshowPanelSection

            Divider()

            // Occlusion panel section
            VStack(spacing: 12) {
                Toggle("Occlusion Panel", isOn: $appModel.occlusionPanelEnabled)
                    .toggleStyle(.switch)

                if appModel.occlusionPanelEnabled {
                    Text("パネル位置はドラッグで移動できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading) {
                        Text("幅: \(appModel.occlusionPanelWidth, specifier: "%.1f")m")
                        Slider(value: $appModel.occlusionPanelWidth, in: 0.3...3.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("高さ: \(appModel.occlusionPanelHeight, specifier: "%.1f")m")
                        Slider(value: $appModel.occlusionPanelHeight, in: 0.2...2.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("回転: \(Int(appModel.occlusionPanelRotation))°")
                        Slider(value: $appModel.occlusionPanelRotation, in: -180...180, step: 5)
                    }
                }
            }

            Divider()

            // Mesh classification filter
            VStack(spacing: 8) {
                Toggle("Mesh Classification Filter", isOn: $appModel.meshClassificationFilterEnabled)
                    .toggleStyle(.switch)

                if !appModel.meshClassificationFilterEnabled {
                    Text("全ての面にエフェクトを適用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("カテゴリ別にメッシュ表示をON/OFF")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        Toggle("壁 (Wall)", isOn: $appModel.meshFilterWall)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("床 (Floor)", isOn: $appModel.meshFilterFloor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("天井 (Ceiling)", isOn: $appModel.meshFilterCeiling)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("テーブル (Table)", isOn: $appModel.meshFilterTable)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("椅子 (Seat)", isOn: $appModel.meshFilterSeat)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("窓 (Window)", isOn: $appModel.meshFilterWindow)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("ドア (Door)", isOn: $appModel.meshFilterDoor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("その他 (Other)", isOn: $appModel.meshFilterOther)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            Divider()

            Toggle(appModel.immersiveSpaceIsShown ? "Stop Experience" : "Start Experience",
                   isOn: $appModel.immersiveSpaceIsShown)
                .toggleStyle(.button)
                .font(.title2)
                .onChange(of: appModel.immersiveSpaceIsShown) { _, isShown in
                    Task {
                        if isShown {
                            await openImmersiveSpace(id: "PsychedelicSpace")
                        } else {
                            await dismissImmersiveSpace()
                        }
                    }
                }
        }
        .padding(40)
        .frame(width: 500)
        } // ScrollView
    }

    // MARK: - Video Panel Controls

    @MainActor
    private var videoPanelSection: some View {
        VStack(spacing: 12) {
            Toggle("Video Panel", isOn: Binding(
                get: { mediaVM.videoEnabled },
                set: { mediaVM.videoEnabled = $0 }
            ))
            .toggleStyle(.switch)

            if mediaVM.videoEnabled {
                Text("Immersive空間に枠なし動画パネルを配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // File picker button
                Button {
                    showVideoFilePicker = true
                } label: {
                    Label(mediaVM.videoURL != nil ? mediaVM.videoURL!.lastPathComponent : "動画ファイルを選択",
                          systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .fileImporter(
                    isPresented: $showVideoFilePicker,
                    allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        mediaVM.loadVideo(url: url)
                        mediaVM.playVideo()
                    }
                }

                if mediaVM.player != nil {
                    // Playback controls
                    HStack(spacing: 16) {
                        Button {
                            if mediaVM.isVideoPlaying {
                                mediaVM.pauseVideo()
                            } else {
                                mediaVM.playVideo()
                            }
                        } label: {
                            Image(systemName: mediaVM.isVideoPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            mediaVM.stopVideo()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Rotation controls
                    VStack(alignment: .leading) {
                        Text("水平回転: \(Int(mediaVM.videoRotationH))°")
                        Slider(value: Binding(
                            get: { mediaVM.videoRotationH },
                            set: { mediaVM.videoRotationH = $0 }
                        ), in: -180...180, step: 5)
                    }

                    VStack(alignment: .leading) {
                        Text("垂直回転: \(Int(mediaVM.videoRotationV))°")
                        Slider(value: Binding(
                            get: { mediaVM.videoRotationV },
                            set: { mediaVM.videoRotationV = $0 }
                        ), in: -90...90, step: 5)
                    }
                }
            }
        }
    }

    // MARK: - Slideshow Panel Controls

    @MainActor
    private var slideshowPanelSection: some View {
        VStack(spacing: 12) {
            Toggle("Slideshow Panel", isOn: Binding(
                get: { mediaVM.slideshowEnabled },
                set: { mediaVM.slideshowEnabled = $0 }
            ))
            .toggleStyle(.switch)

            if mediaVM.slideshowEnabled {
                Text("立体視対応スライドショーパネル")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Folder picker button
                Button {
                    showSlideshowFolderPicker = true
                } label: {
                    Label(mediaVM.slideshowFolderURL != nil ? mediaVM.slideshowFolderURL!.lastPathComponent : "画像フォルダを選択",
                          systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .fileImporter(
                    isPresented: $showSlideshowFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        mediaVM.loadSlideshowFolder(url: url)
                    }
                }

                if !mediaVM.slideshowImages.isEmpty {
                    Text("\(mediaVM.slideshowCurrentIndex + 1) / \(mediaVM.slideshowImages.count) 枚")
                        .font(.caption)

                    if mediaVM.slideshowIsStereo {
                        Label("立体視 (Stereo)", systemImage: "eye.trianglebadge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    // Navigation controls
                    HStack(spacing: 16) {
                        Button {
                            mediaVM.slideshowPrev()
                        } label: {
                            Image(systemName: "backward.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if mediaVM.slideshowIsPlaying {
                                mediaVM.stopSlideshow()
                            } else {
                                mediaVM.startSlideshow()
                            }
                        } label: {
                            Image(systemName: mediaVM.slideshowIsPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            mediaVM.slideshowNext()
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Interval control
                    VStack(alignment: .leading) {
                        Text("間隔: \(mediaVM.slideshowInterval, specifier: "%.0f")秒")
                        Slider(value: Binding(
                            get: { mediaVM.slideshowInterval },
                            set: {
                                mediaVM.slideshowInterval = $0
                                if mediaVM.slideshowIsPlaying {
                                    mediaVM.stopSlideshow()
                                    mediaVM.startSlideshow()
                                }
                            }
                        ), in: 1...30, step: 1)
                    }

                    // Rotation controls
                    VStack(alignment: .leading) {
                        Text("水平回転: \(Int(mediaVM.slideshowRotationH))°")
                        Slider(value: Binding(
                            get: { mediaVM.slideshowRotationH },
                            set: { mediaVM.slideshowRotationH = $0 }
                        ), in: -180...180, step: 5)
                    }

                    VStack(alignment: .leading) {
                        Text("垂直回転: \(Int(mediaVM.slideshowRotationV))°")
                        Slider(value: Binding(
                            get: { mediaVM.slideshowRotationV },
                            set: { mediaVM.slideshowRotationV = $0 }
                        ), in: -90...90, step: 5)
                    }
                }
            }
        }
    }
}

// MARK: - Audio Level Visualizer

struct AudioLevelBar: View {
    let label: String
    let level: Float

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(height: geo.size.height * CGFloat(level))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var barColor: some ShapeStyle {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
