import SwiftUI
import UIKit
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
    @State private var memoryMB: Double = 0
    @State private var memoryPeakMB: Double = 0

    private let memoryTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
        VStack(spacing: 24) {
            Text("Psychedelic Room")
                .font(.extraLargeTitle)

            Text("部屋をサイケデリックな模様で彩ります")
                .font(.title3)
                .foregroundStyle(.secondary)

            memoryIndicator

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

            // Opacity control
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(appModel.opacity * 100))%")
                Slider(value: $appModel.opacity, in: 0.0...1.0, step: 0.05)
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

            // MARK: - Illust Server Settings
            illustServerSection

            Divider()

            // MARK: - Video Panel Section
            videoPanelSection

            Divider()

            // MARK: - Slideshow Panel Section
            slideshowPanelSection

            Divider()

            // MARK: - Color Mode Section
            colorModeSection

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
                        Toggle("階段 (Stairs)", isOn: $appModel.meshFilterStairs)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("ベッド (Bed)", isOn: $appModel.meshFilterBed)
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
                        Toggle("棚 (Cabinet)", isOn: $appModel.meshFilterCabinet)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("窓 (Window)", isOn: $appModel.meshFilterWindow)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("ドア (Door)", isOn: $appModel.meshFilterDoor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("家電 (HomeAppliance)", isOn: $appModel.meshFilterHomeAppliance)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("テレビ (TV)", isOn: $appModel.meshFilterTV)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("植物 (Plant)", isOn: $appModel.meshFilterPlant)
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
        .onAppear {
            updateMemory()
        }
        .onReceive(memoryTimer) { _ in
            updateMemory()
        }
    }

    private func updateMemory() {
        if let mb = MemoryMonitor.currentResidentMB() {
            memoryMB = mb
            if mb > memoryPeakMB { memoryPeakMB = mb }
        }
    }

    @ViewBuilder
    private var memoryIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip")
                .imageScale(.small)
            Text("Memory: \(memoryMB, specifier: "%.0f") MB")
                .font(.caption)
                .monospacedDigit()
            Text("(peak \(memoryPeakMB, specifier: "%.0f"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button {
                memoryPeakMB = memoryMB
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("ピークをリセット")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Illust Server Settings

    @MainActor
    private var illustServerSection: some View {
        @Bindable var appModel = appModel
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                Text("Illust Server")
                    .font(.headline)
                Spacer()
                illustServerStatusDot
            }

            TextField("http://100.x.x.x:8080", text: $appModel.illustServerHost)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button {
                    Task { await appModel.pingIllustServer() }
                } label: {
                    Label("接続テスト", systemImage: "network")
                }
                .buttonStyle(.bordered)
                .disabled(appModel.illustServerHost.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                illustServerStatusText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var illustServerStatusDot: some View {
        switch appModel.illustServerPingStatus {
        case .unknown:
            Circle().fill(.gray).frame(width: 10, height: 10)
        case .checking:
            ProgressView().controlSize(.mini)
        case .ok:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .failed:
            Circle().fill(.red).frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private var illustServerStatusText: some View {
        switch appModel.illustServerPingStatus {
        case .unknown:
            Text("未確認")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            Text("確認中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok(let v):
            Text("接続OK (v\(v))")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
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

                // Source mode picker (Local File / Server Search)
                Picker("Source", selection: Binding(
                    get: { mediaVM.videoSourceMode },
                    set: { mediaVM.videoSourceMode = $0 }
                )) {
                    ForEach(MediaPanelViewModel.VideoSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mediaVM.videoSourceMode == .localFile {
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
                } else {
                    videoServerSearchControls
                }

                if mediaVM.player != nil {
                    // Playlist navigation (Server mode only)
                    if mediaVM.videoSourceMode == .serverSearch && !mediaVM.videoPlaylist.isEmpty {
                        if let name = currentVideoDisplayName, !name.isEmpty {
                            Text(name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                        if !currentVideoTags.isEmpty {
                            Text(currentVideoTags.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(mediaVM.videoPlaylistIndex + 1) / \(mediaVM.videoPlaylist.count) 本")
                            .font(.caption)

                        if mediaVM.currentVideoHash != nil {
                            favoriteRow(
                                current: mediaVM.videoCurrentFavorite,
                                busy: mediaVM.videoFavoriteBusy
                            ) { mediaVM.setVideoFavorite($0) }
                        }

                        HStack(spacing: 8) {
                            Button { mediaVM.videoPlaylistJump(by: -10) } label: {
                                Text("-10").font(.caption2)
                            }
                            .buttonStyle(.bordered)

                            Button { mediaVM.videoPlaylistPrev() } label: {
                                Image(systemName: "backward.fill")
                            }
                            .buttonStyle(.bordered)

                            Button { mediaVM.videoPlaylistNext() } label: {
                                Image(systemName: "forward.fill")
                            }
                            .buttonStyle(.bordered)

                            Button { mediaVM.videoPlaylistJump(by: 10) } label: {
                                Text("+10").font(.caption2)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

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

                    // Seek bar
                    if mediaVM.videoDuration > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { mediaVM.videoCurrentTime },
                                    set: { newValue in
                                        mediaVM.videoCurrentTime = newValue
                                        mediaVM.seekVideo(to: newValue)
                                    }
                                ),
                                in: 0...max(mediaVM.videoDuration, 1),
                                onEditingChanged: { editing in
                                    mediaVM.isSeeking = editing
                                }
                            )
                            HStack {
                                Text(formatTime(mediaVM.videoCurrentTime))
                                Spacer()
                                Text(formatTime(mediaVM.videoDuration))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
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

                    VStack(alignment: .leading) {
                        Text("パネル湾曲: \(videoCurveLabel)")
                        Slider(value: Binding(
                            get: { mediaVM.videoCurveAmount },
                            set: { mediaVM.videoCurveAmount = $0 }
                        ), in: -1.0...1.0, step: 0.05)
                        HStack {
                            Text("← 奥向き").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("まっすぐ").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("こちら向き →").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    // Repeat count (プレイリスト時、N回再生してから次へ)
                    VStack(alignment: .leading) {
                        Text("繰り返し再生: \(mediaVM.videoRepeatCount)回")
                        Slider(value: Binding(
                            get: { Double(mediaVM.videoRepeatCount) },
                            set: { mediaVM.videoRepeatCount = Int($0) }
                        ), in: 1...10, step: 1)
                        Text("プレイリスト再生時、この回数を再生したら次の動画へ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Background removal (立体視動画クロマキー, 試作)
                    Divider()
                    Toggle("背景透過 (クロマキー, 試作)", isOn: Binding(
                        get: { mediaVM.videoBackgroundRemovalEnabled },
                        set: {
                            mediaVM.videoBackgroundRemovalEnabled = $0
                            // マテリアル種別が変わるため動画パネルを作り直す。
                            mediaVM.videoVersion += 1
                        }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoBackgroundRemovalEnabled {
                        Text("立体視を保ったままキー色付近を透明化（試作・実機推奨）")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ColorPicker("キー色", selection: Binding(
                            get: {
                                let c = mediaVM.videoChromaKeyColor
                                return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                            },
                            set: { newColor in
                                let ui = UIColor(newColor)
                                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                                mediaVM.videoChromaKeyColor = SIMD3<Float>(Float(r), Float(g), Float(b))
                            }
                        ))

                        VStack(alignment: .leading) {
                            Text("透過範囲: \(Int(mediaVM.videoChromaThreshold * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.videoChromaThreshold },
                                set: { mediaVM.videoChromaThreshold = $0 }
                            ), in: 0.0...1.0, step: 0.01)
                        }

                        VStack(alignment: .leading) {
                            Text("縁のぼかし: \(Int(mediaVM.videoChromaSmoothness * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.videoChromaSmoothness },
                                set: { mediaVM.videoChromaSmoothness = $0 }
                            ), in: 0.0...0.5, step: 0.01)
                        }
                    }

                    // Foreground extraction (Vision 被写体マスク, 試作)
                    Toggle("前景抽出 (被写体, 試作)", isOn: Binding(
                        get: { mediaVM.videoForegroundKeyEnabled },
                        set: {
                            mediaVM.videoForegroundKeyEnabled = $0
                            mediaVM.videoVersion += 1 // パイプライン/マスク有効化のため作り直す
                        }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoForegroundKeyEnabled {
                        Text("被写体を残し背景を透明化（数フレームに1回マスク生成。動きの速い部分は輪郭が遅れます）")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text("抽出しきい値: \(Int(mediaVM.videoForegroundThreshold * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.videoForegroundThreshold },
                                set: { mediaVM.videoForegroundThreshold = $0 }
                            ), in: 0.0...1.0, step: 0.01)
                        }

                        VStack(alignment: .leading) {
                            Text("縁のぼかし: \(Int(mediaVM.videoForegroundFeather * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.videoForegroundFeather },
                                set: { mediaVM.videoForegroundFeather = $0 }
                            ), in: 0.0...0.3, step: 0.01)
                        }
                    }

                    // FPS デバッグ表示 (背景透過モード時)
                    if mediaVM.videoBackgroundRemovalEnabled || mediaVM.videoForegroundKeyEnabled {
                        HStack(spacing: 12) {
                            Label(String(format: "描画 %.0f fps", mediaVM.videoMeasuredFPS), systemImage: "speedometer")
                            if mediaVM.videoForegroundKeyEnabled {
                                Label(String(format: "マスク %.1f fps", mediaVM.videoMaskFPS), systemImage: "person.crop.rectangle")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    // Vertical bob controls
                    Toggle("上下運動", isOn: Binding(
                        get: { mediaVM.videoBobEnabled },
                        set: { mediaVM.videoBobEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoBobEnabled {
                        VStack(alignment: .leading) {
                            Text("上下幅: \(String(format: "%.2f", mediaVM.videoBobAmplitude))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoBobAmplitude },
                                set: { mediaVM.videoBobAmplitude = $0 }
                            ), in: 0.05...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("上下スピード: \(String(format: "%.2f", mediaVM.videoBobSpeed))Hz")
                            Slider(value: Binding(
                                get: { mediaVM.videoBobSpeed },
                                set: { mediaVM.videoBobSpeed = $0 }
                            ), in: 0.02...0.5, step: 0.02)
                        }
                    }

                    // Forward/back surge controls
                    Toggle("前後運動", isOn: Binding(
                        get: { mediaVM.videoSurgeEnabled },
                        set: { mediaVM.videoSurgeEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoSurgeEnabled {
                        VStack(alignment: .leading) {
                            Text("前後幅: \(String(format: "%.2f", mediaVM.videoSurgeAmplitude))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoSurgeAmplitude },
                                set: { mediaVM.videoSurgeAmplitude = $0 }
                            ), in: 0.05...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("前後スピード: \(String(format: "%.2f", mediaVM.videoSurgeSpeed))Hz")
                            Slider(value: Binding(
                                get: { mediaVM.videoSurgeSpeed },
                                set: { mediaVM.videoSurgeSpeed = $0 }
                            ), in: 0.02...0.5, step: 0.02)
                        }
                    }

                    // Left/right sway controls
                    Toggle("左右運動", isOn: Binding(
                        get: { mediaVM.videoSwayEnabled },
                        set: { mediaVM.videoSwayEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoSwayEnabled {
                        VStack(alignment: .leading) {
                            Text("左右幅: \(String(format: "%.2f", mediaVM.videoSwayAmplitude))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoSwayAmplitude },
                                set: { mediaVM.videoSwayAmplitude = $0 }
                            ), in: 0.05...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("左右スピード: \(String(format: "%.2f", mediaVM.videoSwaySpeed))Hz")
                            Slider(value: Binding(
                                get: { mediaVM.videoSwaySpeed },
                                set: { mediaVM.videoSwaySpeed = $0 }
                            ), in: 0.02...0.5, step: 0.02)
                        }
                    }

                    handFollowControls(
                        enabled: Binding(
                            get: { mediaVM.videoFollowHandEnabled },
                            set: { mediaVM.videoFollowHandEnabled = $0 }
                        ),
                        hand: Binding(
                            get: { mediaVM.videoFollowHand },
                            set: { mediaVM.videoFollowHand = $0 }
                        ),
                        height: Binding(
                            get: { mediaVM.videoFollowHandHeight },
                            set: { mediaVM.videoFollowHandHeight = $0 }
                        ),
                        lateral: Binding(
                            get: { mediaVM.videoFollowHandLateral },
                            set: { mediaVM.videoFollowHandLateral = $0 }
                        ),
                        depth: Binding(
                            get: { mediaVM.videoFollowHandDepth },
                            set: { mediaVM.videoFollowHandDepth = $0 }
                        )
                    )

                    // Face centering (連続顔追跡)
                    Toggle("顔を正面に配置 (連続追跡)", isOn: Binding(
                        get: { mediaVM.videoFaceCenterEnabled },
                        set: { mediaVM.videoFaceCenterEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.videoFaceCenterEnabled {
                        Text("再生中の顔を定期検出し、顔が頭の正面に来るようパネルがゆっくり追従します (実写向け・実機のみ)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text("距離: \(String(format: "%.1f", mediaVM.videoFaceDistance))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoFaceDistance },
                                set: { mediaVM.videoFaceDistance = $0 }
                            ), in: 0.5...4.0, step: 0.1)
                        }

                        VStack(alignment: .leading) {
                            Text("高さオフセット: \(String(format: "%+.2f", mediaVM.videoFaceHeight))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoFaceHeight },
                                set: { mediaVM.videoFaceHeight = $0 }
                            ), in: -1.0...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("水平オフセット: \(String(format: "%+.2f", mediaVM.videoFaceLateral))m")
                            Slider(value: Binding(
                                get: { mediaVM.videoFaceLateral },
                                set: { mediaVM.videoFaceLateral = $0 }
                            ), in: -1.0...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("検出間隔: \(String(format: "%.2f", mediaVM.videoFaceInterval))秒")
                            Slider(value: Binding(
                                get: { mediaVM.videoFaceInterval },
                                set: { mediaVM.videoFaceInterval = $0 }
                            ), in: 0.5...3.0, step: 0.25)
                        }
                    }

                }
            }
        }
    }

    // MARK: - Hand Follow Controls (shared by video & slideshow)

    /// 手の甲追従の ON/OFF + 左右の手 + 高さ/水平/奥行きオフセットの共通 UI。
    @ViewBuilder
    private func handFollowControls(
        enabled: Binding<Bool>,
        hand: Binding<FollowHand>,
        height: Binding<Float>,
        lateral: Binding<Float>,
        depth: Binding<Float>
    ) -> some View {
        Toggle("手の甲に追従", isOn: enabled)
            .toggleStyle(.switch)

        if enabled.wrappedValue {
            Text("パネルが手の甲の位置についてきます (実機のみ)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("追従する手", selection: hand) {
                ForEach(FollowHand.allCases) { h in
                    Text(h.displayName).tag(h)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("高さオフセット: \(String(format: "%.2f", height.wrappedValue))m")
                Slider(value: height, in: 0.0...1.0, step: 0.05)
            }

            VStack(alignment: .leading) {
                Text("水平オフセット: \(String(format: "%+.2f", lateral.wrappedValue))m")
                Slider(value: lateral, in: -1.0...1.0, step: 0.05)
                HStack {
                    Text("← 左").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("中央").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("右 →").font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading) {
                Text("奥行きオフセット: \(String(format: "%+.2f", depth.wrappedValue))m")
                Slider(value: depth, in: -1.0...1.0, step: 0.05)
                HStack {
                    Text("← 手前").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("中央").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("奥 →").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Slideshow Panel Controls

    @MainActor
    private var slideshowPanelSection: some View {
        @Bindable var appModel = appModel
        return VStack(spacing: 12) {
            Toggle("Slideshow Panel", isOn: Binding(
                get: { mediaVM.slideshowEnabled },
                set: { mediaVM.slideshowEnabled = $0 }
            ))
            .toggleStyle(.switch)

            if mediaVM.slideshowEnabled {
                Text("立体視対応スライドショーパネル")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Source mode picker
                Picker("Source", selection: Binding(
                    get: { mediaVM.slideshowSourceMode },
                    set: { mediaVM.slideshowSourceMode = $0 }
                )) {
                    ForEach(MediaPanelViewModel.SlideshowSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mediaVM.slideshowSourceMode == .localFolder {
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
                } else {
                    slideshowServerSearchControls
                }

                if !mediaVM.slideshowImages.isEmpty {
                    if let name = currentSlideshowDisplayName, !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    if !currentSlideshowTags.isEmpty {
                        Text(currentSlideshowTags.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(mediaVM.slideshowCurrentIndex + 1) / \(mediaVM.slideshowImages.count) 枚")
                        .font(.caption)

                    if mediaVM.slideshowIsStereo {
                        Label("立体視 (Stereo)", systemImage: "eye.trianglebadge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if mediaVM.slideshowSourceMode == .serverSearch, mediaVM.currentSlideshowHash != nil {
                        favoriteRow(
                            current: mediaVM.slideshowCurrentFavorite,
                            busy: mediaVM.slideshowFavoriteBusy
                        ) { mediaVM.setSlideshowFavorite($0) }
                    }

                    // Navigation controls
                    HStack(spacing: 8) {
                        Button { mediaVM.slideshowJump(by: -100) } label: {
                            Text("-100")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)

                        Button { mediaVM.slideshowJump(by: -10) } label: {
                            Text("-10")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)

                        Button { mediaVM.slideshowPrev() } label: {
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

                        Button { mediaVM.slideshowNext() } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(.bordered)

                        Button { mediaVM.slideshowJump(by: 10) } label: {
                            Text("+10")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)

                        Button { mediaVM.slideshowJump(by: 100) } label: {
                            Text("+100")
                                .font(.caption2)
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

                    VStack(alignment: .leading) {
                        Text("パネル湾曲: \(slideshowCurveLabel)")
                        Slider(value: Binding(
                            get: { mediaVM.slideshowCurveAmount },
                            set: { mediaVM.slideshowCurveAmount = $0 }
                        ), in: -1.0...1.0, step: 0.05)
                        HStack {
                            Text("← 奥向き").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("まっすぐ").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("こちら向き →").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    handFollowControls(
                        enabled: Binding(
                            get: { mediaVM.slideshowFollowHandEnabled },
                            set: { mediaVM.slideshowFollowHandEnabled = $0 }
                        ),
                        hand: Binding(
                            get: { mediaVM.slideshowFollowHand },
                            set: { mediaVM.slideshowFollowHand = $0 }
                        ),
                        height: Binding(
                            get: { mediaVM.slideshowFollowHandHeight },
                            set: { mediaVM.slideshowFollowHandHeight = $0 }
                        ),
                        lateral: Binding(
                            get: { mediaVM.slideshowFollowHandLateral },
                            set: { mediaVM.slideshowFollowHandLateral = $0 }
                        ),
                        depth: Binding(
                            get: { mediaVM.slideshowFollowHandDepth },
                            set: { mediaVM.slideshowFollowHandDepth = $0 }
                        )
                    )

                    // Face centering (顔を正面に配置)
                    Toggle("顔を正面に配置", isOn: Binding(
                        get: { mediaVM.slideshowFaceCenterEnabled },
                        set: { mediaVM.slideshowFaceCenterEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.slideshowFaceCenterEnabled {
                        Text("画像の顔を検出し、毎スライド頭の正面に顔が来るよう配置します (実写向け・実機のみ)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text("距離: \(String(format: "%.1f", mediaVM.slideshowFaceDistance))m")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowFaceDistance },
                                set: { mediaVM.slideshowFaceDistance = $0 }
                            ), in: 0.5...4.0, step: 0.1)
                        }

                        VStack(alignment: .leading) {
                            Text("高さオフセット: \(String(format: "%+.2f", mediaVM.slideshowFaceHeight))m")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowFaceHeight },
                                set: { mediaVM.slideshowFaceHeight = $0 }
                            ), in: -1.0...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading) {
                            Text("水平オフセット: \(String(format: "%+.2f", mediaVM.slideshowFaceLateral))m")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowFaceLateral },
                                set: { mediaVM.slideshowFaceLateral = $0 }
                            ), in: -1.0...1.0, step: 0.05)
                            HStack {
                                Text("← 左").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text("右 →").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Chroma key (背景透過)
                    Divider()
                    Toggle("背景透過 (クロマキー)", isOn: Binding(
                        get: { mediaVM.slideshowChromaKeyEnabled },
                        set: { mediaVM.slideshowChromaKeyEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.slideshowChromaKeyEnabled {
                        Text("立体視を保ったままキー色付近を透明化")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ColorPicker("キー色", selection: Binding(
                            get: {
                                let c = mediaVM.slideshowChromaKeyColor
                                return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                            },
                            set: { newColor in
                                let ui = UIColor(newColor)
                                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                                mediaVM.slideshowChromaKeyColor = SIMD3<Float>(Float(r), Float(g), Float(b))
                            }
                        ))

                        VStack(alignment: .leading) {
                            Text("透過範囲: \(Int(mediaVM.slideshowChromaThreshold * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowChromaThreshold },
                                set: { mediaVM.slideshowChromaThreshold = $0 }
                            ), in: 0.0...1.0, step: 0.01)
                        }

                        VStack(alignment: .leading) {
                            Text("縁のぼかし: \(Int(mediaVM.slideshowChromaSmoothness * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowChromaSmoothness },
                                set: { mediaVM.slideshowChromaSmoothness = $0 }
                            ), in: 0.0...0.5, step: 0.01)
                        }
                    }

                    // Foreground extraction (Vision 被写体マスクで背景透過)
                    Divider()
                    Toggle("前景抽出 (背景透過)", isOn: Binding(
                        get: { mediaVM.slideshowForegroundKeyEnabled },
                        set: { newValue in
                            mediaVM.slideshowForegroundKeyEnabled = newValue
                            // ON 時はマスク未生成のため現在画像を再読込して生成する。
                            // OFF 時もマスクを破棄するため再読込する。
                            mediaVM.loadCurrentSlideshowImage()
                        }
                    ))
                    .toggleStyle(.switch)

                    if mediaVM.slideshowForegroundKeyEnabled {
                        Text("被写体を残し背景を透明化（Vision被写体抽出。メートル単位の深度ではありません）")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text("抽出しきい値: \(Int(mediaVM.slideshowForegroundThreshold * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowForegroundThreshold },
                                set: { mediaVM.slideshowForegroundThreshold = $0 }
                            ), in: 0.0...1.0, step: 0.01)
                        }

                        VStack(alignment: .leading) {
                            Text("縁のぼかし: \(Int(mediaVM.slideshowForegroundFeather * 100))%")
                            Slider(value: Binding(
                                get: { mediaVM.slideshowForegroundFeather },
                                set: { mediaVM.slideshowForegroundFeather = $0 }
                            ), in: 0.0...0.3, step: 0.01)
                        }
                    }
                }
            }
        }
    }

    /// パネル湾曲スライダーの数値ラベル。0 近傍はフラット表記、それ以外は方向 + 倍率。
    private var slideshowCurveLabel: String {
        let v = mediaVM.slideshowCurveAmount
        if abs(v) < 0.01 { return "まっすぐ" }
        let pct = Int(round(abs(v) * 100))
        return v > 0 ? "こちら向き \(pct)%" : "奥向き \(pct)%"
    }

    /// 動画パネル湾曲スライダーの数値ラベル。
    private var videoCurveLabel: String {
        let v = mediaVM.videoCurveAmount
        if abs(v) < 0.01 { return "まっすぐ" }
        let pct = Int(round(abs(v) * 100))
        return v > 0 ? "こちら向き \(pct)%" : "奥向き \(pct)%"
    }

    // MARK: - Video Server Search Controls

    @MainActor
    private var videoServerSearchControls: some View {
        @Bindable var appModel = appModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("タグ (動画専用)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("例: character:frieren, rating:safe", text: $appModel.illustServerLastVideoTags)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("空欄にすると全件検索 (最大 500 本)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Button {
                    openWindow(id: "VideoTagPickerWindow")
                } label: {
                    Label("タグ一覧", systemImage: "tag")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                ForEach(["safe", "questionable", "explicit"], id: \.self) { r in
                    Toggle(isOn: videoRatingBinding(for: r)) {
                        Text(r).font(.caption2)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            dateFilterControls(
                sortOrder: sortOrderBinding(
                    get: { appModel.illustServerVideoDateSource },
                    set: { appModel.illustServerVideoDateSource = $0 }
                ),
                preset: datePresetBinding(
                    get: { appModel.illustServerVideoDatePreset },
                    set: { appModel.illustServerVideoDatePreset = $0 }
                )
            )

            favoriteFilterPicker(selection: Binding(
                get: { appModel.illustServerVideoFavoriteMin },
                set: { appModel.illustServerVideoFavoriteMin = $0 }
            ))

            Button {
                triggerVideoServerSearch()
            } label: {
                if mediaVM.videoServerSearchInProgress {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text("検索中…")
                    }
                } else {
                    Label("動画をサーバ検索", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                appModel.illustServerHost.trimmingCharacters(in: .whitespaces).isEmpty
                || mediaVM.videoServerSearchInProgress
            )

            if let err = mediaVM.videoServerSearchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if mediaVM.videoServerSearchDone {
                let tagsLabel = mediaVM.videoServerLastTags.isEmpty ? "タグなし" : mediaVM.videoServerLastTags
                Text("検索結果: \(mediaVM.videoServerTotalCount) 本 (\(tagsLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func videoRatingBinding(for value: String) -> Binding<Bool> {
        Binding(
            get: {
                let set = parseCommaList(appModel.illustServerLastVideoRatings)
                return set.contains(value)
            },
            set: { newValue in
                var set = parseCommaList(appModel.illustServerLastVideoRatings)
                if newValue {
                    set.insert(value)
                } else {
                    set.remove(value)
                }
                appModel.illustServerLastVideoRatings = set.sorted().joined(separator: ",")
            }
        )
    }

    private func triggerVideoServerSearch() {
        let tags = parseCommaList(appModel.illustServerLastVideoTags).sorted()
        let ratings = parseCommaList(appModel.illustServerLastVideoRatings).sorted()
        let sortOrder = ServerSortOrder(rawValue: appModel.illustServerVideoDateSource) ?? .filename
        let preset = DateRangePreset(rawValue: appModel.illustServerVideoDatePreset) ?? .all
        mediaVM.loadVideoPlaylistFromServer(
            host: appModel.illustServerHost,
            tags: tags,
            ratings: ratings,
            after: preset.afterEpoch(),
            sortOrder: sortOrder,
            favorite: appModel.illustServerVideoFavoriteMin
        )
    }

    // MARK: - Slideshow Server Search Controls

    @MainActor
    private var slideshowServerSearchControls: some View {
        @Bindable var appModel = appModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("タグ (カンマ区切り、AND 検索)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("例: character:frieren, rating:safe", text: $appModel.illustServerLastTags)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("空欄にすると全件検索 (最大 2000 件)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                openWindow(id: "ImageTagPickerWindow")
            } label: {
                Label("タグ一覧から選択", systemImage: "tag")
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                ForEach(["safe", "questionable", "explicit"], id: \.self) { r in
                    Toggle(isOn: ratingBinding(for: r)) {
                        Text(r).font(.caption)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            dateFilterControls(
                sortOrder: sortOrderBinding(
                    get: { appModel.illustServerImageDateSource },
                    set: { appModel.illustServerImageDateSource = $0 }
                ),
                preset: datePresetBinding(
                    get: { appModel.illustServerImageDatePreset },
                    set: { appModel.illustServerImageDatePreset = $0 }
                )
            )

            favoriteFilterPicker(selection: Binding(
                get: { appModel.illustServerImageFavoriteMin },
                set: { appModel.illustServerImageFavoriteMin = $0 }
            ))

            Button {
                triggerServerSearch()
            } label: {
                if mediaVM.slideshowServerSearchInProgress {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text("検索中…")
                    }
                } else {
                    Label("サーバ検索", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                appModel.illustServerHost.trimmingCharacters(in: .whitespaces).isEmpty
                || mediaVM.slideshowServerSearchInProgress
            )

            if let err = mediaVM.slideshowServerSearchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if mediaVM.slideshowServerSearchDone {
                let tagsLabel = mediaVM.slideshowServerLastTags.isEmpty ? "タグなし" : mediaVM.slideshowServerLastTags
                Text("検索結果: \(mediaVM.slideshowServerTotalCount) 件 (\(tagsLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func ratingBinding(for value: String) -> Binding<Bool> {
        Binding(
            get: {
                let set = parseCommaList(appModel.illustServerLastRatings)
                return set.contains(value)
            },
            set: { newValue in
                var set = parseCommaList(appModel.illustServerLastRatings)
                if newValue {
                    set.insert(value)
                } else {
                    set.remove(value)
                }
                appModel.illustServerLastRatings = set.sorted().joined(separator: ",")
            }
        )
    }

    private func triggerServerSearch() {
        let tags = parseCommaList(appModel.illustServerLastTags).sorted()
        let ratings = parseCommaList(appModel.illustServerLastRatings).sorted()
        let sortOrder = ServerSortOrder(rawValue: appModel.illustServerImageDateSource) ?? .filename
        let preset = DateRangePreset(rawValue: appModel.illustServerImageDatePreset) ?? .all
        mediaVM.loadSlideshowFromServer(
            host: appModel.illustServerHost,
            tags: tags,
            ratings: ratings,
            after: preset.afterEpoch(),
            sortOrder: sortOrder,
            favorite: appModel.illustServerImageFavoriteMin
        )
    }

    private func parseCommaList(_ s: String) -> Set<String> {
        Set(s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// 現在表示中スライドショー画像の displayName (ファイル名)。範囲外は nil。
    private var currentSlideshowDisplayName: String? {
        let idx = mediaVM.slideshowCurrentIndex
        guard idx >= 0, idx < mediaVM.slideshowImages.count else { return nil }
        return mediaVM.slideshowImages[idx].displayName
    }

    /// 現在再生中の動画プレイリスト要素の表示ラベル (作者名：ファイル名)。範囲外は nil。
    private var currentVideoDisplayName: String? {
        let idx = mediaVM.videoPlaylistIndex
        guard idx >= 0, idx < mediaVM.videoPlaylist.count else { return nil }
        return mediaVM.videoPlaylist[idx].displayName
    }

    /// 現在表示中スライドショー画像のタグ (サーバ検索由来のみ)。
    private var currentSlideshowTags: [String] {
        let idx = mediaVM.slideshowCurrentIndex
        guard idx >= 0, idx < mediaVM.slideshowImages.count else { return [] }
        return mediaVM.slideshowImages[idx].tags ?? []
    }

    /// 現在再生中の動画のタグ (サーバ検索由来のみ)。
    private var currentVideoTags: [String] {
        let idx = mediaVM.videoPlaylistIndex
        guard idx >= 0, idx < mediaVM.videoPlaylist.count else { return [] }
        return mediaVM.videoPlaylist[idx].tags ?? []
    }

    // MARK: - Favorite Controls (shared by slideshow & video)

    /// 現在表示中アイテムのお気に入り (1...10 のラベル) を設定する行。
    /// 選択中の番号だけが黄色でハイライトされ、もう一度押すと解除。
    @ViewBuilder
    private func favoriteRow(current: Int?, busy: Bool, set: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(current != nil ? "お気に入り: \(current!)" : "お気に入り: なし")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if busy {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Button {
                    set(nil)
                } label: {
                    Image(systemName: "xmark.circle").imageScale(.small)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .disabled(current == nil || busy)
            }
            HStack(spacing: 2) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        set(n == current ? nil : n)
                    } label: {
                        Text("\(n)")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(n == current ? .yellow : .secondary)
                    .disabled(busy)
                }
            }
        }
    }

    /// 検索用のお気に入りフィルター (0 = なし、N = その番号のみ表示)。
    @ViewBuilder
    private func favoriteFilterPicker(selection: Binding<Int>) -> some View {
        HStack {
            Text("お気に入り")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("お気に入りフィルター", selection: selection) {
                Text("フィルタなし").tag(0)
                ForEach(1...10, id: \.self) { n in
                    Text("\(n) のみ").tag(n)
                }
            }
            .pickerStyle(.menu)
            Spacer()
        }
    }

    // MARK: - Sort / Date Filter Controls (shared by slideshow & video)

    /// 並び順 segmented + 期間ショートカット 5 ボタンの共通 UI。
    @ViewBuilder
    private func dateFilterControls(sortOrder: Binding<ServerSortOrder>, preset: Binding<DateRangePreset>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("並び順・期間フィルター")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("並び順", selection: sortOrder) {
                ForEach(ServerSortOrder.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 4) {
                ForEach(DateRangePreset.allCases) { p in
                    Button {
                        preset.wrappedValue = p
                    } label: {
                        Text(p.displayName)
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(preset.wrappedValue == p ? .accentColor : .secondary)
                }
            }
        }
    }

    private func sortOrderBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<ServerSortOrder> {
        Binding(
            get: { ServerSortOrder(rawValue: get()) ?? .filename },
            set: { set($0.rawValue) }
        )
    }

    private func datePresetBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<DateRangePreset> {
        Binding(
            get: { DateRangePreset(rawValue: get()) ?? .all },
            set: { set($0.rawValue) }
        )
    }

    // MARK: - Color Mode Controls

    @MainActor
    private var colorModeSection: some View {
        VStack(spacing: 12) {
            Toggle("Video Color Mode", isOn: Binding(
                get: { appModel.videoColorMode },
                set: { appModel.videoColorMode = $0 }
            ))
            .toggleStyle(.switch)

            if appModel.videoColorMode {
                Text("パネルの端の色を部屋に反映します")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Color Source", selection: Binding(
                    get: { appModel.colorSource },
                    set: { appModel.colorSource = $0 }
                )) {
                    ForEach(AppModel.ColorSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    let top = appModel.colorSource == .slideshow ? mediaVM.slideshowColorTop : mediaVM.videoColorTop
                    let mid = appModel.colorSource == .slideshow ? mediaVM.slideshowColorMiddle : mediaVM.videoColorMiddle
                    let bot = appModel.colorSource == .slideshow ? mediaVM.slideshowColorBottom : mediaVM.videoColorBottom

                    VStack(spacing: 2) {
                        Circle().fill(Color(
                            red: Double(top.x), green: Double(top.y), blue: Double(top.z)
                        )).frame(width: 20, height: 20)
                        Text("天井").font(.caption2)
                    }
                    VStack(spacing: 2) {
                        Circle().fill(Color(
                            red: Double(mid.x), green: Double(mid.y), blue: Double(mid.z)
                        )).frame(width: 20, height: 20)
                        Text("壁").font(.caption2)
                    }
                    VStack(spacing: 2) {
                        Circle().fill(Color(
                            red: Double(bot.x), green: Double(bot.y), blue: Double(bot.z)
                        )).frame(width: 20, height: 20)
                        Text("床").font(.caption2)
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let totalSeconds = Int(seconds)
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
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
