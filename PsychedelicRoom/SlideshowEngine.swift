import Foundation
import RealityKit
import ImageIO
import CoreGraphics
import CoreVideo
import CoreML
import Vision
import CoreImage

/// 顔中心配置の検出方法。
enum CenterDetectionMode: String, CaseIterable, Identifiable, Sendable {
    case face
    case saliency
    case animeFace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .face: return "顔検出"
        case .saliency: return "注目度"
        case .animeFace: return "アニメ顔"
        }
    }
}

struct SlideshowImage {
    let url: URL
    /// 画面に表示するファイル名 (ローカル: lastPathComponent、リモート: asset.title or short hash)。nil 時は非表示。
    let displayName: String?
    /// サーバ検索由来の場合、そのアセットのタグ。ローカル/未対応サーバでは nil。
    var tags: [String]? = nil
    /// illust-server 上の asset hash (リモートのみ)。お気に入り設定に使う。ローカルは nil。
    var hash: String? = nil
    // stereo detection is deferred to load time
}

struct LoadedImageTextures {
    let leftTexture: TextureResource
    let rightTexture: TextureResource?
    let isStereo: Bool
    let displaySize: CGSize
    /// 色サンプリング用の小サイズ CGImage (max 128px) — 二重ダウンロード回避のためここで作って渡す。
    let colorSamplingImage: CGImage?
    /// 表示テクスチャ生成に使った CGImage (左/モノ)。前景マスクを後追い生成する際に
    /// 再デコード/再ダウンロードせず使い回すために保持する。
    let leftDisplayImage: CGImage?
    /// 表示テクスチャ生成に使った CGImage (右ステレオ)。
    let rightDisplayImage: CGImage?
}

@MainActor
class SlideshowEngine {
    static let supportedExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff", "tif"]

