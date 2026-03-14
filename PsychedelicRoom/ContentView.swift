import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AudioReactiveEngine.self) private var audioEngine
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow

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
                    // Auto Pulse toggle (for when mic can't capture device audio)
                    Toggle("Auto Pulse (BPMモード)", isOn: $appModel.autoPulseEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: appModel.autoPulseEnabled) { _, enabled in
                            audioEngine.autoPulseEnabled = enabled
                            // Restart engine with new mode
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

            // Browser & Video buttons
            HStack(spacing: 12) {
                Button {
                    openWindow(id: "BrowserWindow")
                } label: {
                    Label("Browser", systemImage: "globe")
                }
                .buttonStyle(.bordered)

                Button {
                    openWindow(id: "VideoPlayerWindow")
                } label: {
                    Label("Video Player", systemImage: "film")
                }
                .buttonStyle(.bordered)
            }

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
