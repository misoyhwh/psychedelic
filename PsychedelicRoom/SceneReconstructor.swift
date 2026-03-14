import RealityKit
import ARKit
import SwiftUI
import QuartzCore

@Observable
@MainActor
class SceneReconstructor {
    let rootEntity = Entity()
    private let session = ARKitSession()
    private let sceneReconstruction = SceneReconstructionProvider(modes: [.classification])
    private var meshEntities: [UUID: ModelEntity] = [:]
    private var currentTime: Float = 0
    private var displayLink: CADisplayLink?
    private var speed: Float = 1.0
    private var intensity: Float = 1.0
    private var style: AppModel.PatternStyle = .psychedelic
    private var textureGenerator: TextureGenerator?
    private var particleSystem = ParticleSystem()
    private var frameCount: Int = 0
    private var particlesEnabled: Bool = true
    private var opacity: Float = 0.75
    private var audioReactiveEnabled: Bool = false
    private var audioSensitivity: Float = 1.0
    private var audioEngine: AudioReactiveEngine?
    private var audioLevel: Float = 0
    private var bassLevel: Float = 0
    private var trebleLevel: Float = 0
    // nil = show all faces (no filtering), non-nil = filter by classification
    private var classificationFilter: Set<MeshAnchor.MeshClassification>? = nil
    private var anchorCache: [UUID: MeshAnchor] = [:]

    func start() async {
        guard SceneReconstructionProvider.isSupported else {
            print("SceneReconstructionProvider is not supported on this device.")
            return
        }

        textureGenerator = TextureGenerator()
        rootEntity.addChild(particleSystem.rootEntity)

        do {
            try await session.run([sceneReconstruction])
            startDisplayLink()
        } catch {
            print("Failed to start ARKit session: \(error)")
        }
    }

    func processUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let anchor = update.anchor

            // Feed floor anchors to particle system
            particleSystem.updateFloorAnchor(anchor, event: update.event)