    /// Collect image URLs only — no file I/O per image (safe for 1000+ files)
    static func loadImageList(from folderURL: URL) -> [SlideshowImage] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var images: [SlideshowImage] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            images.append(SlideshowImage(url: fileURL, displayName: fileURL.lastPathComponent))
        }

        images.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        return images
    }

    /// Load textures with stereo detection at load time (not at scan time).
    /// URL が file:// ならディスク直読み、それ以外 (http/https) は URLSession でダウンロード後にデコード。
    /// 同じ CGImageSource から色サンプリング用サムネも作って返すので、呼び出し側で再ダウンロード不要。
    static func loadTextures(for image: SlideshowImage) async throws -> LoadedImageTextures {
        let source: CGImageSource
        if image.url.isFileURL {
            guard let s = CGImageSourceCreateWithURL(image.url as CFURL, nil) else {
                throw SlideshowError.imageLoadFailed
            }
            source = s
        } else {
            let data = try await fetchData(from: image.url)
            guard let s = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw SlideshowError.imageLoadFailed
            }
            source = s
        }

        let thumb = makeColorSamplingThumbnail(from: source)

        // Check stereo at load time
        if let indices = stereoImageIndices(from: source),
           let leftCG = makeDisplayThumbnail(source: source, index: indices.left),
           let rightCG = makeDisplayThumbnail(source: source, index: indices.right) {
            let leftTexture = try await TextureResource(image: leftCG, options: .init(semantic: .color))
            let rightTexture = try await TextureResource(image: rightCG, options: .init(semantic: .color))
            let size = computeDisplaySize(width: CGFloat(leftCG.width), height: CGFloat(leftCG.height))
            return LoadedImageTextures(
                leftTexture: leftTexture,
                rightTexture: rightTexture,
                isStereo: true,
                displaySize: size,
                colorSamplingImage: thumb,
                leftDisplayImage: leftCG,
                rightDisplayImage: rightCG
            )
        }

        // Mono
        guard let cgImage = makeDisplayThumbnail(source: source, index: 0) else {
            throw SlideshowError.imageLoadFailed
        }
        let texture = try await TextureResource(image: cgImage, options: .init(semantic: .color))
        let size = computeDisplaySize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return LoadedImageTextures(
            leftTexture: texture,
            rightTexture: nil,
            isStereo: false,
            displaySize: size,
            colorSamplingImage: thumb,
            leftDisplayImage: cgImage,
            rightDisplayImage: nil
        )
    }

    /// 前景マスクを表示テクスチャとは分離して生成する。表示は先に出し、これは後追いで適用する。
    /// 既にデコード済みの表示用 CGImage を受け取るので再ダウンロード/再デコードは発生しない。
    static func foregroundMaskTextures(
        leftImage: CGImage,
        rightImage: CGImage?
    ) async -> (left: TextureResource?, right: TextureResource?) {
        let left = await makeForegroundMaskTexture(from: leftImage)
        // ステレオは右も個別生成 (視差に沿った縁)。モノは右なし。
        let right: TextureResource?
        if let rightImage {
            right = await makeForegroundMaskTexture(from: rightImage)
        } else {
            right = nil
        }
        return (left, right)
    }

    /// 表示用に最大 `maxDisplayPixelSize` px に downsample した CGImage を返す。
    /// 4K Spatial Photo を 4K 全解像でテクスチャ化すると GPU メモリを圧迫するので、
    /// 物理的なパネルサイズに見合った解像度に抑える。
    private static let maxDisplayPixelSize: Int = 2048

    private static func makeDisplayThumbnail(source: CGImageSource, index: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDisplayPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// 画像/動画フレームの「中心検出」で顔の中心を正規化座標 (原点左下、0...1) で返す。
    /// - face: Vision の顔検出。実写向け — イラストの顔は検出できないことが多い。
    /// - saliency: 注目度サリエンシー。人が注目しやすい領域 (イラストでも顔付近に反応しやすい)。
    /// 検出できなければ nil (呼び出し側は画像中心として扱う)。
    static func detectCenter(in image: CGImage, mode: CenterDetectionMode) async -> SIMD2<Float>? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                continuation.resume(returning: detectedCenter(mode: mode, handler: handler))
            }
        }
    }

    /// 動画フレーム (CVPixelBuffer) 版。座標系は CGImage 版と同じ。
    static func detectCenter(inPixelBuffer buffer: CVPixelBuffer, mode: CenterDetectionMode) async -> SIMD2<Float>? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
                continuation.resume(returning: detectedCenter(mode: mode, handler: handler))
            }
        }
    }

    /// アニメ顔検出用の Core ML モデル (deepghs/anime_face_detection v1.4_s を Core ML 変換したもの)。
    /// 初回アクセス時に一度だけロードされる。失敗時は nil (呼び出し側は未検出扱い)。
    nonisolated(unsafe) private static let animeFaceModel: VNCoreMLModel? = {
        guard let mlModel = try? AnimeFaceDetector(configuration: MLModelConfiguration()).model,
              let vnModel = try? VNCoreMLModel(for: mlModel) else {
            print("Failed to load AnimeFaceDetector Core ML model")
            return nil
        }
        return vnModel
    }()

    nonisolated private static func detectedCenter(mode: CenterDetectionMode, handler: VNImageRequestHandler) -> SIMD2<Float>? {
        switch mode {
        case .face:
            let request = VNDetectFaceRectanglesRequest()
            guard (try? handler.perform([request])) != nil,
                  let faces = request.results, !faces.isEmpty else { return nil }
            let largest = faces.max {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }!
            return SIMD2<Float>(Float(largest.boundingBox.midX), Float(largest.boundingBox.midY))
        case .saliency:
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first,
                  let objects = observation.salientObjects, !objects.isEmpty else { return nil }
            let largest = objects.max {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }!
            return SIMD2<Float>(Float(largest.boundingBox.midX), Float(largest.boundingBox.midY))
        case .animeFace:
            guard let vnModel = animeFaceModel else { return nil }
            let request = VNCoreMLRequest(model: vnModel)
            // YOLO (ultralytics) エクスポートの前処理に合わせる
            request.imageCropAndScaleOption = .scaleFill
            guard (try? handler.perform([request])) != nil,
                  let results = request.results as? [VNRecognizedObjectObservation],
                  !results.isEmpty else { return nil }
            let largest = results.max {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }!
            return SIMD2<Float>(Float(largest.boundingBox.midX), Float(largest.boundingBox.midY))
        }
    }

    private static func makeColorSamplingThumbnail(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Foreground Mask (Vision)

    /// Vision 入力に渡す最大辺。品質と速度のバランスで原寸より落とす。
    private static let maskInputMaxPixelSize: Int = 1024

    /// 前景被写体マスクを Vision (`VNGenerateForegroundInstanceMask`) で生成し TextureResource にする。
    /// マスクは色管理しない grayscale なので semantic: .raw。重い同期処理はメインスレッド外で実行。
    /// 生成できない (被写体なし/失敗) 場合は nil を返し、呼び出し側で全表示にフォールバックする。
    private static func makeForegroundMaskTexture(from cgImage: CGImage) async -> TextureResource? {
        let maxSize = maskInputMaxPixelSize
        let maskCG: CGImage? = await Task.detached(priority: .userInitiated) {
            let context = CIContext(options: nil)
            let input = Self.downscaleCGImage(cgImage, maxDimension: maxSize, context: context)
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: input, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else {
                    return nil
                }
                let buffer = try result.generateScaledMaskForImage(
                    forInstances: result.allInstances,
                    from: handler
                )
                let ci = CIImage(cvPixelBuffer: buffer)
                return context.createCGImage(ci, from: ci.extent)
            } catch {
                print("Foreground mask generation failed: \(error)")
                return nil
            }
        }.value
        guard let maskCG else { return nil }
        return try? await TextureResource(image: maskCG, options: .init(semantic: .raw))
    }

    nonisolated private static func downscaleCGImage(_ cgImage: CGImage, maxDimension: Int, context: CIContext) -> CGImage {
        let maxDim = max(cgImage.width, cgImage.height)
        guard maxDim > maxDimension else { return cgImage }
        let scale = CGFloat(maxDimension) / CGFloat(maxDim)
        let w = Int((CGFloat(cgImage.width) * scale).rounded())
        let h = Int((CGFloat(cgImage.height) * scale).rounded())
        let ci = CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h)) ?? cgImage
    }

    // MARK: - Private

    private static func stereoImageIndices(from source: CGImageSource) -> (left: Int, right: Int)? {
        let count = CGImageSourceGetCount(source)
        guard count >= 2 else { return nil }

        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]] else {
            return nil
        }

        for group in groups {
            guard let groupType = group[kCGImagePropertyGroupType] as? String,
                  groupType == (kCGImagePropertyGroupTypeStereoPair as String) else {
                continue
            }
            guard let leftIndex = group[kCGImagePropertyGroupImageIndexLeft] as? Int,
                  let rightIndex = group[kCGImagePropertyGroupImageIndexRight] as? Int else {
                continue
            }
            return (left: leftIndex, right: rightIndex)
        }
        return nil
    }

    private static func computeDisplaySize(width: CGFloat, height: CGFloat) -> CGSize {
        guard width > 0, height > 0 else { return CGSize(width: 1.92, height: 1.08) }
        let maxDimension: CGFloat = 2.0
        let scale = min(maxDimension / width, maxDimension / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    /// ephemeral session でディスク/メモリキャッシュを無効化。大量の HEIC を捌くため毎リクエスト破棄。
    private static let httpSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    private static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, response) = try await httpSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw SlideshowError.imageLoadFailed
            }
            return data
        } catch is SlideshowError {
            throw SlideshowError.imageLoadFailed
        } catch {
            throw SlideshowError.imageLoadFailed
        }
    }
}

enum SlideshowError: Error {
    case imageLoadFailed
}
