import SwiftUI
import RealityKit
@preconcurrency import ARKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AudioReactiveEngine.self) private var audioEngine
    @Environment(MediaPanelViewModel.self) private var mediaVM
    @State private var sceneReconstructor = SceneReconstructor()
    @State private var occlusionPanel = OcclusionPanelManager()

    // Video panel entities
    @State private var videoRootEntity = Entity()
    @State private var videoEntity: ModelEntity?
    @State private var videoInitialScale: Float = 1.0
    @State private var videoBobBaseY: Float = 1.5
    @State private var videoSurgeBaseZ: Float = -2.0
    @State private var videoSwayBaseX: Float = 0.0
    @State private var videoMotionTimer: Timer?
    @State private var videoMotionStartTime: Date?

    // Slideshow panel entities
    @State private var slideshowRootEntity = Entity()
    @State private var slideshowEntity: ModelEntity?
    @State private var slideshowInitialScale: Float = 1.0

    var body: some View {
        RealityView { content in
            sceneReconstructor.configure(audioEngine: audioEngine)
            content.add(sceneReconstructor.rootEntity)
            content.add(occlusionPanel.rootEntity)

            // Video panel root
            videoRootEntity.position = SIMD3<Float>(0, 1.5, -2.0)
            videoRootEntity.isEnabled = false
            content.add(videoRootEntity)

            // Slideshow panel root
            slideshowRootEntity.position = SIMD3<Float>(1.8, 1.5, -2.0)
            slideshowRootEntity.isEnabled = false
            content.add(slideshowRootEntity)

            await sceneReconstructor.start()
        } update: { content in
            // Read mediaVM properties to register SwiftUI observation
            // (ensures onChange handlers fire reliably)
            let _ = mediaVM.videoVersion
            let _ = mediaVM.videoEnabled
            let _ = mediaVM.videoRotationH
            let _ = mediaVM.videoRotationV
            let _ = mediaVM.videoBobEnabled
            let _ = mediaVM.videoSurgeEnabled
            let _ = mediaVM.videoSwayEnabled
            let _ = mediaVM.slideshowTextureVersion
            let _ = mediaVM.slideshowEnabled
            let _ = mediaVM.slideshowRotationH
            let _ = mediaVM.slideshowRotationV
            let _ = mediaVM.videoColorTop
            let _ = mediaVM.videoColorMiddle
            let _ = mediaVM.videoColorBottom
            let _ = mediaVM.slideshowColorTop
            let _ = mediaVM.slideshowColorMiddle
            let _ = mediaVM.slideshowColorBottom

            // MARK: - Psychedelic parameters
            let filter: Set<MeshAnchor.MeshClassification>?
            if appModel.meshClassificationFilterEnabled {
                var f: Set<MeshAnchor.MeshClassification> = []
                if appModel.meshFilterWall { f.insert(.wall) }
                if appModel.meshFilterFloor { f.insert(.floor) }
                if appModel.meshFilterStairs { f.insert(.stairs) }
                if appModel.meshFilterBed { f.insert(.bed) }
                if appModel.meshFilterCeiling { f.insert(.ceiling) }
                if appModel.meshFilterTable { f.insert(.table) }
                if appModel.meshFilterSeat { f.insert(.seat) }
                if appModel.meshFilterCabinet { f.insert(.cabinet) }
                if appModel.meshFilterWindow { f.insert(.window) }
                if appModel.meshFilterDoor { f.insert(.door) }
                if appModel.meshFilterHomeAppliance { f.insert(.homeAppliance) }
                if appModel.meshFilterTV { f.insert(.tv) }
                if appModel.meshFilterPlant { f.insert(.plant) }
                if appModel.meshFilterOther { f.insert(.none) }
                filter = f
            } else {
                filter = nil
            }

            // Select color source
            let colorTop: SIMD3<Float>
            let colorMiddle: SIMD3<Float>
            let colorBottom: SIMD3<Float>
            if appModel.colorSource == .slideshow {
                colorTop = mediaVM.slideshowColorTop
                colorMiddle = mediaVM.slideshowColorMiddle
                colorBottom = mediaVM.slideshowColorBottom
            } else {
                colorTop = mediaVM.videoColorTop
                colorMiddle = mediaVM.videoColorMiddle
                colorBottom = mediaVM.videoColorBottom
            }

            sceneReconstructor.updateParameters(
                speed: appModel.speed,
                intensity: appModel.intensity,
                style: appModel.patternStyle,
                opacity: appModel.opacity,
                particlesEnabled: appModel.particlesEnabled,
                audioReactiveEnabled: appModel.audioReactiveEnabled,
                audioSensitivity: appModel.audioSensitivity,
                autoPulseEnabled: appModel.autoPulseEnabled,
                classificationFilter: filter,
                videoColorMode: appModel.videoColorMode,
                videoColorTop: colorTop,
                videoColorMiddle: colorMiddle,
                videoColorBottom: colorBottom
            )
            occlusionPanel.update(
                enabled: appModel.occlusionPanelEnabled,
                width: appModel.occlusionPanelWidth,
                height: appModel.occlusionPanelHeight,
                rotationDegrees: appModel.occlusionPanelRotation
            )
        }
        .onDisappear {
            videoMotionTimer?.invalidate()
            videoMotionTimer = nil
        }
        .gesture(occlusionDragGesture)
        .gesture(panelDragGesture)
        .gesture(panelMagnifyGesture)
        .task {
            await sceneReconstructor.processUpdates()
        }
        // MARK: - Video panel onChange handlers
        .onChange(of: mediaVM.videoVersion) {
            recreateVideoEntity()
            updateVideoVisibility()
        }
        .onChange(of: mediaVM.videoEnabled) {
            updateVideoVisibility()
        }
        .onChange(of: mediaVM.videoRotationH) {
            updateVideoRotation()
        }
        .onChange(of: mediaVM.videoRotationV) {
            updateVideoRotation()
        }
        .onChange(of: mediaVM.videoBobEnabled) {
            updateVideoMotion()
        }
        .onChange(of: mediaVM.videoSurgeEnabled) {
            updateVideoMotion()
        }
        .onChange(of: mediaVM.videoSwayEnabled) {
            updateVideoMotion()
        }
        // MARK: - Slideshow panel onChange handlers
        .onChange(of: mediaVM.slideshowTextureVersion) {
            recreateSlideshowEntity()
        }
        .onChange(of: mediaVM.slideshowEnabled) {
            updateSlideshowVisibility()
        }
        .onChange(of: mediaVM.slideshowRotationH) {
            updateSlideshowRotation()
        }
        .onChange(of: mediaVM.slideshowRotationV) {
            updateSlideshowRotation()
        }
    }

    // MARK: - Video Entity

    private func recreateVideoEntity() {
        // Remove ALL children to prevent entity accumulation
        for child in videoRootEntity.children {
            child.removeFromParent()
        }
        videoEntity = nil

        guard let player = mediaVM.player else { return }

        let width = Float(mediaVM.videoSize.width)
        let height = Float(mediaVM.videoSize.height)

        let mesh = MeshResource.generatePlane(width: width, height: height)
        let material = VideoMaterial(avPlayer: player)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        entity.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: height, depth: 0.01)]))
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.name = "videoPanel"

        videoRootEntity.addChild(entity)
        videoEntity = entity
        print("Video entity created: \(width)x\(height)")
    }

    private func updateVideoVisibility() {
        let shouldShow = mediaVM.videoEnabled && mediaVM.player != nil
        videoRootEntity.isEnabled = shouldShow
        print("Video visibility: \(shouldShow), enabled=\(mediaVM.videoEnabled), player=\(mediaVM.player != nil)")
    }

    private func updateVideoRotation() {
        let yaw = simd_quatf(angle: mediaVM.videoRotationH * .pi / 180, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: mediaVM.videoRotationV * .pi / 180, axis: [1, 0, 0])
        videoRootEntity.orientation = yaw * pitch
    }

    private func updateVideoMotion() {
        videoMotionTimer?.invalidate()
        videoMotionTimer = nil
        videoMotionStartTime = nil

        let bobEnabled = mediaVM.videoBobEnabled
        let surgeEnabled = mediaVM.videoSurgeEnabled
        let swayEnabled = mediaVM.videoSwayEnabled

        guard bobEnabled || surgeEnabled || swayEnabled else { return }

        if bobEnabled { videoBobBaseY = videoRootEntity.position.y }
        if surgeEnabled { videoSurgeBaseZ = videoRootEntity.position.z }
        if swayEnabled { videoSwayBaseX = videoRootEntity.position.x }
        let startTime = Date()
        videoMotionStartTime = startTime

        // Capture references to avoid retaining the entire view
        let rootEntity = videoRootEntity
        let vm = mediaVM
        var baseY = videoBobBaseY
        var baseZ = videoSurgeBaseZ
        var baseX = videoSwayBaseX

        videoMotionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let elapsed = Float(Date().timeIntervalSince(startTime))
            if vm.videoBobEnabled {
                let offsetY = sin(elapsed * vm.videoBobSpeed * 2 * .pi) * vm.videoBobAmplitude
                rootEntity.position.y = baseY + offsetY
            }
            if vm.videoSurgeEnabled {
                let offsetZ = sin(elapsed * vm.videoSurgeSpeed * 2 * .pi) * vm.videoSurgeAmplitude
                rootEntity.position.z = baseZ + offsetZ
            }
            if vm.videoSwayEnabled {
                let offsetX = sin(elapsed * vm.videoSwaySpeed * 2 * .pi) * vm.videoSwayAmplitude
                rootEntity.position.x = baseX + offsetX
            }
        }
    }

    // MARK: - Slideshow Entity

    private func recreateSlideshowEntity() {
        // Remove ALL children to prevent entity accumulation
        for child in slideshowRootEntity.children {
            child.removeFromParent()
        }
        slideshowEntity = nil

        guard let leftTexture = mediaVM.slideshowTexture else { return }

        let width = Float(mediaVM.slideshowDisplaySize.width)
        let height = Float(mediaVM.slideshowDisplaySize.height)

        Task {
            let mesh = MeshResource.generatePlane(width: width, height: height)
            var material: RealityKit.Material

            if mediaVM.slideshowIsStereo, let rightTexture = mediaVM.slideshowRightTexture {
                do {
                    var stereoMaterial = try await ShaderGraphMaterial(
                        named: "/Root/StereoImageMaterial",
                        from: "StereoImageMaterial",
                        in: realityKitContentBundle
                    )
                    try stereoMaterial.setParameter(name: "LeftImage", value: .textureResource(leftTexture))
                    try stereoMaterial.setParameter(name: "RightImage", value: .textureResource(rightTexture))
                    material = stereoMaterial
                } catch {
                    print("Failed to load stereo material: \(error)")
                    var fallback = UnlitMaterial()
                    fallback.color = .init(tint: .white, texture: .init(leftTexture))
                    material = fallback
                }
            } else {
                var monoMaterial = UnlitMaterial()
                monoMaterial.color = .init(tint: .white, texture: .init(leftTexture))
                material = monoMaterial
            }

            // Check again in case a newer update arrived while awaiting
            for child in slideshowRootEntity.children {
                child.removeFromParent()
            }

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: height, depth: 0.01)]))
            entity.components.set(InputTargetComponent(allowedInputTypes: .all))
            entity.name = "slideshowPanel"

            slideshowRootEntity.addChild(entity)
            slideshowEntity = entity
            updateSlideshowVisibility()
            print("Slideshow entity created: \(width)x\(height), stereo=\(mediaVM.slideshowIsStereo)")
        }
    }

    private func updateSlideshowVisibility() {
        let shouldShow = mediaVM.slideshowEnabled && mediaVM.slideshowTexture != nil
        slideshowRootEntity.isEnabled = shouldShow
        print("Slideshow visibility: \(shouldShow)")
    }

    private func updateSlideshowRotation() {
        let yaw = simd_quatf(angle: mediaVM.slideshowRotationH * .pi / 180, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: mediaVM.slideshowRotationV * .pi / 180, axis: [1, 0, 0])
        slideshowRootEntity.orientation = yaw * pitch
    }

    // MARK: - Gestures

    var occlusionDragGesture: some Gesture {
        DragGesture()
            .targetedToEntity(occlusionPanel.panelEntity)
            .onChanged { value in
                let pos = value.convert(value.location3D, from: .local, to: occlusionPanel.rootEntity)
                occlusionPanel.panelEntity.position = pos
            }
    }

    var panelMagnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let entity = value.entity as? ModelEntity,
                      (entity.name == "videoPanel" || entity.name == "slideshowPanel"),
                      let root = entity.parent else { return }

                let initialScale: Float
                if entity.name == "videoPanel" {
                    initialScale = videoInitialScale
                } else {
                    initialScale = slideshowInitialScale
                }

                let newScale = initialScale * Float(value.magnification)
                root.scale = SIMD3<Float>(repeating: max(0.1, min(newScale, 5.0)))
            }
            .onEnded { value in
                guard let entity = value.entity as? ModelEntity,
                      (entity.name == "videoPanel" || entity.name == "slideshowPanel"),
                      let root = entity.parent else { return }

                if entity.name == "videoPanel" {
                    videoInitialScale = root.scale.x
                } else {
                    slideshowInitialScale = root.scale.x
                }
            }
    }

    var panelDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let entity = value.entity as? ModelEntity,
                      (entity.name == "videoPanel" || entity.name == "slideshowPanel"),
                      let root = entity.parent else { return }

                let translation = value.translation3D
                let deltaX = Float(translation.x) * 0.00005
                let deltaY = Float(-translation.y) * 0.00005
                let deltaZ = Float(translation.z) * 0.00005

                root.position.x += deltaX
                root.position.y += deltaY
                root.position.z += deltaZ
            }
    }
}