            switch update.event {
            case .added:
                anchorCache[anchor.id] = anchor
                if let entity = try? await createMeshEntity(from: anchor) {
                    meshEntities[anchor.id] = entity
                    rootEntity.addChild(entity)
                }

            case .updated:
                anchorCache[anchor.id] = anchor
                if let existingEntity = meshEntities[anchor.id] {
                    existingEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                    if let newMesh = try? await generateFilteredMeshResource(from: anchor) {
                        existingEntity.model?.mesh = newMesh
                    }
                }

            case .removed:
                anchorCache.removeValue(forKey: anchor.id)
                if let entity = meshEntities.removeValue(forKey: anchor.id) {
                    entity.removeFromParent()
                }
            }
        }
    }

    func configure(audioEngine: AudioReactiveEngine) {
        self.audioEngine = audioEngine
    }

    func updateParameters(speed: Float, intensity: Float, style: AppModel.PatternStyle,
                          opacity: Float, particlesEnabled: Bool, audioReactiveEnabled: Bool,
                          audioSensitivity: Float, autoPulseEnabled: Bool,
                          classificationFilter: Set<MeshAnchor.MeshClassification>?) {
        self.speed = speed
        self.intensity = intensity
        self.style = style
        self.opacity = opacity
        self.particlesEnabled = particlesEnabled
        self.audioReactiveEnabled = audioReactiveEnabled
        self.audioSensitivity = audioSensitivity
        if self.classificationFilter != classificationFilter {
            self.classificationFilter = classificationFilter
            rebuildAllMeshes()
        }
    }

    private func pullAudioLevels() {
        guard audioReactiveEnabled, let engine = audioEngine else { return }
        // AudioReactiveEngine now updates itself via its own DisplayLink
        // We just read the latest values
        audioLevel = engine.audioLevel
        bassLevel = engine.bassLevel
        trebleLevel = engine.trebleLevel
    }

    // MARK: - Mesh Creation

    private func createMeshEntity(from anchor: MeshAnchor) async throws -> ModelEntity {
        let meshResource = try await generateFilteredMeshResource(from: anchor)
        let material = getOrCreateMaterial()
        let entity = ModelEntity(mesh: meshResource, materials: [material])
        entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        return entity
    }

    private func rebuildAllMeshes() {
        Task {
            for (id, anchor) in anchorCache {
                guard let entity = meshEntities[id] else { continue }
                if let newMesh = try? await generateFilteredMeshResource(from: anchor) {
                    entity.model?.mesh = newMesh
                }
            }
        }
    }

    private func generateFilteredMeshResource(from anchor: MeshAnchor) async throws -> MeshResource {
        let meshGeometry = anchor.geometry

        // Read all positions
        let vertices = meshGeometry.vertices
        let positionData = vertices.buffer.contents()
        var allPositions: [SIMD3<Float>] = []
        for i in 0..<vertices.count {
            let pointer = positionData.advanced(by: vertices.offset + i * vertices.stride)
            allPositions.append(pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee)
        }

        // Read all normals
        let normals = meshGeometry.normals
        let normalData = normals.buffer.contents()
        var allNormals: [SIMD3<Float>] = []
        for i in 0..<normals.count {
            let pointer = normalData.advanced(by: normals.offset + i * normals.stride)
            allNormals.append(pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee)
        }

        // Read all face indices
        let faces = meshGeometry.faces
        let faceData = faces.buffer.contents()
        let bytesPerIndex = faces.bytesPerIndex
        let indicesPerFace = faces.primitive.indexCount

        // Build indices — optionally filter by classification
        var filteredIndices: [UInt32] = []

        if let activeFilter = classificationFilter,
           let classifications = meshGeometry.classifications {
            // Classification filter mode: only include faces matching selected types
            let classData = classifications.buffer.contents()
            for faceIndex in 0..<faces.count {
                let classPointer = classData.advanced(by: classifications.offset + faceIndex * classifications.stride)
                let classRawValue = classPointer.assumingMemoryBound(to: UInt8.self).pointee
                let classification = MeshAnchor.MeshClassification(rawValue: Int(classRawValue)) ?? .none

                guard activeFilter.contains(classification) else { continue }

                for j in 0..<indicesPerFace {
                    let idx = faceIndex * indicesPerFace + j
                    let pointer = faceData.advanced(by: idx * bytesPerIndex)
                    if bytesPerIndex == 4 {
                        filteredIndices.append(pointer.assumingMemoryBound(to: UInt32.self).pointee)
                    } else if bytesPerIndex == 2 {
                        filteredIndices.append(UInt32(pointer.assumingMemoryBound(to: UInt16.self).pointee))
                    }
                }
            }
        } else {
            // All-mesh mode: include every face (covers everything)
            for i in 0..<(faces.count * indicesPerFace) {
                let pointer = faceData.advanced(by: i * bytesPerIndex)
                if bytesPerIndex == 4 {
                    filteredIndices.append(pointer.assumingMemoryBound(to: UInt32.self).pointee)
                } else if bytesPerIndex == 2 {
                    filteredIndices.append(UInt32(pointer.assumingMemoryBound(to: UInt16.self).pointee))
                }
            }
        }

        // Build UVs from positions
        var uvs: [SIMD2<Float>] = []
        for position in allPositions {
            let u = (position.x + position.z) * 0.5
            let v = (position.y + position.z) * 0.5
            uvs.append(SIMD2<Float>(u, v))
        }

        var descriptor = MeshDescriptor(name: "SceneMesh")
        descriptor.positions = MeshBuffer(allPositions)
        descriptor.normals = MeshBuffer(allNormals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(filteredIndices)

        return try await MeshResource(from: [descriptor])
    }

    // MARK: - Material

    private var styleIndex: Int {
        switch style {
        case .psychedelic: return 0
        case .fractal: return 1
        case .miku39: return 2
        case .rainbow: return 3
        case .aurora: return 4
        case .voronoi: return 5
        case .interference: return 6
        case .hexTunnel: return 7
        case .organic: return 8
        case .sparkles: return 9
        case .hearts: return 10
        case .caustic: return 11
        }
    }

    private var cachedMaterial: UnlitMaterial?
    private var lastCachedOpacity: Float = -1

    private func getOrCreateMaterial() -> UnlitMaterial {
        if let cachedMaterial, !audioReactiveEnabled, lastCachedOpacity == opacity {
            return cachedMaterial
        }
        var material = UnlitMaterial()
        if let texture = textureGenerator?.textureResource {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: .init(red: 1, green: 0, blue: 1, alpha: 0.8))
        }

        // Audio-reactive opacity: base from slider, boosted by bass * sensitivity
        let effectiveOpacity: Float
        if audioReactiveEnabled {
            effectiveOpacity = min(opacity * 0.4 + bassLevel * 0.65 * audioSensitivity, 1.0)
        } else {
            effectiveOpacity = opacity
        }
        material.blending = .transparent(opacity: .init(floatLiteral: Float(effectiveOpacity)))

        if !audioReactiveEnabled {
            cachedMaterial = material
            lastCachedOpacity = opacity
        }
        return material
    }

    // MARK: - Animation Loop

    private func startDisplayLink() {
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] dt in
            Task { @MainActor in
                guard let self else { return }
                let floatDt = Float(dt)
                self.currentTime += floatDt * self.speed
                self.frameCount += 1
                // Pull latest audio levels from the audio engine
                self.pullAudioLevels()
                // Update texture every 3rd frame for performance (30fps on 90Hz display)
                if self.frameCount % 3 == 0 {
                    self.updateMaterials()
                }
                // Update particles every frame for smooth motion
                if self.particlesEnabled {
                    self.particleSystem.update(
                        deltaTime: floatDt,
                        speed: self.speed,
                        intensity: self.intensity,
                        audioReactive: self.audioReactiveEnabled,
                        audioLevel: self.audioLevel,
                        trebleLevel: self.trebleLevel,
                        audioSensitivity: self.audioSensitivity
                    )
                }
            }
        }, selector: #selector(DisplayLinkTarget.step(_:)))
        link.add(to: RunLoop.main, forMode: RunLoop.Mode.default)
        displayLink = link
    }

    private func updateMaterials() {
        // Update the GPU texture in-place (non-blocking)
        textureGenerator?.updateTexture(
            time: currentTime,
            speed: speed,
            intensity: intensity,
            styleIndex: styleIndex
        )

        let needsFullUpdate = audioReactiveEnabled || lastCachedOpacity != opacity
        let material = getOrCreateMaterial()
        if needsFullUpdate {
            // Update all entities when opacity or audio changes
            for entity in meshEntities.values {
                entity.model?.materials = [material]
            }
        } else {
            // Apply material only to entities that don't have one yet
            for entity in meshEntities.values {
                if entity.model?.materials.first is UnlitMaterial {
                    continue
                }
                entity.model?.materials = [material]
            }
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        session.stop()
    }
}

// MARK: - CADisplayLink Target

private class DisplayLinkTarget: NSObject {
    let callback: (TimeInterval) -> Void
    private var lastTimestamp: TimeInterval = 0

    init(callback: @escaping (TimeInterval) -> Void) {
        self.callback = callback
    }

    @objc func step(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 0 : link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        callback(dt)
    }
}
