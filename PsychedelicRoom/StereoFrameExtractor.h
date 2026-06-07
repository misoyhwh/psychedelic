#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

/// 立体視動画 1 フレーム分の左右 CVPixelBuffer を保持する。
/// CoreMedia の tagged buffer 抽出 API は CF_REFINED_FOR_SWIFT で Swift から呼べないため、
/// この Objective-C シムで取り出して Swift へ渡す。
API_AVAILABLE(visionos(2.0))
@interface StereoFramePair : NSObject
/// 左目バッファ。モノラル動画では left のみ入り right は nil。
@property (nonatomic, readonly, nullable) __attribute__((NSObject)) CVPixelBufferRef left;
/// 右目バッファ。
@property (nonatomic, readonly, nullable) __attribute__((NSObject)) CVPixelBufferRef right;
@end

/// AVPlayerVideoOutput から指定ホスト時刻のステレオフレームを取り出すヘルパー。
API_AVAILABLE(visionos(2.0))
@interface StereoFrameExtractor : NSObject

/// 立体視出力用の AVPlayerVideoOutput を生成する（BGRA 出力 / Stereoscopic プリセット）。
/// 失敗時は nil。
+ (nullable AVPlayerVideoOutput *)makeStereoscopicOutput;

/// 指定ホスト時刻のフレームを取り出す。新規フレームが無ければ nil。
/// 返る CVPixelBuffer は StereoFramePair が保持する（呼び出し側で解放不要）。
+ (nullable StereoFramePair *)copyStereoFrameFromOutput:(AVPlayerVideoOutput *)output
                                               hostTime:(CMTime)hostTime;

@end

NS_ASSUME_NONNULL_END
