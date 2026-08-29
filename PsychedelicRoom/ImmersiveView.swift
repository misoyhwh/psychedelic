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
    @State private var handTracking = HandTrackingManager()
    @State private var handFollowTimer: Timer?
    /// 顔中心配置モードで頭に向けたヨー角 (rad)。nil = 顔配置による向き補正なし。
    @State private var slideshowFaceYaw: Float? = nil
    /// 動画の連続顔追跡タイマー (60Hz で lerp 追従)。
    @State private var videoFaceFollowTimer: Timer?
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
            // Kaleido / Tunnel パターン用に動画フレームと静止画 (スライド) の供給元を接続
            sceneReconstructor.videoFrameProvider = { [weak mediaVM = mediaVM as MediaPanelViewModel?] in
                mediaVM?.copyCurrentVideoPixelBuffer()
            }
            sceneReconstructor.stillImageProvider = { [weak mediaVM = mediaVM as MediaPanelViewModel?] in
                mediaVM?.slideshowCurrentImage
            }
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
        } update: { _ in
            runSceneUpdate()
        }
        .onDisappear {
            videoMotionTimer?.invalidate()
            videoMotionTimer = nil
            handFollowTimer?.invalidate()
            handFollowTimer = nil
            videoFaceFollowTimer?.invalidate()
            videoFaceFollowTimer = nil
            mediaVM.stopVideoFaceDetection()
            mediaVM.stopVideoAutoCrop()
            handTracking.stop()
            videoFramePump?.detach()
        }
    }

    /// RealityView の update closure 本体。閉包内に直接書くと SwiftUI の
    /// 型チェックが時間切れになるため関数に分離している。
    /// (observation 登録は実行時のプロパティアクセスで行われるため、関数化しても機能は同じ)
    private func runSceneUpdate() {
            // Read mediaVM properties to register SwiftUI observation
            // (ensures onChange handlers fire reliably)
            let _ = mediaVM.videoVersion
            let _ = mediaVM.videoEnabled
            let _ = mediaVM.isVideoPlaying
            let _ = mediaVM.videoRotationH
            let _ = mediaVM.videoRotationV
            let _ = mediaVM.videoCurveAmount
            let _ = mediaVM.videoCurveVAmount
            let _ = mediaVM.videoAutoCropEnabled
            let _ = mediaVM.videoCropRect
            let _ = mediaVM.videoBobEnabled
            let _ = mediaVM.videoSurgeEnabled
            let _ = mediaVM.videoSwayEnabled
            let _ = mediaVM.videoFollowHandEnabled
            let _ = mediaVM.slideshowFollowHandEnabled
            let _ = mediaVM.slideshowFaceCenterEnabled
            let _ = mediaVM.slideshowFacePlacementTick
            let _ = mediaVM.slideshowFaceDetectionMode
            let _ = mediaVM.videoFaceCenterEnabled
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
            let _ = mediaVM.slideshowCurveVAmount
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
                videoColorBottom: colorBottom,
                videoColorHistory: appModel.colorSource == .slideshow
                    ? mediaVM.slideshowColorHistory
                    : mediaVM.videoColorHistory,
                mediaSourceIsSlideshow: appModel.colorSource == .slideshow
            )
            occlusionPanel.update(
                enabled: appModel.occlusionPanelEnabled,
                width: appModel.occlusionPanelWidth,
                height: appModel.occlusionPanelHeight,
                rotationDegrees: appModel.occlusionPanelRotation
            )
    }

    /// sceneView + ジェスチャー + 動画系 onChange。
    private var sceneWithVideoHandlers: some View {
        sceneView
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
        .onChange(of: mediaVM.videoCurveVAmount) {
            updateVideoMesh()
        }
        .onChange(of: mediaVM.videoAutoCropEnabled) {
            updateVideoMesh()
        }
        .onChange(of: mediaVM.videoCropRect) {
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

    /// 手の甲追従・顔配置系の onChange (型チェック時間対策でチェーンを分割)。
    private var sceneWithFollowHandlers: some View {
        sceneWithVideoHandlers
        .onChange(of: mediaVM.videoFollowHandEnabled) {
            updateHandFollowState()
        }
        .onChange(of: mediaVM.slideshowFollowHandEnabled) {
            updateHandFollowState()
        }
        .onChange(of: mediaVM.videoFaceCenterEnabled) {
            updateVideoFaceFollowState()
        }
        .onChange(of: mediaVM.videoFaceInterval) {
            if mediaVM.videoFaceCenterEnabled {
                mediaVM.startVideoFaceDetection()
            }
        }
        .onChange(of: mediaVM.slideshowFaceCenterEnabled) {
            updateTrackingSessions()
            if mediaVM.slideshowFaceCenterEnabled {
                // 現在表示中の画像にも即適用するため再ロード → 検出 → 配置
                mediaVM.loadCurrentSlideshowImage()
            } else {
                slideshowFaceYaw = nil
                updateSlideshowRotation()
            }
        }
        .onChange(of: mediaVM.slideshowFacePlacementTick) {
            placeSlideshowByFace()
        }
        .onChange(of: mediaVM.slideshowFaceDetectionMode) {
            if mediaVM.slideshowFaceCenterEnabled {
                // 検出方法の変更を現在の画像にも即反映 (再ロード → 再検出 → 再配置)
                mediaVM.loadCurrentSlideshowImage()
            }
        }
        .onChange(of: mediaVM.slideshowCurveVAmount) {
            updateSlideshowMesh()
        }
        .onChange(of: mediaVM.slideshowFaceDistance) {
            placeSlideshowByFace()
        }
        .onChange(of: mediaVM.slideshowFaceHeight) {
            placeSlideshowByFace()
        }
        .onChange(of: mediaVM.slideshowFaceLateral) {
            placeSlideshowByFace()
        }
    }

    var body: some View {
        sceneWithFollowHandlers
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

        let (mesh, width, height) = makeVideoPanelMesh()

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
        entity.model?.mesh = makeVideoPanelMesh().mesh
    }

    /// 動画パネル用メッシュ。黒フチ自動カットの検出矩形を反映し、
    /// パネル寸法をコンテンツ部分の比率に縮めつつ UV をクロップする。
    private func makeVideoPanelMesh() -> (mesh: MeshResource, width: Float, height: Float) {
        let crop = mediaVM.videoAutoCropEnabled ? mediaVM.videoCropRect : CGRect(x: 0, y: 0, width: 1, height: 1)
        let width = Float(mediaVM.videoSize.width) * Float(crop.width)
        let height = Float(mediaVM.videoSize.height) * Float(crop.height)
        let mesh = makeCurvedPanelMesh(
            width: width,
            height: height,
            curveH: mediaVM.videoCurveAmount,
            curveV: mediaVM.videoCurveVAmount,
            uvRect: crop
        )
        return (mesh, width, height)
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
            curveH: mediaVM.slideshowCurveAmount,
            curveV: mediaVM.slideshowCurveVAmount
        )
        entity.model?.mesh = mesh

        // 拡張背景 (アウトペイント) も同じ湾曲に追従させる
        if let background = slideshowRootEntity.findEntity(named: "slideshowOutpaint") as? ModelEntity {
            background.model?.mesh = makeCurvedPanelMesh(
                width: width * 2.0,
                height: height * 2.0,
                curveH: mediaVM.slideshowCurveAmount,
                curveV: mediaVM.slideshowCurveVAmount
            )
            background.position.z = slideshowBackgroundZ(width: width, height: height)
        }
    }

    /// 拡張背景の退避 Z 位置。凸 (奥向き) 湾曲時はパネルの張り出し分だけさらに奥へ。
    private func slideshowBackgroundZ(width: Float, height: Float) -> Float {
        let depth = max(
            convexDepth(span: width, curve: mediaVM.slideshowCurveAmount),
            convexDepth(span: height, curve: mediaVM.slideshowCurveVAmount)
        )
        return -(depth + 0.05)
    }

    /// curve = 0 でフラット、>0 でこちら向きの凹面、<0 で奥向きの凸面の
    /// 円筒セクションメッシュを生成する。湾曲は水平方向のみで縦は直線。
    /// 既存呼び出し互換 (水平湾曲のみ)。動画パネルはこちらを使う。
    private func makeCurvedPanelMesh(
        width: Float,
        height: Float,
        curve: Float,
        uvRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> MeshResource {
        makeCurvedPanelMesh(width: width, height: height, curveH: curve, curveV: 0, uvRect: uvRect)
    }

    /// 水平 (curveH)・垂直 (curveV) の 2 軸湾曲パネルメッシュを生成する。
    /// 正値 = こちら向き (端がユーザー側 +Z)、負値 = 奥向き。両軸有効時は変位を加算した球面近似。
    /// アーク長 = パネル寸法を保つため、湾曲を強めても表示面積は変わらない。
    /// `uvRect` でテクスチャの一部だけを貼れる (黒フチ自動カット用。正規化・原点左下)。
    private func makeCurvedPanelMesh(
        width: Float,
        height: Float,
        curveH: Float,
        curveV: Float,
        uvRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> MeshResource {
        let hActive = abs(curveH) >= 0.01
        let vActive = abs(curveV) >= 0.01
        let fullUV = abs(uvRect.minX) < 0.001 && abs(uvRect.minY) < 0.001
            && abs(uvRect.width - 1) < 0.001 && abs(uvRect.height - 1) < 0.001
        if !hActive && !vActive && fullUV {
            return MeshResource.generatePlane(width: width, height: height)
        }

        let segX = 32
        let segY = 32
        let maxAngle: Float = .pi * 0.8   // |curve| = 1.0 のとき ~144°

        let angleH = abs(curveH) * maxAngle
        let radiusH: Float = hActive ? width / angleH : 0
        let signH: Float = curveH >= 0 ? 1 : -1

        let angleV = abs(curveV) * maxAngle
        let radiusV: Float = vActive ? height / angleV : 0
        let signV: Float = curveV >= 0 ? 1 : -1

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        let vertCount = (segX + 1) * (segY + 1)
        positions.reserveCapacity(vertCount)
        normals.reserveCapacity(vertCount)
        uvs.reserveCapacity(vertCount)

        for iy in 0...segY {
            let vNorm = Float(iy) / Float(segY)   // 0 (下) ... 1 (上)。RealityKit は v=1 が上
            let vCentered = vNorm - 0.5
            let thetaV = vActive ? vCentered * angleV : 0
            let y = vActive ? radiusV * sin(thetaV) : vCentered * height
            let zV = vActive ? signV * radiusV * (1 - cos(thetaV)) : 0

            for ix in 0...segX {
                let uNorm = Float(ix) / Float(segX)
                let uCentered = uNorm - 0.5
                let thetaH = hActive ? uCentered * angleH : 0
                let x = hActive ? radiusH * sin(thetaH) : uCentered * width
                let zH = hActive ? signH * radiusH * (1 - cos(thetaH)) : 0

                positions.append(SIMD3<Float>(x, y, zH + zV))
                // 接線ベクトル (dPos/du, dPos/dv) の外積から求めた法線
                let n = SIMD3<Float>(
                    -signH * sin(thetaH) * cos(thetaV),
                    -signV * cos(thetaH) * sin(thetaV),
                    cos(thetaH) * cos(thetaV)
                )
                normals.append(simd_normalize(n))
                uvs.append(SIMD2<Float>(
                    Float(uvRect.minX) + uNorm * Float(uvRect.width),
                    Float(uvRect.minY) + vNorm * Float(uvRect.height)
                ))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(segX * segY * 6)
        let rowStride = UInt32(segX + 1)
        for iy in 0..<segY {
            for ix in 0..<segX {
                let bl = UInt32(iy) * rowStride + UInt32(ix)
                let br = bl + 1
                let tl = bl + rowStride
                let tr = tl + 1
                // CCW from +Z (user side)
                indices.append(contentsOf: [bl, br, tl])
                indices.append(contentsOf: [tl, br, tr])
            }
        }

        var descriptor = MeshDescriptor(name: "CurvedPanel")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("Failed to build curved panel mesh: \(error)")
            return MeshResource.generatePlane(width: width, height: height)
        }
    }

    /// 凸 (奥向き) 湾曲でパネル端が -Z 方向へ張り出す最大深さ。背景の退避距離計算に使う。
    private func convexDepth(span: Float, curve: Float) -> Float {
        guard curve < -0.01 else { return 0 }
        let angleTotal = abs(curve) * .pi * 0.8
        let radius = span / angleTotal
        return radius * (1 - cos(angleTotal / 2))
    }

    private func updateVideoRotation() {
        // 連続顔追跡中は 60Hz タイマーが facing 込みで orientation を管理する
        guard !mediaVM.videoFaceCenterEnabled else { return }
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
            // 手の甲追従・顔追跡中は位置の主導権をそちらのタイマーに譲る
            guard !vm.videoFollowHandEnabled, !vm.videoFaceCenterEnabled else { return }
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

    // MARK: - Hand Follow

    /// 手の甲追従の ON/OFF を反映する。どちらかのパネルが追従中なら
    /// ハンドトラッキングセッションと 60Hz の追従タイマーを起動し、
    /// 両方 OFF ならすべて停止する。
    private func updateHandFollowState() {
        handFollowTimer?.invalidate()
        handFollowTimer = nil

        let anyFollow = mediaVM.videoFollowHandEnabled || mediaVM.slideshowFollowHandEnabled
        guard anyFollow else {
            updateTrackingSessions()
            return
        }

        handTracking.startIfNeeded(hands: true)

        // Capture references to avoid retaining the entire view (same pattern as updateVideoMotion)
        let tracker = handTracking
        let vm = mediaVM
        let videoRoot = videoRootEntity
        let slideshowRoot = slideshowRootEntity

        handFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let lerpFactor: Float = 0.18  // 補間係数: 大きいほど機敏、小さいほど滑らか
            // 水平/奥行きオフセットは頭の向き基準。デバイスアンカー未取得時はワールド軸にフォールバック。
            let rightVec = tracker.headRightVector() ?? SIMD3<Float>(1, 0, 0)
            let forwardVec = tracker.headForwardVector() ?? SIMD3<Float>(0, 0, -1)

            if vm.videoFollowHandEnabled,
               let hand = tracker.position(for: vm.videoFollowHand) {
                let target = hand
                    + SIMD3<Float>(0, vm.videoFollowHandHeight, 0)
                    + rightVec * vm.videoFollowHandLateral
                    + forwardVec * vm.videoFollowHandDepth
                videoRoot.position = mix(videoRoot.position, target, t: lerpFactor)
            }
            if vm.slideshowFollowHandEnabled,
               let hand = tracker.position(for: vm.slideshowFollowHand) {
                let target = hand
                    + SIMD3<Float>(0, vm.slideshowFollowHandHeight, 0)
                    + rightVec * vm.slideshowFollowHandLateral
                    + forwardVec * vm.slideshowFollowHandDepth
                slideshowRoot.position = mix(slideshowRoot.position, target, t: lerpFactor)
            }
        }
    }

    // MARK: - Tracking Session Management

    /// 手の甲追従 / 顔中心配置の有効状態に応じて ARKit セッションを起動・停止する。
    /// 手が必要なら hands つき、顔配置だけなら頭の姿勢のみ、どちらも不要なら停止。
    private func updateTrackingSessions() {
        let needHands = mediaVM.videoFollowHandEnabled || mediaVM.slideshowFollowHandEnabled
        let needWorld = needHands
            || mediaVM.slideshowFaceCenterEnabled
            || mediaVM.videoFaceCenterEnabled
        if needHands {
            handTracking.startIfNeeded(hands: true)
        } else if needWorld {
            handTracking.startIfNeeded(hands: false)
        } else {
            handTracking.stop()
        }
    }

    /// 動画の連続顔追跡の ON/OFF を反映する。
    /// ON: 検出ループ (VM 側) + 60Hz の lerp 追従タイマーを起動。OFF: 停止して向きをスライダー基準に戻す。
    private func updateVideoFaceFollowState() {
        videoFaceFollowTimer?.invalidate()
        videoFaceFollowTimer = nil

        guard mediaVM.videoFaceCenterEnabled else {
            mediaVM.stopVideoFaceDetection()
            updateTrackingSessions()
            updateVideoRotation()
            return
        }

        updateTrackingSessions()
        mediaVM.startVideoFaceDetection()

        // Capture references to avoid retaining the entire view (same pattern as updateVideoMotion)
        let tracker = handTracking
        let vm = mediaVM
        let root = videoRootEntity

        videoFaceFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard vm.videoFaceCenterEnabled,
                  !vm.videoFollowHandEnabled,
                  let headPos = tracker.headPosition() else { return }

            let fwd = tracker.headForwardVector() ?? SIMD3<Float>(0, 0, -1)
            let right = tracker.headRightVector() ?? SIMD3<Float>(1, 0, 0)
            let anchor = headPos
                + fwd * vm.videoFaceDistance
                + SIMD3<Float>(0, vm.videoFaceHeight, 0)
                + right * vm.videoFaceLateral

            // ヨーだけ頭に向け、回転スライダーを相対適用。slerp で滑らかに。
            let toHead = headPos - anchor
            let facing = simd_quatf(angle: atan2(toHead.x, toHead.z), axis: [0, 1, 0])
            let yaw = simd_quatf(angle: vm.videoRotationH * .pi / 180, axis: [0, 1, 0])
            let pitch = simd_quatf(angle: vm.videoRotationV * .pi / 180, axis: [1, 0, 0])
            let targetOrientation = facing * yaw * pitch
            root.orientation = simd_slerp(root.orientation, targetOrientation, 0.1)

            // 顔中心 (未検出は画像中心) が anchor に一致する位置へゆっくり lerp
            let c = vm.videoFaceCenter ?? SIMD2<Float>(0.5, 0.5)
            let w = Float(vm.videoSize.width)
            let h = Float(vm.videoSize.height)
            let localOffset = SIMD3<Float>((c.x - 0.5) * w, (c.y - 0.5) * h, 0)
            let target = anchor - root.orientation.act(localOffset * root.scale.x)
            root.position = mix(root.position, target, t: 0.08)
        }
    }

    // MARK: - Face-Centered Placement

    /// 検出した顔中心 (無ければ画像中心) が「頭の正面 + オフセット」に来るよう
    /// スライドショーパネルを配置し、ヨーだけ頭に向ける。
    /// 手の甲追従が有効な間は位置の主導権をそちらに譲る。
    private func placeSlideshowByFace() {
        guard mediaVM.slideshowFaceCenterEnabled,
              !mediaVM.slideshowFollowHandEnabled,
              let headPos = handTracking.headPosition() else { return }

        let fwd = handTracking.headForwardVector() ?? SIMD3<Float>(0, 0, -1)
        let right = handTracking.headRightVector() ?? SIMD3<Float>(1, 0, 0)
        let anchor = headPos
            + fwd * mediaVM.slideshowFaceDistance
            + SIMD3<Float>(0, mediaVM.slideshowFaceHeight, 0)
            + right * mediaVM.slideshowFaceLateral

        // ヨーだけ頭に向ける (既存の回転スライダーは相対回転として合成される)
        let toHead = headPos - anchor
        slideshowFaceYaw = atan2(toHead.x, toHead.z)
        updateSlideshowRotation()

        // 顔中心のパネルローカルオフセット。Vision 座標は原点左下、パネルローカルは中心原点 Y 上向き。
        let c = mediaVM.slideshowFaceCenter ?? SIMD2<Float>(0.5, 0.5)
        let w = Float(mediaVM.slideshowDisplaySize.width)
        let h = Float(mediaVM.slideshowDisplaySize.height)
        let localOffset = SIMD3<Float>((c.x - 0.5) * w, (c.y - 0.5) * h, 0)

        let orientation = slideshowRootEntity.orientation
        let scale = slideshowRootEntity.scale.x
        slideshowRootEntity.position = anchor - orientation.act(localOffset * scale)
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
                curveH: mediaVM.slideshowCurveAmount,
                curveV: mediaVM.slideshowCurveVAmount
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

            // 拡張背景 (アウトペイント): サーバ事前生成の画像をパネル背後に敷く。
            // サーバの生成仕様 (キャンバス 2 倍・元画像中央ピクセル一致) に合わせて
            // パネルの 2 倍サイズ・中心一致で置くと継ぎ目が揃う。
            if mediaVM.slideshowOutpaintEnabled, let outpaintTex = mediaVM.slideshowOutpaintTexture {
                let outpaintScale: Float = 2.0
                // パネルと同じ湾曲を背景にも適用して面の向きを揃える
                let bgMesh = makeCurvedPanelMesh(
                    width: width * outpaintScale,
                    height: height * outpaintScale,
                    curveH: mediaVM.slideshowCurveAmount,
                    curveV: mediaVM.slideshowCurveVAmount
                )
                var bgMaterial = UnlitMaterial()
                bgMaterial.color = .init(tint: .white, texture: .init(outpaintTex))
                let background = ModelEntity(mesh: bgMesh, materials: [bgMaterial])
                background.name = "slideshowOutpaint"
                background.position = SIMD3<Float>(0, 0, slideshowBackgroundZ(width: width, height: height))
                slideshowRootEntity.addChild(background)
            }

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
        // 顔中心配置モード中は「頭に向くヨー」をベースにスライダー回転を相対適用
        if mediaVM.slideshowFaceCenterEnabled, let base = slideshowFaceYaw {
            let facing = simd_quatf(angle: base, axis: [0, 1, 0])
            slideshowRootEntity.orientation = facing * yaw * pitch
        } else {
            slideshowRootEntity.orientation = yaw * pitch
        }
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
