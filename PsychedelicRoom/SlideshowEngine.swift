import Foundation
import RealityKit
import ImageIO
import CoreGraphics

struct SlideshowImage {
    let url: URL
    let isStereo: Bool
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
            let stereo = isStereoImage(at: fileURL)
            images.append(SlideshowImage(url: fileURL, isStereo: stereo))
        }

        images.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        return images
    }

    static func loadTextures(for image: SlideshowImage) async throws -> LoadedImageTextures {
        if image.isStereo, let pair = extractStereoPair(from: image.url) {
            let leftTexture = try await TextureResource(image: pair.left, options: .init(semantic: .color))
            let rightTexture = try await TextureResource(image: pair.right, options: .init(semantic: .color))
            let size = computeDisplaySize(width: CGFloat(pair.left.width), height: CGFloat(pair.left.height))
            return LoadedImageTextures(leftTexture: leftTexture, rightTexture: rightTexture, isStereo: true, displaySize: size)
        } else {
            guard let source = CGImageSourceCreateWithURL(image.url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw SlideshowError.imageLoadFailed
            }
            let texture = try await TextureResource(image: cgImage, options: .init(semantic: .color))
            let size = computeDisplaySize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            return LoadedImageTextures(leftTexture: texture, rightTexture: nil, isStereo: false, displaySize: size)
        }
    }

    static func isStereoImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return stereoImageIndices(from: source) != nil
    }

    static func extractStereoPair(from url: URL) -> (left: CGImage, right: CGImage)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let indices = stereoImageIndices(from: source) else { return nil }
        guard let leftImage = CGImageSourceCreateImageAtIndex(source, indices.left, nil),
              let rightImage = CGImageSourceCreateImageAtIndex(source, indices.right, nil) else {
            return nil
        }
        return (left: leftImage, right: rightImage)
    }

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
