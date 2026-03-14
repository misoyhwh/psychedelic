import SwiftUI
import RealityKit
@preconcurrency import ARKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AudioReactiveEngine.self) private var audioEngine
    @State private var sceneReconstructor = SceneReconstructor()
    @State private var occlusionPanel = OcclusionPanelManager()

    var body: some View {
        RealityView { content in
            sceneReconstructor.configure(audioEngine: audioEngine)
            content.add(sceneReconstructor.rootEntity)
            content.add(occlusionPanel.rootEntity)
            await sceneReconstructor.start()
        } update: { content in
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
        }
        .gesture(dragGesture)
        .task {
            await sceneReconstructor.processUpdates()
        }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .targetedToEntity(occlusionPanel.panelEntity)
            .onChanged { value in
                // Convert the 3D drag location to scene coordinates
                let pos = value.convert(value.location3D, from: .local, to: occlusionPanel.rootEntity)
                occlusionPanel.panelEntity.position = pos
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
