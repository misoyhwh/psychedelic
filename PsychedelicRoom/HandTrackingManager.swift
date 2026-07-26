import Foundation
import ARKit
import simd
import QuartzCore

/// パネル追従の対象となる手。
enum FollowHand: String, CaseIterable, Identifiable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "左手"
        case .right: return "右手"
        }
    }
}

/// ARKit HandTrackingProvider をラップし、左右の手の甲のワールド座標を提供する。
/// 実機専用 (シミュレータでは HandTrackingProvider.isSupported == false のため start は no-op)。
@Observable
@MainActor
final class HandTrackingManager {
    private let session = ARKitSession()
    private var provider: HandTrackingProvider?
    private var worldProvider: WorldTrackingProvider?
    private var updateTask: Task<Void, Never>?
    private(set) var isRunning = false
    /// 現在のセッションでハンドトラッキングが有効か (false = 頭の姿勢のみ)。
    private(set) var handsActive = false

    /// 手の甲 (middleFingerMetacarpal、無ければ手首) のワールド座標。未トラッキング時は nil。
    private(set) var leftHandPosition: SIMD3<Float>?
    private(set) var rightHandPosition: SIMD3<Float>?

    static var isSupported: Bool { HandTrackingProvider.isSupported }

    func position(for hand: FollowHand) -> SIMD3<Float>? {
        switch hand {
        case .left: return leftHandPosition
        case .right: return rightHandPosition
        }
    }

    /// セッションを開始する。`hands: false` なら頭の姿勢 (WorldTrackingProvider) のみで起動。
    /// 既に必要な構成で動作中なら何もしない。頭のみ → 手が必要になったら作り直す。
    func startIfNeeded(hands: Bool = true) {
        let wantHands = hands && HandTrackingProvider.isSupported
        if isRunning {
            guard wantHands && !handsActive else { return }
            stop()  // 頭のみ → 手つきに昇格するため再起動
        }
        if hands && !HandTrackingProvider.isSupported {
            print("Hand tracking not supported on this platform — starting world tracking only")
        }
        isRunning = true
        handsActive = wantHands

        // 頭の向き (デバイスアンカー) はどのモードでも使う
        let world = WorldTrackingProvider()
        self.worldProvider = world

        var handProvider: HandTrackingProvider? = nil
        if wantHands {
            let p = HandTrackingProvider()
            self.provider = p
            handProvider = p
        }

        updateTask = Task { [weak self] in
            do {
                guard let session = self?.session else { return }
                if let handProvider {
                    try await session.run([handProvider, world])
                    for await update in handProvider.anchorUpdates {
                        guard let self, !Task.isCancelled else { break }
                        self.apply(update)
                    }
                } else {
                    try await session.run([world])
                }
            } catch {
                print("Hand tracking session failed: \(error)")
                self?.isRunning = false
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        updateTask?.cancel()
        updateTask = nil
        session.stop()
        provider = nil
        worldProvider = nil
        isRunning = false
        handsActive = false
        leftHandPosition = nil
        rightHandPosition = nil
    }

    /// 頭 (デバイス) のワールド座標。取れない場合は nil。
    func headPosition() -> SIMD3<Float>? {
        guard let t = deviceTransform() else { return nil }
        return SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    /// 頭 (デバイス) の右方向を水平面に投影して正規化したベクトル。
    /// デバイスアンカーが取れない場合は nil (呼び出し側でワールド X 軸にフォールバック)。
    func headRightVector() -> SIMD3<Float>? {
        guard let t = deviceTransform() else { return nil }
        return normalizedHorizontal(SIMD3<Float>(t.columns.0.x, 0, t.columns.0.z))
    }

    /// 頭 (デバイス) の前方向 (視線の向く先 = 奥) を水平面に投影して正規化したベクトル。
    /// カメラは -Z を向くため columns.2 を反転する。取れない場合は nil (ワールド -Z にフォールバック)。
    func headForwardVector() -> SIMD3<Float>? {
        guard let t = deviceTransform() else { return nil }
        return normalizedHorizontal(SIMD3<Float>(-t.columns.2.x, 0, -t.columns.2.z))
    }

    private func deviceTransform() -> simd_float4x4? {
        guard let world = worldProvider, world.state == .running,
              let device = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return nil
        }
        return device.originFromAnchorTransform
    }

    private func normalizedHorizontal(_ v: SIMD3<Float>) -> SIMD3<Float>? {
        let len = simd_length(v)
        guard len > 0.0001 else { return nil }
        return v / len
    }

    // MARK: - Private

    private func apply(_ update: AnchorUpdate<HandAnchor>) {
        let anchor = update.anchor
        let position: SIMD3<Float>?
        switch update.event {
        case .added, .updated:
            position = anchor.isTracked ? Self.backOfHandPosition(anchor) : nil
        case .removed:
            position = nil
        }
        switch anchor.chirality {
        case .left: leftHandPosition = position
        case .right: rightHandPosition = position
        }
    }

    /// 手の甲の中心位置。中指の中手骨 (metacarpal) 関節が最も「手の甲の真ん中」に近い。
    /// スケルトンが取れない場合は手首 (anchor origin) にフォールバック。
    private static func backOfHandPosition(_ anchor: HandAnchor) -> SIMD3<Float> {
        let origin = anchor.originFromAnchorTransform
        if let skeleton = anchor.handSkeleton {
            let joint = skeleton.joint(.middleFingerMetacarpal)
            if joint.isTracked {
                let world = origin * joint.anchorFromJointTransform
                return SIMD3<Float>(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            }
        }
        return SIMD3<Float>(origin.columns.3.x, origin.columns.3.y, origin.columns.3.z)
    }
}
