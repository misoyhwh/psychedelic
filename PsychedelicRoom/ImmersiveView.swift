import SwiftUI
import RealityKit
@preconcurrency import ARKit
import RealityKitContent
import AVFoundation

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AudioReactiveEngine.self) private var audioEngine
    @Environment(MediaPanelViewModel.self) private var mediaVM
    @State private var sceneReconstructor = SceneReconstructor()
    @State private var occlusionPanel = OcclusionPanelManager()

    // Video panel entities
    @State private var videoRootEntity = Entity()
    @State private var videoEntity: ModelEntity?
    @State private var videoFramePump: StereoVideoFramePump? = StereoVideoFramePump()
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

    // body を分割しないと SwiftUI の型チェッカーが時間切れになるため、
    // RealityView 本体 + 動画系 onChange を sceneView に切り出している。
    private var sceneView: some View {
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
            let _ = mediaVM.isVideoPlaying
            let _ = mediaVM.videoRotationH
            let _ = mediaVM.videoRotationV
            let _ = mediaVM.videoCurveAmount
            let _ = mediaVM.videoBobEnabled
            let _ = mediaVM.videoSurgeEnabled
            let _ = mediaVM.videoSwayEnabled
            let _ = mediaVM.videoBackgroundRemovalEnabled
            let _ = mediaVM.videoChromaThreshold
            let _ = mediaVM.videoChromaSmoothness
            let _ = mediaVM.videoChromaKeyColor
            let _ = mediaVM.videoForegroundKeyEnabled
            let _ = mediaVM.videoForegroundThreshold
            let _ = mediaVM.videoForegroundFeather
            let _ = mediaVM.slideshowTextureVersion
            let _ = mediaVM.slideshowEnabled
            let _ = mediaVM.slideshowRotationH
            let _ = mediaVM.slideshowRotationV
            let _ = mediaVM.slideshowCurveAmount
            let _ = mediaVM.slideshowChromaKeyEnabled
            let _ = mediaVM.slideshowChromaKeyColor
            let _ = mediaVM.slideshowChromaThreshold
            let _ = mediaVM.slideshowChromaSmoothness
            let _ = mediaVM.slideshowForegroundKeyEnabled
            let _ = mediaVM.slideshowForegroundThreshold
            let _ = mediaVM.slideshowForegroundFeather
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
            videoFramePump?.detach()
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
        .onChange(of: mediaVM.videoCurveAmount) {
            updateVideoMesh()
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
    }

    var body: some View {
        sceneView
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
        .onChange(of: mediaVM.slideshowCurveAmount) {
            updateSlideshowMesh()
        }
        .onChange(of: mediaVM.slideshowChromaKeyEnabled) {
            updateSlideshowChromaKey()
        }
        .onChange(of: mediaVM.slideshowChromaKeyColor) {
            updateSlideshowChromaKey()
        }
        .onChange(of: mediaVM.slideshowChromaThreshold) {
            updateSlideshowChromaKey()
        }
        .onChange(of: mediaVM.slideshowChromaSmoothness) {
            updateSlideshowChromaKey()
        }
        .onChange(of: mediaVM.slideshowForegroundThreshold) {
            updateSlideshowForegroundKey()
        }
        .onChange(of: mediaVM.slideshowForegroundFeather) {
            updateSlideshowForegroundKey()
        }
        .onChange(of: mediaVM.videoChromaThreshold) {
            updateVideoChromaKey()
        }
        .onChange(of: mediaVM.videoChromaSmoothness) {
            updateVideoChromaKey()
        }
        .onChange(of: mediaVM.videoChromaKeyColor) {
            updateVideoChromaKey()
        }
        .onChange(of: mediaVM.videoForegroundThreshold) {
            updateVideoForegroundKey()
        }
        .onChange(of: mediaVM.videoForegroundFeather) {
            updateVideoForegroundKey()
        }
    }

    // MARK: - Video Entity

    private func recreateVideoEntity() {
        // Remove ALL children to prevent entity accumulation
        for child in videoRootEntity.children {
            child.removeFromParent()
        }
        videoEntity = nil

        guard let player = mediaVM.player else {
            videoFramePump?.detach()
            return
        }

        let width = Float(mediaVM.videoSize.width)
        let height = Float(mediaVM.videoSize.height)
        let mesh = makeCurvedPanelMesh(width: width, height: height, curve: mediaVM.videoCurveAmount)

        if (mediaVM.videoBackgroundRemovalEnabled || mediaVM.videoForegroundKeyEnabled), let pump = videoFramePump {
            recreateVideoEntityWithBackgroundRemoval(player: player, pump: pump, mesh: mesh, width: width, height: height)
            return
        }

        // 通常表示: VideoMaterial (透過なし)。
        videoFramePump?.detach()
        let material = VideoMaterial(avPlayer: player)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: height, depth: 0.01)]))
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.name = "videoPanel"
        videoRootEntity.addChild(entity)
        videoEntity = entity
        print("Video entity created (VideoMaterial): \(width)x\(height)")
    }

    /// 背景透過モード: StereoImageMaterial にフレームポンプの左右テクスチャを流す。
    private func recreateVideoEntityWithBackgroundRemoval(
        player: AVPlayer, pump: StereoVideoFramePump,
        mesh: MeshResource, width: Float, height: Float
    ) {
        Task {
            var material: RealityKit.Material
            do {
                var m = try await ShaderGraphMaterial(
                    named: "/Root/StereoImageMaterial",
                    from: "StereoImageMaterial",
                    in: realityKitContentBundle
                )
                applyVideoChromaParameters(to: &m)
                applyVideoForegroundParameters(to: &m)
                try? m.setParameter(name: "MaskEnable", value: .float(0)) // マスク生成完了まで全表示
                material = m
                print("✅ [Stereo] StereoImageMaterial loaded OK (video)")
            } catch {
                print("❌ [Stereo] StereoImageMaterial FAILED (video) -> black fallback: \(error)")
                material = UnlitMaterial(color: .black)
            }

            for child in videoRootEntity.children { child.removeFromParent() }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: height, depth: 0.01)]))
            entity.components.set(InputTargetComponent(allowedInputTypes: .all))
            entity.name = "videoPanel"
            videoRootEntity.addChild(entity)
            videoEntity = entity

            // 最初のフレームでテクスチャが用意できたら LeftImage/RightImage をバインド。
            pump.onTexturesReady = { [weak entity, weak pump] in
                guard let entity, let pump,
                      var m = entity.model?.materials.first as? ShaderGraphMaterial else { return }
                if let lt = pump.leftTexture {
                    try? m.setParameter(name: "LeftImage", value: .textureResource(lt))
                }
                if let rt = pump.rightTexture ?? pump.leftTexture {
                    try? m.setParameter(name: "RightImage", value: .textureResource(rt))
                }
                entity.model?.materials = [m]
            }

            // 前景マスクが更新されるたびに LeftMask/RightMask を再バインド (左右個別)。
            pump.foregroundEnabled = mediaVM.videoForegroundKeyEnabled
            pump.onMaskUpdated = { [weak entity, weak pump] in
                guard let entity, let pump,
                      var m = entity.model?.materials.first as? ShaderGraphMaterial,
                      let leftMask = pump.maskLeftTexture else { return }
                let rightMask = pump.maskRightTexture ?? leftMask // モノラルは左で代用
                try? m.setParameter(name: "LeftMask", value: .textureResource(leftMask))
                try? m.setParameter(name: "RightMask", value: .textureResource(rightMask))
                try? m.setParameter(name: "MaskEnable", value: .float(pump.foregroundEnabled ? 1.0 : 0.0))
                entity.model?.materials = [m]
            }

            // FPS 計測をビューモデルへ反映 (デバッグ表示用)。
            pump.onStats = { displayFPS, maskFPS in
                mediaVM.videoMeasuredFPS = displayFPS
                mediaVM.videoMaskFPS = maskFPS
            }
            pump.attach(to: player)
            print("Video entity created (background removal): \(width)x\(height)")
        }
    }

    private func applyVideoChromaParameters(to material: inout ShaderGraphMaterial) {
        let c = mediaVM.videoChromaKeyColor
        let key = CGColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        try? material.setParameter(name: "KeyColor", value: .color(key))
        try? material.setParameter(name: "Threshold", value: .float(mediaVM.videoChromaThreshold))
        try? material.setParameter(name: "Smoothness", value: .float(mediaVM.videoChromaSmoothness))
        try? material.setParameter(name: "ChromaEnable", value: .float(mediaVM.videoBackgroundRemovalEnabled ? 1.0 : 0.0))
    }

    private func updateVideoChromaKey() {
        guard let entity = videoEntity,
              var material = entity.model?.materials.first as? ShaderGraphMaterial else { return }
        applyVideoChromaParameters(to: &material)
        entity.model?.materials = [material]
    }

    private func applyVideoForegroundParameters(to material: inout ShaderGraphMaterial) {
        try? material.setParameter(name: "MaskThreshold", value: .float(mediaVM.videoForegroundThreshold))
        try? material.setParameter(name: "MaskFeather", value: .float(mediaVM.videoForegroundFeather))
    }

    private func updateVideoForegroundKey() {
        guard let entity = videoEntity,
              var material = entity.model?.materials.first as? ShaderGraphMaterial else { return }
        applyVideoForegroundParameters(to: &material)
        entity.model?.materials = [material]
    }

    private func updateVideoVisibility() {
        let shouldShow = mediaVM.videoEnabled && mediaVM.player != nil
        videoRootEntity.isEnabled = shouldShow
        print("Video visibility: \(shouldShow), enabled=\(mediaVM.videoEnabled), player=\(mediaVM.player != nil)")
    }

    /// 既存 video entity のメッシュを湾曲量に合わせて差し替える (entity 再生成なし)。
    private func updateVideoMesh() {
        guard let entity = videoEntity else { return }
        let width = Float(mediaVM.videoSize.width)
        let height = Float(mediaVM.videoSize.height)
        entity.model?.mesh = makeCurvedPanelMesh(width: width, height: height, curve: mediaVM.videoCurveAmount)
    }

    // MARK: - Slideshow Panel Curve

    /// 既存 slideshow entity のメッシュを湾曲量に合わせて差し替える。
    /// entity 自体は再生成しないので、スライダーで連続的に値を変えても
    /// テクスチャの再バインドや表示の途切れが発生しない。
    private func updateSlideshowMesh() {
        guard let entity = slideshowEntity else { return }
        let width = Float(mediaVM.slideshowDisplaySize.width)
        let height = Float(mediaVM.slideshowDisplaySize.height)
        let mesh = makeCurvedPanelMesh(
            width: width,
            height: height,
            curve: mediaVM.slideshowCurveAmount
        )
        entity.model?.mesh = mesh
    }

    /// curve = 0 でフラット、>0 でこちら向きの凹面、<0 で奥向きの凸面の
    /// 円筒セクションメッシュを生成する。湾曲は水平方向のみで縦は直線。
    private func makeCurvedPanelMesh(width: Float, height: Float, curve: Float) -> MeshResource {
        // ほぼ 0 ならフラットなプレーンに退避 (除算 0 回避)。
        if abs(curve) < 0.01 {
            return MeshResource.generatePlane(width: width, height: height)
        }

        let segmentsX = 32
        let maxAngle: Float = .pi * 0.8           // |curve| = 1.0 のとき ~144°
        let angleTotal = abs(curve) * maxAngle    // パネル全幅で展開する角度
        let radius = width / angleTotal           // アーク長 = width を保つ

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity((segmentsX + 1) * 2)
        normals.reserveCapacity((segmentsX + 1) * 2)
        uvs.reserveCapacity((segmentsX + 1) * 2)

        let halfH = height / 2

        for i in 0...segmentsX {
            let uNorm = Float(i) / Float(segmentsX)        // 0 ... 1
            let uCentered = uNorm - 0.5                    // -0.5 ... 0.5
            let theta = uCentered * angleTotal             // -a/2 ... a/2
            let x = radius * sin(theta)
            let zMag = radius * (1 - cos(theta))
            let z: Float
            let normalX: Float
            if curve > 0 {
                // こちら向き concave: 端がユーザー側 (+z)
                z = zMag
                normalX = -sin(theta)
            } else {
                // 奥向き convex: 端が向こう側 (-z)
                z = -zMag
                normalX = sin(theta)
            }
            let normal = SIMD3<Float>(normalX, 0, cos(theta))

            // top (RealityKit の generatePlane は v=1 が上、v=0 が下なので合わせる)
            positions.append(SIMD3<Float>(x, halfH, z))
            normals.append(normal)
            uvs.append(SIMD2<Float>(uNorm, 1))
            // bottom
            positions.append(SIMD3<Float>(x, -halfH, z))
            normals.append(normal)
            uvs.append(SIMD2<Float>(uNorm, 0))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(segmentsX * 6)
        for i in 0..<segmentsX {
            let tl = UInt32(2 * i)
            let bl = UInt32(2 * i + 1)
            let tr = UInt32(2 * (i + 1))
            let br = UInt32(2 * (i + 1) + 1)
            // CCW from +Z (user side)
            indices.append(contentsOf: [tl, bl, tr])
            indices.append(contentsOf: [tr, bl, br])
        }

        var descriptor = MeshDescriptor(name: "SlideshowCurvedPanel")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("Failed to build curved slideshow mesh: \(error)")
            return MeshResource.generatePlane(width: width, height: height)
        }
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
            let mesh = makeCurvedPanelMesh(
                width: width,
                height: height,
                curve: mediaVM.slideshowCurveAmount
            )
            var material: RealityKit.Material

            // モノ画像も同じ ShaderGraph を使う (左テクスチャを両眼に供給)。
            // こうすることで立体視・クロマキーの経路が一本化され、
            // 背景透過のオン/オフはマテリアルを作り直さず setParameter で切り替えられる。
            let rightTexture = mediaVM.slideshowRightTexture ?? leftTexture
            do {
                var stereoMaterial = try await ShaderGraphMaterial(
                    named: "/Root/StereoImageMaterial",
                    from: "StereoImageMaterial",
                    in: realityKitContentBundle
                )
                try stereoMaterial.setParameter(name: "LeftImage", value: .textureResource(leftTexture))
                try stereoMaterial.setParameter(name: "RightImage", value: .textureResource(rightTexture))
                applyChromaParameters(to: &stereoMaterial)
                applyForegroundParameters(to: &stereoMaterial)
                material = stereoMaterial
                print("✅ [Stereo] StereoImageMaterial loaded OK (image)")
            } catch {
                print("❌ [Stereo] StereoImageMaterial FAILED (image) -> falling back to mono/opaque: \(error)")
                var fallback = UnlitMaterial()
                fallback.color = .init(tint: .white, texture: .init(leftTexture))
                material = fallback
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

    // MARK: - Slideshow Chroma Key

    /// 現在の chroma key 設定を ShaderGraphMaterial のパラメータへ書き込む。
    private func applyChromaParameters(to material: inout ShaderGraphMaterial) {
        let c = mediaVM.slideshowChromaKeyColor
        let keyColor = CGColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        try? material.setParameter(name: "KeyColor", value: .color(keyColor))
        try? material.setParameter(name: "Threshold", value: .float(mediaVM.slideshowChromaThreshold))
        try? material.setParameter(name: "Smoothness", value: .float(mediaVM.slideshowChromaSmoothness))
        try? material.setParameter(name: "ChromaEnable", value: .float(mediaVM.slideshowChromaKeyEnabled ? 1.0 : 0.0))
    }

    /// 既存パネルのマテリアルを作り直さず chroma key パラメータだけ更新する。
    /// スライダー/カラーピッカーの連続操作でも表示が途切れない。
    private func updateSlideshowChromaKey() {
        guard let entity = slideshowEntity,
              var material = entity.model?.materials.first as? ShaderGraphMaterial else { return }
        applyChromaParameters(to: &material)
        entity.model?.materials = [material]
    }

    // MARK: - Slideshow Foreground Extraction

    /// 前景抽出マスクとパラメータを ShaderGraphMaterial へ書き込む。
    /// MaskEnable は「機能ON かつ 有効なマスクが存在」する時のみ 1.0。
    /// 生成失敗 (mask 無し) 時は 0.0 にして全表示を維持する。
    private func applyForegroundParameters(to material: inout ShaderGraphMaterial) {
        let leftMask = mediaVM.slideshowForegroundMask
        let rightMask = mediaVM.slideshowForegroundMaskRight ?? leftMask
        if let leftMask {
            try? material.setParameter(name: "LeftMask", value: .textureResource(leftMask))
        }
        if let rightMask {
            try? material.setParameter(name: "RightMask", value: .textureResource(rightMask))
        }
        let active = mediaVM.slideshowForegroundKeyEnabled && leftMask != nil
        try? material.setParameter(name: "MaskEnable", value: .float(active ? 1.0 : 0.0))
        try? material.setParameter(name: "MaskThreshold", value: .float(mediaVM.slideshowForegroundThreshold))
        try? material.setParameter(name: "MaskFeather", value: .float(mediaVM.slideshowForegroundFeather))
    }

    /// しきい値・ぼかしの連続操作をマテリアル再生成なしで反映する。
    /// 有効/無効やマスク有無の変化は slideshowTextureVersion 経由の再生成で扱う。
    private func updateSlideshowForegroundKey() {
        guard let entity = slideshowEntity,
              var material = entity.model?.materials.first as? ShaderGraphMaterial else { return }
        applyForegroundParameters(to: &material)
        entity.model?.materials = [material]
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
