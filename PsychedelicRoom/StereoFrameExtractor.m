#import "StereoFrameExtractor.h"

@interface StereoFramePair ()
- (instancetype)initWithLeft:(nullable CVPixelBufferRef)left
                       right:(nullable CVPixelBufferRef)right;
@end

@implementation StereoFramePair

// _left / _right は __attribute__((NSObject)) なので ARC が retain/release を管理する。
- (instancetype)initWithLeft:(CVPixelBufferRef)left right:(CVPixelBufferRef)right {
    if (self = [super init]) {
        _left = left;
        _right = right;
    }
    return self;
}

@end


@implementation StereoFrameExtractor

+ (nullable AVPlayerVideoOutput *)makeStereoscopicOutput {
    if (@available(visionOS 2.0, *)) {
        CMTagCollectionRef collection = NULL;
        OSStatus status = CMTagCollectionCreateWithVideoOutputPreset(
            kCFAllocatorDefault,
            kCMTagCollectionVideoOutputPreset_Stereoscopic,
            &collection);
        if (status != noErr || collection == NULL) {
            if (collection) { CFRelease(collection); }
            return nil;
        }

        AVVideoOutputSpecification *spec =
            [[AVVideoOutputSpecification alloc] initWithTagCollections:@[ (__bridge id)collection ]];

        // BGRA を要求しておくと Metal テクスチャ化が単純になる。
        NSDictionary *settings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
        [spec setOutputSettings:settings forTagCollection:collection];

        AVPlayerVideoOutput *output = [[AVPlayerVideoOutput alloc] initWithSpecification:spec];

        CFRelease(collection);
        return output;
    }
    return nil;
}

+ (nullable StereoFramePair *)copyStereoFrameFromOutput:(AVPlayerVideoOutput *)output
                                               hostTime:(CMTime)hostTime {
    if (@available(visionOS 2.0, *)) {
        CMTaggedBufferGroupRef group =
            [output copyTaggedBufferGroupForHostTime:hostTime
                               presentationTimeStamp:NULL
                                 activeConfiguration:NULL];
        if (group == NULL) {
            return nil;
        }

        CVPixelBufferRef left = NULL;
        CVPixelBufferRef right = NULL;

        CMItemCount count = CMTaggedBufferGroupGetCount(group);
        for (CMItemCount i = 0; i < count; i++) {
            CMTagCollectionRef tags = CMTaggedBufferGroupGetTagCollectionAtIndex(group, i);
            CVPixelBufferRef pb = CMTaggedBufferGroupGetCVPixelBufferAtIndex(group, i);
            if (tags == NULL || pb == NULL) {
                continue;
            }
            if (CMTagCollectionContainsTag(tags, kCMTagStereoLeftEye)) {
                left = pb;
            } else if (CMTagCollectionContainsTag(tags, kCMTagStereoRightEye)) {
                right = pb;
            } else if (left == NULL) {
                // モノラル動画など stereo タグが無い場合は最初のバッファを左に割り当てる。
                left = pb;
            }
        }

        // StereoFramePair が CVPixelBuffer を retain してから group を解放する。
        StereoFramePair *pair = [[StereoFramePair alloc] initWithLeft:left right:right];
        CFRelease(group);

        if (pair.left == NULL && pair.right == NULL) {
            return nil;
        }
        return pair;
    }
    return nil;
}

@end
