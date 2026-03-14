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

    // Slideshow panel entities
    @State private var slideshowRootEntity = Entity()
    @State private var slideshowEntity: ModelEntity?

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
            // Psychedelic parameters
            let filter: Set<MeshAnchor.MeshClassification>?
            if appModel.meshClassificationFilterEnabled {
                var f: Set<MeshAnchor.MeshClassification> = []
                if appModel.meshFilterWall { f.insert(.wall) }
                if appModel.meshFilterFloor { f.insert(.floor) }
                if appModel.meshFilterCeiling { f.insert(.ceiling) }
                if appModel.meshFilterTable { f.insert(.table) }
                if appModel.meshFilterSeat { f.insert(.seat) }
                if appModel.meshFilterWindow { f.insert(.window) }
                if appModel.meshFilterDoor { f.insert(.door) }
                if appModel.meshFilterOther { f.insert(.none) }
                filter = f
            } else {
                filter = nil
            }

            sceneReconstructor.updateParameters(
                speed: appModel.speed,
                intensity: appModel.intensity,
                style: appModel.patternStyle,
                particlesEnabled: appModel.particlesEnabled,
                audioReactiveEnabled: appModel.audioReactiveEnabled,
                audioSensitivity: appModel.audioSensitivity,
                autoPulseEnabled: appModel.autoPulseEnabled,
                classificationFilter: filter
            )
            occlusionPanel.update(
                enabled: appModel.occlusionPanelEnabled,
                width: appModel.occlusionPanelWidth,
                height: appModel.occlusionPanelHeight,
                rotationDegrees: appModel.occlusionPanelRotation
            )

            // Video panel enabled/disabled
            videoRootEntity.isEnabled = mediaVM.videoEnabled && mediaVM.player != nil

            // Video rotation
            let videoYaw = simd_quatf(angle: mediaVM.videoRotationH * .pi / 180, axis: [0, 1, 0])
            let videoPitch = simd_quatf(angle: mediaVM.videoRotationV * .pi / 180, axis: [1, 0, 0])
            videoRootEntity.orientation = videoYaw * videoPitch

            // Slideshow panel enabled/disabled
            slideshowRootEntity.isEnabled = mediaVM.slideshowEnabled && mediaVM.slideshowTexture != nil

            // Slideshow rotation
            let ssYaw = simd_quatf(angle: mediaVM.slideshowRotationH * .pi / 180, axis: [0, 1, 0])
            let ssPitch = simd_quatf(angle: mediaVM.slideshowRotationV * .pi / 180, axis: [1, 0, 0])
            slideshowRootEntity.orientation = ssYaw * ssPitch
        }
        .gesture(occlusionDragGesture)
        .gesture(panelDragGesture)
        .task {
            await sceneReconstructor.processUpdates()
        }
        .onChange(of: mediaVM.videoVersion) {
            recreateVideoEntity()
        }
        .onChange(of: mediaVM.slideshowTextureVersion) {
            recreateSlideshowEntity()
        }
    }

    // MARK: - Video Entity

    private func recreateVideoEntity() {
        // Remove old
        videoEntity?.removeFromParent()
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
    }

    // MARK: - Slideshow Entity

    private func recreateSlideshowEntity() {
        slideshowEntity?.removeFromParent()
        slideshowEntity = nil

        guard let leftTexture = mediaVM.slideshowTexture else { return }

        let width = Float(mediaVM.slideshowDisplaySize.width)
        let height = Float(mediaVM.slideshowDisplaySize.height)
        let mesh = MeshResource.generatePlane(width: width, height: height)

        var material: RealityKit.Material

        if mediaVM.slideshowIsStereo, let rightTexture = mediaVM.slideshowRightTexture {
            // Stereo: use ShaderGraph material with CameraIndexSwitch
            do {
                var stereoMaterial = try ShaderGraphMaterial(
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
            // Mono: use UnlitMaterial
            var monoMaterial = UnlitMaterial()
            monoMaterial.color = .init(tint: .white, texture: .init(leftTexture))
            material = monoMaterial
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: height, depth: 0.01)]))
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.name = "slideshowPanel"

        slideshowRootEntity.addChild(entity)
        slideshowEntity = entity
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
