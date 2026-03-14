import Foundation
import RealityKit
import ImageIO
import CoreGraphics

struct SlideshowImage {
    let url: URL
    // stereo detection is deferred to load time
}

struct LoadedImageTextures {
    let leftTexture: TextureResource
    let rightTexture: TextureResource?
    let isStereo: Bool
    let displaySize: CGSize
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
            images.append(SlideshowImage(url: fileURL))
        }

        images.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        return images
    }

    /// Load textures with stereo detection at load time (not at scan time)
    static func loadTextures(for image: SlideshowImage) async throws -> LoadedImageTextures {
        guard let source = CGImageSourceCreateWithURL(image.url as CFURL, nil) else {
            throw SlideshowError.imageLoadFailed
        }

        // Check stereo at load time
        if let indices = stereoImageIndices(from: source),
           let leftCG = CGImageSourceCreateImageAtIndex(source, indices.left, nil),
           let rightCG = CGImageSourceCreateImageAtIndex(source, indices.right, nil) {
            let leftTexture = try await TextureResource(image: leftCG, options: .init(semantic: .color))
            let rightTexture = try await TextureResource(image: rightCG, options: .init(semantic: .color))
            let size = computeDisplaySize(width: CGFloat(leftCG.width), height: CGFloat(leftCG.height))
            return LoadedImageTextures(leftTexture: leftTexture, rightTexture: rightTexture, isStereo: true, displaySize: size)
        }

        // Mono
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SlideshowError.imageLoadFailed
        }
        let texture = try await TextureResource(image: cgImage, options: .init(semantic: .color))
        let size = computeDisplaySize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return LoadedImageTextures(leftTexture: texture, rightTexture: nil, isStereo: false, displaySize: size)
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
}

enum SlideshowError: Error {
    case imageLoadFailed
}
