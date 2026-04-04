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

    // Video color mode & video pattern support
    private var videoColorMode: Bool = false
    private var videoColorTop: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    private var videoColorMiddle: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    private var videoColorBottom: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    // Classification-split entities (used for video color mode and video patterns)
    private var ceilingEntities: [UUID: ModelEntity] = [:]
    private var floorEntities: [UUID: ModelEntity] = [:]
    private var otherEntities: [UUID: ModelEntity] = [:]
    private var lastSplitMode: Bool = false

    private static let ceilingClassifications: Set<MeshAnchor.MeshClassification> = [.ceiling]
    private static let floorClassifications: Set<MeshAnchor.MeshClassification> = [.floor, .stairs, .bed]
    private static let otherClassifications: Set<MeshAnchor.MeshClassification> = [.wall, .cabinet, .table, .seat, .window, .door, .homeAppliance, .tv, .plant, .none]

    /// Whether entities need to be split by classification (ceiling/floor/other)
    private var isVideoPattern: Bool {
        style == .videoPsychedelic || style == .videoInterference || style == .videoRainbow || style == .videoAurora
    }

    private var isOcclusionMode: Bool { style == .occlusion }

    private var splitMode: Bool {
        videoColorMode || isVideoPattern
    }

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
                if splitMode {
                    await addSplitEntities(for: anchor)
                } else {
                    if let entity = try? await createMeshEntity(from: anchor) {
                        meshEntities[anchor.id] = entity
                        rootEntity.addChild(entity)
                    }
                }

            case .updated:
                anchorCache[anchor.id] = anchor
                if splitMode {
                    await updateSplitEntities(for: anchor)
                } else {
                    if let existingEntity = meshEntities[anchor.id] {
                        existingEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
                        if let newMesh = try? await generateMeshResource(from: anchor, filter: classificationFilter) {
                            existingEntity.model?.mesh = newMesh
                        }
                    }
                }

            case .removed:
                anchorCache.removeValue(forKey: anchor.id)
                // Clean up all possible entity types
                meshEntities.removeValue(forKey: anchor.id)?.removeFromParent()
                ceilingEntities.removeValue(forKey: anchor.id)?.removeFromParent()
                floorEntities.removeValue(forKey: anchor.id)?.removeFromParent()
                otherEntities.removeValue(forKey: anchor.id)?.removeFromParent()
            }
        }
    }

    func configure(audioEngine: AudioReactiveEngine) {
        self.audioEngine = audioEngine
    }

    func updateParameters(speed: Float, intensity: Float, style: AppModel.PatternStyle,
                          opacity: Float, particlesEnabled: Bool, audioReactiveEnabled: Bool,
                          audioSensitivity: Float, autoPulseEnabled: Bool,
                          classificationFilter: Set<MeshAnchor.MeshClassification>?,
                          videoColorMode: Bool,
                          videoColorTop: SIMD3<Float>,
                          videoColorMiddle: SIMD3<Float>,
                          videoColorBottom: SIMD3<Float>) {
        let oldSplitMode = self.splitMode

        self.speed = speed
        self.intensity = intensity
        self.style = style
        self.opacity = opacity
        self.particlesEnabled = particlesEnabled
        self.audioReactiveEnabled = audioReactiveEnabled
        self.audioSensitivity = audioSensitivity
        self.videoColorMode = videoColorMode
        self.videoColorTop = videoColorTop
        self.videoColorMiddle = videoColorMiddle
        self.videoColorBottom = videoColorBottom

        let filterChanged = self.classificationFilter != classificationFilter
        self.classificationFilter = classificationFilter

        let newSplitMode = self.splitMode
        if oldSplitMode != newSplitMode {
            switchMeshMode()
        } else if filterChanged {
            rebuildAllMeshes()
        }
    }

    private func pullAudioLevels() {
        guard audioReactiveEnabled, let engine = audioEngine else { return }
        audioLevel = engine.audioLevel
        bassLevel = engine.bassLevel
        trebleLevel = engine.trebleLevel
    }

    // MARK: - Mesh Creation (Normal Mode)

    private func createMeshEntity(from anchor: MeshAnchor) async throws -> ModelEntity {
        let meshResource = try await generateMeshResource(from: anchor, filter: classificationFilter)
        let material: any RealityKit.Material = isOcclusionMode ? OcclusionMaterial() : getOrCreateMaterial()
        let entity = ModelEntity(mesh: meshResource, materials: [material])
        entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        return entity
    }

    // MARK: - Mesh Creation (Split Mode — Video Color & Video Pattern)

    private func addSplitEntities(for anchor: MeshAnchor) async {
        // Ceiling
        let ceilingFilter = effectiveFilter(for: Self.ceilingClassifications)
        if !ceilingFilter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: ceilingFilter) {
            let material = createSplitMaterial(color: videoColorTop)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            rootEntity.addChild(entity)
            ceilingEntities[anchor.id] = entity
        }
        // Floor
        let floorFilter = effectiveFilter(for: Self.floorClassifications)
        if !floorFilter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: floorFilter) {
            let material = createSplitMaterial(color: videoColorBottom)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            rootEntity.addChild(entity)
            floorEntities[anchor.id] = entity
        }
        // Other (walls, tables, etc.)
        let otherFilter = effectiveFilter(for: Self.otherClassifications)
        if !otherFilter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: otherFilter) {
            let material = createSplitMaterial(color: videoColorMiddle)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            rootEntity.addChild(entity)
            otherEntities[anchor.id] = entity
        }
    }

    private func updateSplitEntities(for anchor: MeshAnchor) async {
        if let entity = ceilingEntities[anchor.id] {
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            let filter = effectiveFilter(for: Self.ceilingClassifications)
            if !filter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: filter) {
                entity.model?.mesh = mesh
            }
        }
        if let entity = floorEntities[anchor.id] {
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            let filter = effectiveFilter(for: Self.floorClassifications)
            if !filter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: filter) {
                entity.model?.mesh = mesh
            }
        }
        if let entity = otherEntities[anchor.id] {
            entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            let filter = effectiveFilter(for: Self.otherClassifications)
            if !filter.isEmpty, let mesh = try? await generateMeshResource(from: anchor, filter: filter) {
                entity.model?.mesh = mesh
            }
        }
    }

    private func effectiveFilter(for group: Set<MeshAnchor.MeshClassification>) -> Set<MeshAnchor.MeshClassification> {
        if let cf = classificationFilter {
            return cf.intersection(group)
        }
        return group
    }

    /// Create a material for split-mode entities.
    /// videoColorMode → solid color, videoPattern → textured + tinted
    private func createSplitMaterial(color: SIMD3<Float>) -> UnlitMaterial {
        var material = UnlitMaterial()
        let tint: UIColor = .init(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1.0)

        if isVideoPattern, !videoColorMode, let texture = textureGenerator?.textureResource {
            // Video pattern: grayscale texture tinted with video color
            material.color = .init(tint: tint, texture: .init(texture))
        } else {
            // Video color mode: solid color
            material.color = .init(tint: tint)
        }
        material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        return material
    }

    // MARK: - Mode Switching

    private func switchMeshMode() {
        if splitMode {
            // Remove normal entities
            for entity in meshEntities.values { entity.removeFromParent() }
            meshEntities.removeAll()
            // Build split entities
            Task {
                for (_, anchor) in anchorCache {
                    await addSplitEntities(for: anchor)
                }
            }
        } else {
            // Remove split entities
            for entity in ceilingEntities.values { entity.removeFromParent() }
            for entity in floorEntities.values { entity.removeFromParent() }
            for entity in otherEntities.values { entity.removeFromParent() }
            ceilingEntities.removeAll()
            floorEntities.removeAll()
            otherEntities.removeAll()
            // Rebuild normal entities
            Task {
                for (_, anchor) in anchorCache {
                    if let entity = try? await createMeshEntity(from: anchor) {
                        meshEntities[anchor.id] = entity
                        rootEntity.addChild(entity)
                    }
                }
            }
        }
    }

    private func rebuildAllMeshes() {
        if splitMode {
            for entity in ceilingEntities.values { entity.removeFromParent() }
            for entity in floorEntities.values { entity.removeFromParent() }
            for entity in otherEntities.values { entity.removeFromParent() }
            ceilingEntities.removeAll()
            floorEntities.removeAll()
            otherEntities.removeAll()
            Task {
                for (_, anchor) in anchorCache {
                    await addSplitEntities(for: anchor)
                }
            }
        } else {
            Task {
                for (id, anchor) in anchorCache {
                    guard let entity = meshEntities[id] else { continue }
                    if let newMesh = try? await generateMeshResource(from: anchor, filter: classificationFilter) {
                        entity.model?.mesh = newMesh
                    }
                }
            }
        }
    }

    // MARK: - Mesh Resource Generation

    private func generateMeshResource(from anchor: MeshAnchor, filter: Set<MeshAnchor.MeshClassification>?) async throws -> MeshResource {
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

        if let activeFilter = filter,
           let classifications = meshGeometry.classifications {
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
        case .videoPsychedelic: return 12
        case .videoInterference: return 13
        case .videoRainbow: return 14
        case .videoAurora: return 15
        case .occlusion: return -1
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
                self.pullAudioLevels()
                if self.frameCount % 3 == 0 {
                    self.updateMaterials()
                }
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
        if isOcclusionMode {
            let material = OcclusionMaterial()
            for entity in meshEntities.values { entity.model?.materials = [material] }
            for entity in ceilingEntities.values { entity.model?.materials = [material] }
            for entity in floorEntities.values { entity.model?.materials = [material] }
            for entity in otherEntities.values { entity.model?.materials = [material] }
            return
        }

        if videoColorMode {
            // Video color mode: solid colors, no texture
            let ceilingMat = createSplitMaterial(color: videoColorTop)
            let floorMat = createSplitMaterial(color: videoColorBottom)
            let otherMat = createSplitMaterial(color: videoColorMiddle)
            for entity in ceilingEntities.values { entity.model?.materials = [ceilingMat] }
            for entity in floorEntities.values { entity.model?.materials = [floorMat] }
            for entity in otherEntities.values { entity.model?.materials = [otherMat] }
            return
        }

        // Generate texture (for both normal and video pattern modes)
        textureGenerator?.updateTexture(
            time: currentTime,
            speed: speed,
            intensity: intensity,
            styleIndex: styleIndex
        )

        if isVideoPattern {
            // Video pattern mode: grayscale texture tinted with video colors
            let ceilingMat = createSplitMaterial(color: videoColorTop)
            let floorMat = createSplitMaterial(color: videoColorBottom)
            let otherMat = createSplitMaterial(color: videoColorMiddle)
            for entity in ceilingEntities.values { entity.model?.materials = [ceilingMat] }
            for entity in floorEntities.values { entity.model?.materials = [floorMat] }
            for entity in otherEntities.values { entity.model?.materials = [otherMat] }
            return
        }

        // Normal psychedelic mode
        let needsFullUpdate = audioReactiveEnabled || lastCachedOpacity != opacity
        let material = getOrCreateMaterial()
        if needsFullUpdate {
            for entity in meshEntities.values {
                entity.model?.materials = [material]
            }
        } else {
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