// MARK: - Occlusion Panel Manager

@MainActor
class OcclusionPanelManager {
    let rootEntity = Entity()
    let panelEntity: ModelEntity

    private var currentEnabled = false
    private var currentWidth: Float = 1.0
    private var currentHeight: Float = 0.6
    private var currentRotation: Float = 0

    init() {
        let mesh = MeshResource.generatePlane(width: 1.0, height: 0.6)
        let material = OcclusionMaterial()
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3<Float>(0, 1.2, -2.0)
        entity.components.set(InputTargetComponent())
        entity.collision = CollisionComponent(shapes: [.generateBox(width: 1.0, height: 0.6, depth: 0.01)])
        entity.isEnabled = false
        self.panelEntity = entity
        rootEntity.addChild(entity)
    }

    func update(enabled: Bool, width: Float, height: Float, rotationDegrees: Float) {
        if enabled != currentEnabled {
            currentEnabled = enabled
            panelEntity.isEnabled = enabled
        }

        if width != currentWidth || height != currentHeight {
            currentWidth = width
            currentHeight = height
            let mesh = MeshResource.generatePlane(width: width, height: height)
            panelEntity.model?.mesh = mesh
            panelEntity.collision = CollisionComponent(
                shapes: [.generateBox(width: width, height: height, depth: 0.01)]
            )
        }

        if rotationDegrees != currentRotation {
            currentRotation = rotationDegrees
            let radians = rotationDegrees * .pi / 180.0
            panelEntity.orientation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        }
    }
}
