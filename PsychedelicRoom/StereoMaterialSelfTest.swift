import RealityKit
import RealityKitContent

/// StereoImageMaterial が現在の OS でロードでき、パラメータが公開されるかを起動時に検査する。
/// visionOS 27 でのマテリアルロード不具合を切り分けるための一時的な自己診断。
enum StereoMaterialSelfTest {
    @MainActor
    static func run() async {
        do {
            let m = try await ShaderGraphMaterial(
                named: "/Root/StereoImageMaterial",
                from: "StereoImageMaterial",
                in: realityKitContentBundle
            )
            print("SELFTEST: material LOADED ok. parameterNames=\(Array(m.parameterNames).sorted())")
        } catch {
            print("SELFTEST: material LOAD FAILED: \(error)")
        }
    }
}
