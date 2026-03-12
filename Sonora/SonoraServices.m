//
//  SonoraServices.m
//  Sonora
//

#import "SonoraServices.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <math.h>
#import <mach/mach.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>

#import "AppDelegate.h"
#import "SonoraSettings.h"

NSString * const SonoraPlaybackStateDidChangeNotification = @"SonoraPlaybackStateDidChangeNotification";
NSString * const SonoraPlaybackProgressDidChangeNotification = @"SonoraPlaybackProgressDidChangeNotification";
NSString * const SonoraPlaybackMeterDidChangeNotification = @"SonoraPlaybackMeterDidChangeNotification";
NSString * const SonoraPlaylistsDidChangeNotification = @"SonoraPlaylistsDidChangeNotification";
NSString * const SonoraFavoritesDidChangeNotification = @"SonoraFavoritesDidChangeNotification";
NSString * const SonoraSleepTimerDidChangeNotification = @"SonoraSleepTimerDidChangeNotification";
NSString * const SonoraPlayerSettingsDidChangeNotification = @"SonoraPlayerSettingsDidChangeNotification";

static NSString * const kMusicFolderName = @"Sonora";
static NSString * const kPlaylistsDefaultsKey = @"sonora_playlists_v2";
static NSString * const kPlaylistCoverFolderName = @"PlaylistCovers";
static NSString * const kPlaylistsBackupFileName = @"sonora_playlists_backup_v1.json";
static NSString * const kTrackMetadataCacheDirectoryName = @"TrackMetadataCache";
static NSString * const kTrackMetadataArtworkDirectoryName = @"Artwork";
static NSString * const kTrackMetadataCacheFileName = @"track_metadata_cache_v1.json";
static NSString * const kTrackMetadataCacheModifiedAtMSKey = @"modifiedAtMs";
static NSString * const kTrackMetadataCacheFileSizeKey = @"fileSize";
static NSString * const kTrackMetadataCacheTitleKey = @"title";
static NSString * const kTrackMetadataCacheArtistKey = @"artist";
static NSString * const kTrackMetadataCacheDurationKey = @"duration";
static NSString * const kTrackMetadataCacheArtworkFileKey = @"artworkFile";
static NSString * const kPlayerSettingsSavedShuffleKey = @"sonora.settings.savedShuffleEnabled";
static NSString * const kPlayerSettingsSavedRepeatModeKey = @"sonora.settings.savedRepeatMode";
static NSString * const kPlaybackSessionQueueTrackIDsKey = @"sonora.playbackSession.queueTrackIDs";
static NSString * const kPlaybackSessionCurrentTrackIDKey = @"sonora.playbackSession.currentTrackID";
static NSString * const kPlaybackSessionCurrentTimeKey = @"sonora.playbackSession.currentTime";
static NSString * const kPlaybackSessionWasPlayingKey = @"sonora.playbackSession.wasPlaying";
static NSString * const kMiniStreamingPlaceholderPrefix = @"mini-streaming-placeholder-";
static NSString * const kDiagnosticsDirectoryName = @"SonoraDiagnostics";
static NSString * const kDiagnosticsLogFileName = @"runtime.log";
static NSString * const kDiagnosticsLogFileBackupName = @"runtime-prev.log";
static unsigned long long const kDiagnosticsLogMaxBytes = 4ull * 1024ull * 1024ull;

static BOOL SonoraShouldPreservePlayerModes(NSUserDefaults *defaults) {
    (void)defaults;
    return SonoraSettingsPreservePlayerModesEnabled();
}

static NSArray<NSString *> *SonoraLegacyPlaylistsDefaultsKeys(void) {
    return @[@"sonora_playlists_v1", @"sonora_playlists"];
}

NSString *SonoraStableHashString(NSString *value) {
    if (value.length == 0) {
        return @"0";
    }

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) {
        return @"0";
    }

    const uint8_t *bytes = data.bytes;
    uint64_t hash = 1469598103934665603ULL; // FNV-1a 64-bit
    for (NSUInteger index = 0; index < data.length; index += 1) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }

    return [NSString stringWithFormat:@"%016llx", hash];
}

static dispatch_queue_t SonoraDiagnosticsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.sonora.diagnostics.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString *SonoraDiagnosticsTimestampString(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

static NSURL *SonoraDiagnosticsDirectoryURL(void) {
    NSURL *documentsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (documentsURL == nil) {
        return nil;
    }
    return [documentsURL URLByAppendingPathComponent:kDiagnosticsDirectoryName isDirectory:YES];
}

static NSURL *SonoraDiagnosticsLogFileURL(void) {
    NSURL *directoryURL = SonoraDiagnosticsDirectoryURL();
    if (directoryURL == nil) {
        return nil;
    }
    return [directoryURL URLByAppendingPathComponent:kDiagnosticsLogFileName];
}

static void SonoraDiagnosticsRotateIfNeeded(NSURL *fileURL) {
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:nil];
    unsigned long long currentSize = [attributes[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)] ? [attributes[NSFileSize] unsignedLongLongValue] : 0ull;
    if (currentSize < kDiagnosticsLogMaxBytes) {
        return;
    }

    NSURL *directoryURL = [fileURL URLByDeletingLastPathComponent];
    NSURL *backupURL = [directoryURL URLByAppendingPathComponent:kDiagnosticsLogFileBackupName];
    [NSFileManager.defaultManager removeItemAtURL:backupURL error:nil];
    [NSFileManager.defaultManager moveItemAtURL:fileURL toURL:backupURL error:nil];
}

void SonoraDiagnosticsLog(NSString *component, NSString *message) {
    NSString *normalizedComponent = [component isKindOfClass:NSString.class] ? component : @"app";
    NSString *normalizedMessage = [message isKindOfClass:NSString.class] ? message : @"";
    if (normalizedMessage.length == 0) {
        return;
    }

    dispatch_async(SonoraDiagnosticsQueue(), ^{
        NSURL *directoryURL = SonoraDiagnosticsDirectoryURL();
        NSURL *fileURL = SonoraDiagnosticsLogFileURL();
        if (directoryURL == nil || fileURL == nil) {
            return;
        }

        [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
        SonoraDiagnosticsRotateIfNeeded(fileURL);

        NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n", SonoraDiagnosticsTimestampString(), normalizedComponent, normalizedMessage];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length == 0) {
            return;
        }

        if (![NSFileManager.defaultManager fileExistsAtPath:fileURL.path]) {
            [NSFileManager.defaultManager createFileAtPath:fileURL.path contents:nil attributes:nil];
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:fileURL error:nil];
        if (handle == nil) {
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (__unused NSException *exception) {
        } @finally {
            [handle closeFile];
        }
    });
}

NSString *SonoraDiagnosticsLogFilePath(void) {
    NSURL *fileURL = SonoraDiagnosticsLogFileURL();
    return fileURL.path ?: @"";
}

static uint64_t SonoraProcessPhysicalFootprintBytes(void) {
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t status = task_info(mach_task_self_, TASK_VM_INFO, (task_info_t)&vmInfo, &count);
    if (status == KERN_SUCCESS && vmInfo.phys_footprint > 0) {
        return vmInfo.phys_footprint;
    }

    mach_task_basic_info_data_t basicInfo;
    mach_msg_type_number_t basicCount = MACH_TASK_BASIC_INFO_COUNT;
    status = task_info(mach_task_self_, MACH_TASK_BASIC_INFO, (task_info_t)&basicInfo, &basicCount);
    if (status == KERN_SUCCESS) {
        return (uint64_t)basicInfo.resident_size;
    }
    return 0ull;
}

static double SonoraProcessCPUUsagePercent(void) {
    thread_array_t threads = NULL;
    mach_msg_type_number_t threadCount = 0;
    kern_return_t status = task_threads(mach_task_self_, &threads, &threadCount);
    if (status != KERN_SUCCESS || threads == NULL || threadCount == 0) {
        return -1.0;
    }

    double totalCPU = 0.0;
    for (mach_msg_type_number_t index = 0; index < threadCount; index += 1) {
        thread_basic_info_data_t basicInfo;
        mach_msg_type_number_t infoCount = THREAD_BASIC_INFO_COUNT;
        status = thread_info(threads[index], THREAD_BASIC_INFO, (thread_info_t)&basicInfo, &infoCount);
        if (status != KERN_SUCCESS) {
            continue;
        }
        if ((basicInfo.flags & TH_FLAGS_IDLE) != 0) {
            continue;
        }
        totalCPU += ((double)basicInfo.cpu_usage / (double)TH_USAGE_SCALE) * 100.0;
    }

    vm_size_t deallocateSize = (vm_size_t)threadCount * (vm_size_t)sizeof(thread_t);
    vm_deallocate(mach_task_self_, (vm_address_t)threads, deallocateSize);
    return totalCPU;
}

#pragma mark - Artwork Accent

static UIColor *SonoraAverageColorFromImage(UIImage *image) {
    if (image == nil || image.CGImage == nil) {
        return nil;
    }

    CIImage *inputImage = [[CIImage alloc] initWithCGImage:image.CGImage];
    if (inputImage == nil) {
        return nil;
    }

    CIFilter *filter = [CIFilter filterWithName:@"CIAreaAverage"];
    if (filter == nil) {
        return nil;
    }
    [filter setValue:inputImage forKey:kCIInputImageKey];
    [filter setValue:[CIVector vectorWithCGRect:inputImage.extent] forKey:kCIInputExtentKey];

    CIImage *outputImage = filter.outputImage;
    if (outputImage == nil) {
        return nil;
    }

    static CIContext *context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO
        }];
    });

    uint8_t rgba[4] = {0, 0, 0, 0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == nil) {
        return nil;
    }

    [context render:outputImage
           toBitmap:rgba
           rowBytes:4
             bounds:CGRectMake(0.0, 0.0, 1.0, 1.0)
             format:kCIFormatRGBA8
         colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);

    CGFloat alpha = ((CGFloat)rgba[3]) / 255.0;
    if (alpha <= 0.02) {
        return nil;
    }

    return [UIColor colorWithRed:((CGFloat)rgba[0]) / 255.0
                           green:((CGFloat)rgba[1]) / 255.0
                            blue:((CGFloat)rgba[2]) / 255.0
                           alpha:1.0];
}

enum {
    SonoraAccentHueBinCount = 36,
    SonoraAccentSaturationBinCount = 5,
    SonoraAccentBrightnessBinCount = 4
};

typedef struct {
    CGFloat weight;
    CGFloat red;
    CGFloat green;
    CGFloat blue;
    CGFloat saturation;
    CGFloat brightness;
} SonoraAccentHistogramBin;

static UIColor *SonoraVibrantColorFromImage(UIImage *image) {
    if (image == nil || image.CGImage == nil) {
        return nil;
    }

    const size_t width = 40;
    const size_t height = 40;
    const size_t bytesPerRow = width * 4;
    uint8_t *pixels = calloc(height, bytesPerRow);
    if (pixels == NULL) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == nil) {
        free(pixels);
        return nil;
    }

    CGBitmapInfo bitmapInfo = (CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextRef bitmapContext = CGBitmapContextCreate(pixels,
                                                       width,
                                                       height,
                                                       8,
                                                       bytesPerRow,
                                                       colorSpace,
                                                       bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (bitmapContext == NULL) {
        free(pixels);
        return nil;
    }

    CGContextSetInterpolationQuality(bitmapContext, kCGInterpolationHigh);
    CGContextDrawImage(bitmapContext, CGRectMake(0.0, 0.0, width, height), image.CGImage);

    SonoraAccentHistogramBin bins[SonoraAccentHueBinCount * SonoraAccentSaturationBinCount * SonoraAccentBrightnessBinCount] = {0};
    static const CGFloat kCenterMaxDistance = 0.70710678;

    CGFloat bestScore = -1.0;
    NSUInteger bestBinIndex = NSNotFound;

    for (size_t y = 0; y < height; y += 1) {
        for (size_t x = 0; x < width; x += 1) {
            size_t offset = y * bytesPerRow + x * 4;
            CGFloat alpha = ((CGFloat)pixels[offset + 3]) / 255.0;
            if (alpha < 0.14) {
                continue;
            }

            CGFloat red = ((CGFloat)pixels[offset + 0]) / 255.0;
            CGFloat green = ((CGFloat)pixels[offset + 1]) / 255.0;
            CGFloat blue = ((CGFloat)pixels[offset + 2]) / 255.0;
            UIColor *candidate = [UIColor colorWithRed:red green:green blue:blue alpha:1.0];

            CGFloat hue = 0.0;
            CGFloat saturation = 0.0;
            CGFloat brightness = 0.0;
            CGFloat outAlpha = 1.0;
            if (![candidate getHue:&hue saturation:&saturation brightness:&brightness alpha:&outAlpha]) {
                continue;
            }

            if (saturation < 0.12 || brightness < 0.16 || brightness > 0.98) {
                continue;
            }

            NSUInteger hueIndex = MIN((NSUInteger)floor(hue * (CGFloat)SonoraAccentHueBinCount), (NSUInteger)(SonoraAccentHueBinCount - 1));
            NSUInteger saturationIndex = MIN((NSUInteger)floor(saturation * (CGFloat)SonoraAccentSaturationBinCount), (NSUInteger)(SonoraAccentSaturationBinCount - 1));
            NSUInteger brightnessIndex = MIN((NSUInteger)floor(brightness * (CGFloat)SonoraAccentBrightnessBinCount), (NSUInteger)(SonoraAccentBrightnessBinCount - 1));
            NSUInteger binIndex = (hueIndex * SonoraAccentSaturationBinCount * SonoraAccentBrightnessBinCount) +
            (saturationIndex * SonoraAccentBrightnessBinCount) +
            brightnessIndex;

            CGFloat normalizedX = (((CGFloat)x) + 0.5) / ((CGFloat)width);
            CGFloat normalizedY = (((CGFloat)y) + 0.5) / ((CGFloat)height);
            CGFloat distance = hypot(normalizedX - 0.5, normalizedY - 0.5) / kCenterMaxDistance;
            distance = MIN(MAX(distance, 0.0), 1.0);
            CGFloat centerBias = 1.0 - (distance * 0.32);
            CGFloat weight = alpha * (0.34 + saturation * 0.66) * (0.42 + brightness * 0.58) * centerBias;

            bins[binIndex].weight += weight;
            bins[binIndex].red += red * weight;
            bins[binIndex].green += green * weight;
            bins[binIndex].blue += blue * weight;
            bins[binIndex].saturation += saturation * weight;
            bins[binIndex].brightness += brightness * weight;

            CGFloat averageSaturation = bins[binIndex].saturation / bins[binIndex].weight;
            CGFloat averageBrightness = bins[binIndex].brightness / bins[binIndex].weight;
            CGFloat score = bins[binIndex].weight *
            (0.55 + averageSaturation * 0.45) *
            (0.46 + averageBrightness * 0.54);
            if (score > bestScore) {
                bestScore = score;
                bestBinIndex = binIndex;
            }
        }
    }

    CGContextRelease(bitmapContext);
    free(pixels);

    if (bestBinIndex == NSNotFound || bins[bestBinIndex].weight <= 0.0) {
        return nil;
    }

    SonoraAccentHistogramBin bestBin = bins[bestBinIndex];
    return [UIColor colorWithRed:(bestBin.red / bestBin.weight)
                           green:(bestBin.green / bestBin.weight)
                            blue:(bestBin.blue / bestBin.weight)
                           alpha:1.0];
}

static UIColor *SonoraNormalizedAccentColor(UIColor *rawColor, CGFloat minimumSaturation) {
    if (rawColor == nil) {
        return nil;
    }

    CGFloat hue = 0.0;
    CGFloat saturation = 0.0;
    CGFloat brightness = 0.0;
    CGFloat alpha = 1.0;
    if (![rawColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        return nil;
    }

    if (saturation < minimumSaturation) {
        return nil;
    }

    saturation = MIN(MAX(saturation * 1.18, 0.40), 0.96);
    brightness = MIN(MAX(brightness * 0.92, 0.38), 0.90);
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1.0];
}

static UIColor *SonoraBlendedAccentColor(UIColor *primaryColor, UIColor *secondaryColor, CGFloat secondaryWeight) {
    if (primaryColor == nil) {
        return secondaryColor;
    }
    if (secondaryColor == nil) {
        return primaryColor;
    }

    CGFloat primaryRed = 0.0;
    CGFloat primaryGreen = 0.0;
    CGFloat primaryBlue = 0.0;
    CGFloat primaryAlpha = 1.0;
    CGFloat secondaryRed = 0.0;
    CGFloat secondaryGreen = 0.0;
    CGFloat secondaryBlue = 0.0;
    CGFloat secondaryAlpha = 1.0;

    BOOL hasPrimaryRGB = [primaryColor getRed:&primaryRed
                                        green:&primaryGreen
                                         blue:&primaryBlue
                                        alpha:&primaryAlpha];
    BOOL hasSecondaryRGB = [secondaryColor getRed:&secondaryRed
                                            green:&secondaryGreen
                                             blue:&secondaryBlue
                                            alpha:&secondaryAlpha];
    if (!hasPrimaryRGB || !hasSecondaryRGB) {
        return primaryColor;
    }

    CGFloat clampedWeight = MIN(MAX(secondaryWeight, 0.0), 1.0);
    CGFloat primaryWeight = 1.0 - clampedWeight;
    return [UIColor colorWithRed:(primaryRed * primaryWeight + secondaryRed * clampedWeight)
                           green:(primaryGreen * primaryWeight + secondaryGreen * clampedWeight)
                            blue:(primaryBlue * primaryWeight + secondaryBlue * clampedWeight)
                           alpha:1.0];
}

@implementation SonoraArtworkAccentColorService

+ (UIColor *)dominantAccentColorForImage:(nullable UIImage *)image
                                fallback:(UIColor *)fallbackColor {
    UIColor *fallback = fallbackColor ?: [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
    if (image == nil) {
        return fallback;
    }

    UIColor *vibrantColor = SonoraNormalizedAccentColor(SonoraVibrantColorFromImage(image), 0.10);
    UIColor *averageColor = SonoraNormalizedAccentColor(SonoraAverageColorFromImage(image), 0.06);

    if (vibrantColor != nil && averageColor != nil) {
        return SonoraBlendedAccentColor(vibrantColor, averageColor, 0.20);
    }

    if (vibrantColor != nil) {
        return vibrantColor;
    }

    if (averageColor != nil) {
        return averageColor;
    }

    return fallback;
}

@end

static NSSet<NSString *> *SonoraAudioExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"mp3", @"m4a", @"wav", @"aac", @"flac", @"aiff", @"caf", @"alac"]];
    });
    return extensions;
}

static UIImage *SonoraPlaceholderArtwork(NSString *seed, CGSize size) {
    CGSize normalizedSize = CGSizeMake(MAX(size.width, 2.0), MAX(size.height, 2.0));
    NSUInteger hash = seed.hash;

    CGFloat hue = (hash % 255) / 255.0;
    UIColor *fillColor = [UIColor colorWithHue:hue saturation:0.18 brightness:0.34 alpha:1.0];

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [fillColor setFill];
        UIRectFill(CGRectMake(0, 0, normalizedSize.width, normalizedSize.height));

        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:normalizedSize.width * 0.35
                                                                                               weight:UIImageSymbolWeightBold];
        UIImage *symbol = [UIImage systemImageNamed:@"music.note" withConfiguration:config];
        [[UIColor colorWithWhite:1.0 alpha:0.82] setFill];
        [symbol drawInRect:CGRectMake((normalizedSize.width - symbol.size.width) * 0.5,
                                      (normalizedSize.height - symbol.size.height) * 0.5,
                                      symbol.size.width,
                                      symbol.size.height)];
    }];
}

static UIImage *SonoraCollageCover(NSArray<UIImage *> *images, CGSize size) {
    CGSize normalizedSize = CGSizeMake(MAX(size.width, 2.0), MAX(size.height, 2.0));
    CGFloat gap = MAX(2.0, normalizedSize.width * 0.015);

    NSArray<UIImage *> *usableImages = images;
    if (usableImages.count > 4) {
        usableImages = [usableImages subarrayWithRange:NSMakeRange(0, 4)];
    }

    if (usableImages.count == 0) {
        return SonoraPlaceholderArtwork(@"playlist-empty", normalizedSize);
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0, 0, normalizedSize.width, normalizedSize.height));

        if (usableImages.count == 1) {
            [usableImages[0] drawInRect:CGRectMake(0, 0, normalizedSize.width, normalizedSize.height)];
            return;
        }

        if (usableImages.count == 2) {
            CGFloat width = (normalizedSize.width - gap) * 0.5;
            [usableImages[0] drawInRect:CGRectMake(0, 0, width, normalizedSize.height)];
            [usableImages[1] drawInRect:CGRectMake(width + gap, 0, width, normalizedSize.height)];
            return;
        }

        if (usableImages.count == 3) {
            CGFloat leftWidth = floor((normalizedSize.width - gap) * 0.42);
            CGFloat rightWidth = normalizedSize.width - leftWidth - gap;
            CGFloat leftHeight = (normalizedSize.height - gap) * 0.5;

            [usableImages[0] drawInRect:CGRectMake(0, 0, leftWidth, leftHeight)];
            [usableImages[1] drawInRect:CGRectMake(0, leftHeight + gap, leftWidth, leftHeight)];
            [usableImages[2] drawInRect:CGRectMake(leftWidth + gap, 0, rightWidth, normalizedSize.height)];
            return;
        }

        CGFloat tile = (normalizedSize.width - gap) * 0.5;
        [usableImages[0] drawInRect:CGRectMake(0, 0, tile, tile)];
        [usableImages[1] drawInRect:CGRectMake(tile + gap, 0, tile, tile)];
        [usableImages[2] drawInRect:CGRectMake(0, tile + gap, tile, tile)];
        [usableImages[3] drawInRect:CGRectMake(tile + gap, tile + gap, tile, tile)];
    }];
}

static NSData *SonoraEncodedCoverData(UIImage *image) {
    if (image == nil) {
        return nil;
    }

    NSData *pngData = UIImagePNGRepresentation(image);
    if (pngData.length > 0) {
        return pngData;
    }

    NSData *jpegData = UIImageJPEGRepresentation(image, 0.96);
    if (jpegData.length > 0) {
        return jpegData;
    }

    CGSize fallbackSize = image.size;
    if (fallbackSize.width <= 1.0 || fallbackSize.height <= 1.0) {
        fallbackSize = CGSizeMake(512.0, 512.0);
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:fallbackSize];
    UIImage *rendered = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull context) {
        [image drawInRect:CGRectMake(0, 0, fallbackSize.width, fallbackSize.height)];
    }];
    return UIImagePNGRepresentation(rendered);
}

#pragma mark - Library

@interface SonoraLibraryManager ()

@property (nonatomic, copy) NSArray<SonoraTrack *> *cachedTracks;
@property (nonatomic, copy) NSDictionary<NSString *, SonoraTrack *> *tracksByID;
@property (nonatomic, copy) NSDictionary<NSString *, SonoraTrack *> *tracksByRelativeID;
@property (nonatomic, copy) NSDictionary<NSString *, SonoraTrack *> *tracksByFileName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *trackMetadataCache;
@property (nonatomic, assign) BOOL trackMetadataCacheLoaded;
@property (nonatomic, assign) BOOL trackMetadataCacheDirty;

@end

@implementation SonoraLibraryManager

+ (instancetype)sharedManager {
    static SonoraLibraryManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SonoraLibraryManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedTracks = @[];
        _tracksByID = @{};
        _tracksByRelativeID = @{};
        _tracksByFileName = @{};
        _trackMetadataCache = [NSMutableDictionary dictionary];
        _trackMetadataCacheLoaded = NO;
        _trackMetadataCacheDirty = NO;
        [self reloadTracks];
    }
    return self;
}

- (NSURL *)musicDirectoryURL {
    NSURL *documentsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directoryURL = [documentsURL URLByAppendingPathComponent:kMusicFolderName isDirectory:YES];

    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&error];
    if (error != nil) {
        NSLog(@"Cannot create music directory: %@", error.localizedDescription);
    }

    return directoryURL;
}

- (NSString *)filesDropHint {
    return @"Files -> On My iPhone -> Sonora -> Sonora";
}

- (NSArray<SonoraTrack *> *)tracks {
    return self.cachedTracks;
}

- (NSURL *)trackMetadataCacheDirectoryURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *baseURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (baseURL == nil) {
        baseURL = [fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    }
    if (baseURL == nil) {
        baseURL = [self musicDirectoryURL];
    }

    NSURL *m2DirectoryURL = [baseURL URLByAppendingPathComponent:@"Sonora" isDirectory:YES];
    NSURL *cacheDirectoryURL = [m2DirectoryURL URLByAppendingPathComponent:kTrackMetadataCacheDirectoryName isDirectory:YES];

    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:cacheDirectoryURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    if (directoryError != nil) {
        NSLog(@"Cannot create track metadata cache directory: %@", directoryError.localizedDescription);
    }
    return cacheDirectoryURL;
}

- (NSURL *)trackArtworkCacheDirectoryURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *artworkDirectoryURL = [[self trackMetadataCacheDirectoryURL] URLByAppendingPathComponent:kTrackMetadataArtworkDirectoryName
                                                                                         isDirectory:YES];
    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:artworkDirectoryURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    if (directoryError != nil) {
        NSLog(@"Cannot create track artwork cache directory: %@", directoryError.localizedDescription);
    }
    return artworkDirectoryURL;
}

- (NSURL *)trackMetadataCacheFileURL {
    return [[self trackMetadataCacheDirectoryURL] URLByAppendingPathComponent:kTrackMetadataCacheFileName];
}

- (void)loadTrackMetadataCacheIfNeeded {
    if (self.trackMetadataCacheLoaded) {
        return;
    }
    self.trackMetadataCacheLoaded = YES;
    [self.trackMetadataCache removeAllObjects];

    NSURL *cacheFileURL = [self trackMetadataCacheFileURL];
    if (![NSFileManager.defaultManager fileExistsAtPath:cacheFileURL.path]) {
        return;
    }

    NSData *data = [NSData dataWithContentsOfURL:cacheFileURL];
    if (data.length == 0) {
        return;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError != nil || ![object isKindOfClass:NSDictionary.class]) {
        NSLog(@"Track metadata cache parse error: %@", jsonError.localizedDescription);
        return;
    }

    NSDictionary *rawCache = (NSDictionary *)object;
    for (id key in rawCache) {
        id value = rawCache[key];
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSDictionary.class]) {
            self.trackMetadataCache[(NSString *)key] = (NSDictionary<NSString *, id> *)value;
        }
    }
}

- (void)persistTrackMetadataCacheIfNeeded {
    if (!self.trackMetadataCacheDirty) {
        return;
    }

    NSURL *cacheFileURL = [self trackMetadataCacheFileURL];
    NSDictionary<NSString *, NSDictionary<NSString *, id> *> *payload = [self.trackMetadataCache copy] ?: @{};
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError != nil || data.length == 0) {
        NSLog(@"Track metadata cache encode error: %@", jsonError.localizedDescription);
        return;
    }

    NSError *writeError = nil;
    [data writeToURL:cacheFileURL options:NSDataWritingAtomic error:&writeError];
    if (writeError != nil) {
        NSLog(@"Track metadata cache write error: %@", writeError.localizedDescription);
        return;
    }

    self.trackMetadataCacheDirty = NO;
}

- (NSString *)normalizedPathStringFromIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return @"";
    }

    NSString *normalized = [identifier stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if ([normalized hasPrefix:@"file://"]) {
        NSURL *fileURL = [NSURL URLWithString:normalized];
        if (fileURL.fileURL && fileURL.path.length > 0) {
            normalized = fileURL.path;
        }
    }
    return normalized;
}

- (NSString *)relativeTrackLookupKeyForIdentifier:(NSString *)identifier {
    NSString *normalized = [self normalizedPathStringFromIdentifier:identifier];
    if (normalized.length == 0) {
        return @"";
    }

    NSString *documentsToken = [NSString stringWithFormat:@"/Documents/%@/", kMusicFolderName];
    NSRange documentsRange = [normalized rangeOfString:documentsToken options:NSCaseInsensitiveSearch];
    if (documentsRange.location != NSNotFound) {
        NSString *relative = [normalized substringFromIndex:NSMaxRange(documentsRange)];
        while ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        return relative.lowercaseString;
    }

    NSString *folderToken = [NSString stringWithFormat:@"/%@/", kMusicFolderName];
    NSRange folderRange = [normalized rangeOfString:folderToken options:(NSCaseInsensitiveSearch | NSBackwardsSearch)];
    if (folderRange.location != NSNotFound && NSMaxRange(folderRange) < normalized.length) {
        NSString *relative = [normalized substringFromIndex:NSMaxRange(folderRange)];
        while ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        return relative.lowercaseString;
    }

    if (![normalized hasPrefix:@"/"]) {
        NSString *relative = normalized;
        while ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        return relative.lowercaseString;
    }

    return @"";
}

- (NSString *)cacheKeyForFileURL:(NSURL *)fileURL inMusicDirectory:(NSURL *)musicDirectoryURL {
    NSString *musicPath = musicDirectoryURL.path ?: @"";
    NSString *filePath = fileURL.path ?: @"";
    if (musicPath.length > 0 && [filePath hasPrefix:musicPath]) {
        NSString *relative = [filePath substringFromIndex:musicPath.length];
        while ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        if (relative.length > 0) {
            return relative.lowercaseString;
        }
    }

    NSString *fallback = fileURL.lastPathComponent.lowercaseString;
    if (fallback.length > 0) {
        return fallback;
    }
    return filePath.lowercaseString ?: @"";
}

- (NSNumber *)cacheTimestampValueForDate:(NSDate *)date {
    if (![date isKindOfClass:NSDate.class]) {
        return @(0);
    }
    NSTimeInterval timestamp = date.timeIntervalSince1970;
    if (!isfinite(timestamp) || timestamp < 0.0) {
        return @(0);
    }
    return @((long long)llround(timestamp * 1000.0));
}

- (BOOL)cacheEntry:(NSDictionary<NSString *, id> *)entry
  matchesFileSize:(NSNumber *)fileSize
      modifiedDate:(NSDate *)modifiedDate {
    if (![entry isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSNumber *cachedSize = entry[kTrackMetadataCacheFileSizeKey];
    NSNumber *cachedTimestamp = entry[kTrackMetadataCacheModifiedAtMSKey];
    if (![cachedSize isKindOfClass:NSNumber.class] || ![cachedTimestamp isKindOfClass:NSNumber.class]) {
        return NO;
    }

    long long currentSize = [fileSize isKindOfClass:NSNumber.class] ? fileSize.longLongValue : 0;
    long long currentTimestamp = [self cacheTimestampValueForDate:modifiedDate].longLongValue;
    return (cachedSize.longLongValue == currentSize &&
            cachedTimestamp.longLongValue == currentTimestamp);
}

- (NSDictionary<NSString *, id> *)cacheEntryForTrack:(SonoraTrack *)track
                                            fileSize:(NSNumber *)fileSize
                                        modifiedDate:(NSDate *)modifiedDate
                                     artworkFileName:(nullable NSString *)artworkFileName {
    NSMutableDictionary<NSString *, id> *entry = [NSMutableDictionary dictionary];
    entry[kTrackMetadataCacheModifiedAtMSKey] = [self cacheTimestampValueForDate:modifiedDate];
    entry[kTrackMetadataCacheFileSizeKey] = [fileSize isKindOfClass:NSNumber.class] ? fileSize : @(0);
    entry[kTrackMetadataCacheTitleKey] = track.title ?: @"";
    entry[kTrackMetadataCacheArtistKey] = track.artist ?: @"";
    entry[kTrackMetadataCacheDurationKey] = @(MAX(0.0, track.duration));
    if (artworkFileName.length > 0) {
        entry[kTrackMetadataCacheArtworkFileKey] = artworkFileName;
    }
    return [entry copy];
}

- (nullable UIImage *)cachedArtworkForFileName:(NSString *)fileName {
    if (fileName.length == 0) {
        return nil;
    }
    NSURL *fileURL = [[self trackArtworkCacheDirectoryURL] URLByAppendingPathComponent:fileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:fileURL.path]) {
        return nil;
    }
    return [UIImage imageWithContentsOfFile:fileURL.path];
}

- (nullable NSString *)storeArtworkInCache:(UIImage *)image
                                  cacheKey:(NSString *)cacheKey
                                  fileSize:(NSNumber *)fileSize
                              modifiedDate:(NSDate *)modifiedDate {
    if (image == nil || cacheKey.length == 0) {
        return nil;
    }

    NSData *artworkData = UIImageJPEGRepresentation(image, 0.86);
    if (artworkData.length == 0) {
        artworkData = UIImagePNGRepresentation(image);
    }
    if (artworkData.length == 0) {
        return nil;
    }

    NSString *seed = [NSString stringWithFormat:@"%@|%@|%@",
                      cacheKey,
                      ([fileSize isKindOfClass:NSNumber.class] ? fileSize.stringValue : @"0"),
                      [self cacheTimestampValueForDate:modifiedDate].stringValue];
    NSString *fileName = [NSString stringWithFormat:@"%@.jpg", SonoraStableHashString(seed)];
    NSURL *fileURL = [[self trackArtworkCacheDirectoryURL] URLByAppendingPathComponent:fileName];

    NSError *writeError = nil;
    [artworkData writeToURL:fileURL options:NSDataWritingAtomic error:&writeError];
    if (writeError != nil) {
        NSLog(@"Track artwork cache write error: %@", writeError.localizedDescription);
        return nil;
    }
    return fileName;
}

- (nullable SonoraTrack *)trackFromCacheEntry:(NSDictionary<NSString *, id> *)entry
                                  fileURL:(NSURL *)fileURL
                                 fileSize:(NSNumber *)fileSize
                             modifiedDate:(NSDate *)modifiedDate {
    if (![self cacheEntry:entry matchesFileSize:fileSize modifiedDate:modifiedDate]) {
        return nil;
    }

    NSString *fallbackTitle = fileURL.lastPathComponent.stringByDeletingPathExtension;
    NSString *title = [entry[kTrackMetadataCacheTitleKey] isKindOfClass:NSString.class] ? entry[kTrackMetadataCacheTitleKey] : fallbackTitle;
    if (title.length == 0) {
        title = fallbackTitle.length > 0 ? fallbackTitle : fileURL.lastPathComponent;
    }
    NSString *artist = [entry[kTrackMetadataCacheArtistKey] isKindOfClass:NSString.class] ? entry[kTrackMetadataCacheArtistKey] : @"";
    NSNumber *durationValue = [entry[kTrackMetadataCacheDurationKey] isKindOfClass:NSNumber.class] ? entry[kTrackMetadataCacheDurationKey] : @(0);
    NSTimeInterval duration = durationValue.doubleValue;
    if (!isfinite(duration) || duration < 0.0) {
        duration = 0.0;
    }

    NSString *artworkFileName = [entry[kTrackMetadataCacheArtworkFileKey] isKindOfClass:NSString.class] ? entry[kTrackMetadataCacheArtworkFileKey] : nil;
    UIImage *artwork = [self cachedArtworkForFileName:artworkFileName];
    if (artwork == nil) {
        artwork = SonoraPlaceholderArtwork(title, CGSizeMake(180, 180));
    }

    SonoraTrack *track = [[SonoraTrack alloc] init];
    track.identifier = fileURL.path;
    track.title = title;
    track.artist = artist ?: @"";
    track.fileName = fileURL.lastPathComponent;
    track.url = fileURL;
    track.duration = duration;
    track.artwork = artwork;
    return track;
}

- (NSArray<SonoraTrack *> *)reloadTracks {
    NSURL *musicURL = [self musicDirectoryURL];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    [self loadTrackMetadataCacheIfNeeded];
    NSDictionary<NSString *, NSDictionary<NSString *, id> *> *previousCacheSnapshot = [self.trackMetadataCache copy] ?: @{};
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *nextCache = [NSMutableDictionary dictionaryWithCapacity:previousCacheSnapshot.count];

    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray array];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:musicURL
                                                   includingPropertiesForKeys:@[NSURLIsDirectoryKey,
                                                                                NSURLNameKey,
                                                                                NSURLContentModificationDateKey,
                                                                                NSURLFileSizeKey]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        NSLog(@"Directory enumeration error for %@: %@", url.path, error.localizedDescription);
        return YES;
    }];

    for (NSURL *fileURL in enumerator) {
        NSNumber *isDirectory = nil;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) {
            continue;
        }

        NSString *extension = fileURL.pathExtension.lowercaseString;
        if (![SonoraAudioExtensions() containsObject:extension]) {
            continue;
        }

        NSNumber *fileSize = nil;
        NSDate *modifiedDate = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        [fileURL getResourceValue:&modifiedDate forKey:NSURLContentModificationDateKey error:nil];
        if (![fileSize isKindOfClass:NSNumber.class]) {
            fileSize = @(0);
        }
        if (![modifiedDate isKindOfClass:NSDate.class]) {
            modifiedDate = [NSDate dateWithTimeIntervalSince1970:0];
        }

        NSString *cacheKey = [self cacheKeyForFileURL:fileURL inMusicDirectory:musicURL];
        NSDictionary<NSString *, id> *cachedEntry = cacheKey.length > 0 ? self.trackMetadataCache[cacheKey] : nil;
        SonoraTrack *track = [self trackFromCacheEntry:cachedEntry
                                           fileURL:fileURL
                                          fileSize:fileSize
                                      modifiedDate:modifiedDate];
        NSDictionary<NSString *, id> *entryForNext = nil;
        if (track != nil && cachedEntry != nil) {
            entryForNext = cachedEntry;
        } else {
            UIImage *embeddedArtwork = nil;
            track = [self trackFromURL:fileURL embeddedArtworkOut:&embeddedArtwork];
            if (track != nil) {
                NSString *artworkFileName = [self storeArtworkInCache:embeddedArtwork
                                                              cacheKey:cacheKey
                                                              fileSize:fileSize
                                                          modifiedDate:modifiedDate];
                entryForNext = [self cacheEntryForTrack:track
                                               fileSize:fileSize
                                           modifiedDate:modifiedDate
                                        artworkFileName:artworkFileName];
            }
        }

        if (cacheKey.length > 0 && entryForNext != nil) {
            nextCache[cacheKey] = entryForNext;
        }

        if (track != nil) {
            [tracks addObject:track];
        }
    }

    [tracks sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        NSComparisonResult titleCompare = [left.title localizedCaseInsensitiveCompare:right.title];
        if (titleCompare != NSOrderedSame) {
            return titleCompare;
        }
        return [left.fileName localizedCaseInsensitiveCompare:right.fileName];
    }];

    NSMutableDictionary<NSString *, SonoraTrack *> *mapping = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    NSMutableDictionary<NSString *, SonoraTrack *> *relativeMapping = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    NSMutableDictionary<NSString *, id> *fileNameCandidates = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            mapping[track.identifier] = track;
            NSString *relativeKey = [self relativeTrackLookupKeyForIdentifier:track.identifier];
            if (relativeKey.length > 0 && relativeMapping[relativeKey] == nil) {
                relativeMapping[relativeKey] = track;
            }
        }

        NSString *fileNameKey = track.fileName.lowercaseString;
        if (fileNameKey.length > 0) {
            id existing = fileNameCandidates[fileNameKey];
            if (existing == nil) {
                fileNameCandidates[fileNameKey] = track;
            } else if (![existing isKindOfClass:NSNull.class]) {
                fileNameCandidates[fileNameKey] = NSNull.null;
            }
        }
    }

    NSMutableDictionary<NSString *, SonoraTrack *> *fileNameMapping = [NSMutableDictionary dictionaryWithCapacity:fileNameCandidates.count];
    for (NSString *fileNameKey in fileNameCandidates) {
        id value = fileNameCandidates[fileNameKey];
        if ([value isKindOfClass:SonoraTrack.class]) {
            fileNameMapping[fileNameKey] = (SonoraTrack *)value;
        }
    }

    self.cachedTracks = [tracks copy];
    self.tracksByID = [mapping copy];
    self.tracksByRelativeID = [relativeMapping copy];
    self.tracksByFileName = [fileNameMapping copy];

    self.trackMetadataCache = nextCache;
    NSDictionary<NSString *, NSDictionary<NSString *, id> *> *nextCacheSnapshot = [nextCache copy] ?: @{};
    if (![previousCacheSnapshot isEqualToDictionary:nextCacheSnapshot]) {
        self.trackMetadataCacheDirty = YES;
        [self persistTrackMetadataCacheIfNeeded];
    }

    return self.cachedTracks;
}

- (nullable SonoraTrack *)trackForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }

    SonoraTrack *directTrack = self.tracksByID[identifier];
    if (directTrack != nil) {
        return directTrack;
    }

    NSString *normalizedIdentifier = [self normalizedPathStringFromIdentifier:identifier];
    if (normalizedIdentifier.length > 0 && ![normalizedIdentifier isEqualToString:identifier]) {
        directTrack = self.tracksByID[normalizedIdentifier];
        if (directTrack != nil) {
            return directTrack;
        }
    }

    NSString *relativeKey = [self relativeTrackLookupKeyForIdentifier:identifier];
    if (relativeKey.length > 0) {
        SonoraTrack *relativeTrack = self.tracksByRelativeID[relativeKey];
        if (relativeTrack != nil) {
            return relativeTrack;
        }
    }

    NSString *fileNameKey = [self normalizedPathStringFromIdentifier:identifier].lastPathComponent.lowercaseString;
    if (fileNameKey.length > 0) {
        SonoraTrack *fileNameTrack = self.tracksByFileName[fileNameKey];
        if (fileNameTrack != nil) {
            return fileNameTrack;
        }
    }

    return nil;
}

- (BOOL)deleteTrackWithIdentifier:(NSString *)identifier error:(NSError * _Nullable __autoreleasing *)error {
    if (identifier.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Track identifier is empty."}];
        }
        return NO;
    }

    SonoraTrack *track = [self trackForIdentifier:identifier];
    NSURL *fileURL = track.url;
    if (fileURL == nil && track.identifier.length > 0) {
        fileURL = [NSURL fileURLWithPath:track.identifier];
    }
    if (fileURL == nil) {
        fileURL = [NSURL fileURLWithPath:[self normalizedPathStringFromIdentifier:identifier]];
    }

    if (![NSFileManager.defaultManager fileExistsAtPath:fileURL.path]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Track file does not exist."}];
        }
        return NO;
    }

    NSError *removeError = nil;
    BOOL removed = [NSFileManager.defaultManager removeItemAtURL:fileURL error:&removeError];
    if (!removed || removeError != nil) {
        if (error != NULL) {
            *error = removeError;
        }
        return NO;
    }

    [self reloadTracks];
    return YES;
}

- (nullable SonoraTrack *)trackFromURL:(NSURL *)fileURL embeddedArtworkOut:(UIImage * _Nullable __autoreleasing *)embeddedArtworkOut {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];

    NSString *fallbackTitle = fileURL.lastPathComponent.stringByDeletingPathExtension;
    NSString *title = [self metadataStringForCommonKey:AVMetadataCommonKeyTitle asset:asset];
    if (title.length == 0) {
        title = fallbackTitle;
    }

    NSString *artist = [self metadataStringForCommonKey:AVMetadataCommonKeyArtist asset:asset];

    NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
    if (!isfinite(duration) || duration < 0) {
        duration = 0;
    }

    UIImage *embeddedArtwork = [self artworkFromAsset:asset];
    if (embeddedArtworkOut != NULL) {
        *embeddedArtworkOut = embeddedArtwork;
    }

    UIImage *artwork = embeddedArtwork;
    if (artwork == nil) {
        artwork = SonoraPlaceholderArtwork(title, CGSizeMake(180, 180));
    }

    SonoraTrack *track = [[SonoraTrack alloc] init];
    track.identifier = fileURL.path;
    track.title = title;
    track.artist = artist ?: @"";
    track.fileName = fileURL.lastPathComponent;
    track.url = fileURL;
    track.duration = duration;
    track.artwork = artwork;

    return track;
}

- (NSString *)metadataStringForCommonKey:(AVMetadataKey)key asset:(AVAsset *)asset {
    NSArray<AVMetadataItem *> *items = [AVMetadataItem metadataItemsFromArray:asset.commonMetadata
                                                                       withKey:key
                                                                      keySpace:AVMetadataKeySpaceCommon];
    AVMetadataItem *item = items.firstObject;
    return item.stringValue ?: @"";
}

- (nullable UIImage *)artworkFromAsset:(AVAsset *)asset {
    for (AVMetadataItem *item in asset.commonMetadata) {
        if (![item.commonKey isEqualToString:AVMetadataCommonKeyArtwork]) {
            continue;
        }

        if ([item.value isKindOfClass:NSData.class]) {
            UIImage *image = [UIImage imageWithData:(NSData *)item.value];
            if (image != nil) {
                return image;
            }
        } else if ([item.value isKindOfClass:UIImage.class]) {
            return (UIImage *)item.value;
        }
    }

    return nil;
}

@end

#pragma mark - Playlists

@interface SonoraPlaylistStore ()

@property (nonatomic, copy) NSArray<SonoraPlaylist *> *cachedPlaylists;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *coverCache;

@end

@implementation SonoraPlaylistStore

+ (instancetype)sharedStore {
    static SonoraPlaylistStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SonoraPlaylistStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedPlaylists = @[];
        _coverCache = [[NSCache alloc] init];
        _coverCache.countLimit = 96;
        _coverCache.totalCostLimit = 64 * 1024 * 1024;
        [self reloadPlaylists];
    }
    return self;
}

- (NSArray<SonoraPlaylist *> *)playlists {
    return self.cachedPlaylists;
}

- (void)invalidateCoverCache {
    [self.coverCache removeAllObjects];
}

- (NSString *)coverCacheKeyForPlaylist:(SonoraPlaylist *)playlist size:(CGSize)size {
    if (playlist == nil) {
        return @"";
    }

    NSString *playlistID = playlist.playlistID ?: @"";
    NSString *customCover = playlist.customCoverFileName ?: @"";
    NSString *trackSignature = [playlist.trackIDs componentsJoinedByString:@"|"] ?: @"";
    NSString *base = [NSString stringWithFormat:@"%@|%@|%@", playlistID, customCover, trackSignature];
    NSString *hashPart = SonoraStableHashString(base);
    return [NSString stringWithFormat:@"%@|%ldx%ld", hashPart, (long)llround(size.width), (long)llround(size.height)];
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)playlistDictionariesFromArrayObject:(id)object {
    if (![object isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSArray *rawArray = (NSArray *)object;
    NSMutableArray<NSDictionary<NSString *, id> *> *dictionaries = [NSMutableArray arrayWithCapacity:rawArray.count];
    for (id item in rawArray) {
        if ([item isKindOfClass:NSDictionary.class]) {
            [dictionaries addObject:item];
        }
    }
    return [dictionaries copy];
}

- (NSArray<NSDictionary<NSString *, id> *> *)playlistDictionariesFromLegacyDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *legacyKey in SonoraLegacyPlaylistsDefaultsKeys()) {
        id legacyObject = [defaults objectForKey:legacyKey];
        NSArray<NSDictionary<NSString *, id> *> *legacyDictionaries = [self playlistDictionariesFromArrayObject:legacyObject];
        if (legacyDictionaries.count > 0) {
            [defaults setObject:legacyDictionaries forKey:kPlaylistsDefaultsKey];
            return legacyDictionaries;
        }
    }
    return @[];
}

- (nullable NSURL *)playlistsBackupFileURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *baseURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (baseURL == nil) {
        baseURL = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    }
    if (baseURL == nil) {
        return nil;
    }

    NSURL *directoryURL = [baseURL URLByAppendingPathComponent:@"Sonora" isDirectory:YES];
    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:directoryURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    if (directoryError != nil) {
        NSLog(@"Cannot create playlists backup directory: %@", directoryError.localizedDescription);
        return nil;
    }

    return [directoryURL URLByAppendingPathComponent:kPlaylistsBackupFileName];
}

- (NSArray<NSDictionary<NSString *, id> *> *)playlistDictionariesFromBackupFile {
    NSURL *backupURL = [self playlistsBackupFileURL];
    if (backupURL == nil || ![NSFileManager.defaultManager fileExistsAtPath:backupURL.path]) {
        return @[];
    }

    NSData *data = [NSData dataWithContentsOfURL:backupURL];
    if (data.length == 0) {
        return @[];
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError != nil) {
        NSLog(@"Playlists backup JSON parse error: %@", jsonError.localizedDescription);
        return @[];
    }

    return [self playlistDictionariesFromArrayObject:object] ?: @[];
}

- (void)writePlaylistsBackupWithDictionaries:(NSArray<NSDictionary<NSString *, id> *> *)dictionaries {
    NSURL *backupURL = [self playlistsBackupFileURL];
    if (backupURL == nil) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *payload = dictionaries ?: @[];
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError != nil || data.length == 0) {
        NSLog(@"Cannot encode playlists backup JSON: %@", jsonError.localizedDescription);
        return;
    }

    NSError *writeError = nil;
    [data writeToURL:backupURL options:NSDataWritingAtomic error:&writeError];
    if (writeError != nil) {
        NSLog(@"Cannot write playlists backup file: %@", writeError.localizedDescription);
    }
}

- (BOOL)repairTrackReferencesIfNeededForPlaylists:(NSArray<SonoraPlaylist *> *)playlists {
    if (playlists.count == 0) {
        return NO;
    }

    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    BOOL changed = NO;

    for (SonoraPlaylist *playlist in playlists) {
        if (playlist.trackIDs.count == 0) {
            continue;
        }

        NSMutableArray<NSString *> *resolvedTrackIDs = [NSMutableArray arrayWithCapacity:playlist.trackIDs.count];
        NSMutableSet<NSString *> *seenIDs = [NSMutableSet setWithCapacity:playlist.trackIDs.count];
        BOOL playlistChanged = NO;

        for (NSString *trackID in playlist.trackIDs) {
            if (![trackID isKindOfClass:NSString.class] || trackID.length == 0) {
                continue;
            }

            NSString *normalizedID = trackID;
            SonoraTrack *resolvedTrack = [library trackForIdentifier:trackID];
            if (resolvedTrack.identifier.length > 0) {
                normalizedID = resolvedTrack.identifier;
            }

            if (normalizedID.length == 0 || [seenIDs containsObject:normalizedID]) {
                playlistChanged = YES;
                continue;
            }

            [resolvedTrackIDs addObject:normalizedID];
            [seenIDs addObject:normalizedID];
            if (![normalizedID isEqualToString:trackID]) {
                playlistChanged = YES;
            }
        }

        if (playlistChanged && ![playlist.trackIDs isEqualToArray:resolvedTrackIDs]) {
            playlist.trackIDs = [resolvedTrackIDs copy];
            changed = YES;
        }
    }

    return changed;
}

- (void)reloadPlaylists {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id currentObject = [defaults objectForKey:kPlaylistsDefaultsKey];
    NSArray<NSDictionary<NSString *, id> *> * _Nullable storedDictionaries = [self playlistDictionariesFromArrayObject:currentObject];
    BOOL currentLooksCorrupt = ([currentObject isKindOfClass:NSArray.class] &&
                                ((NSArray *)currentObject).count > 0 &&
                                storedDictionaries.count == 0);

    if (currentObject == nil || storedDictionaries == nil || currentLooksCorrupt) {
        NSArray<NSDictionary<NSString *, id> *> *legacy = [self playlistDictionariesFromLegacyDefaults];
        if (legacy.count > 0) {
            storedDictionaries = legacy;
        } else {
            NSArray<NSDictionary<NSString *, id> *> *backup = [self playlistDictionariesFromBackupFile];
            if (backup.count > 0) {
                storedDictionaries = backup;
                [defaults setObject:backup forKey:kPlaylistsDefaultsKey];
            }
        }
    }

    if (storedDictionaries == nil) {
        storedDictionaries = @[];
    }

    NSMutableArray<SonoraPlaylist *> *loaded = [NSMutableArray arrayWithCapacity:storedDictionaries.count];
    for (NSDictionary<NSString *, id> *value in storedDictionaries) {
        SonoraPlaylist *playlist = [SonoraPlaylist playlistFromDictionary:value];
        if (playlist != nil) {
            [loaded addObject:playlist];
        }
    }

    BOOL repairedReferences = [self repairTrackReferencesIfNeededForPlaylists:loaded];
    self.cachedPlaylists = [loaded copy];
    [self invalidateCoverCache];
    if (repairedReferences) {
        [self persistPlaylists];
    } else if (storedDictionaries.count > 0 &&
               (currentObject == nil || ![currentObject isKindOfClass:NSArray.class] || currentLooksCorrupt)) {
        [self writePlaylistsBackupWithDictionaries:storedDictionaries];
    }
}

- (nullable SonoraPlaylist *)playlistWithID:(NSString *)playlistID {
    for (SonoraPlaylist *playlist in self.cachedPlaylists) {
        if ([playlist.playlistID isEqualToString:playlistID]) {
            return playlist;
        }
    }
    return nil;
}

- (nullable SonoraPlaylist *)addPlaylistWithName:(NSString *)name
                                    trackIDs:(NSArray<NSString *> *)trackIDs
                                  coverImage:(nullable UIImage *)coverImage {
    NSString *trimmedName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedName.length == 0) {
        return nil;
    }

    NSMutableArray<NSString *> *normalizedTrackIDs = [NSMutableArray arrayWithCapacity:trackIDs.count];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet setWithCapacity:trackIDs.count];

    for (NSString *trackID in trackIDs) {
        if (![trackID isKindOfClass:NSString.class] || trackID.length == 0 || [seenIDs containsObject:trackID]) {
            continue;
        }
        [normalizedTrackIDs addObject:trackID];
        [seenIDs addObject:trackID];
    }

    if (normalizedTrackIDs.count == 0) {
        return nil;
    }

    SonoraPlaylist *playlist = [[SonoraPlaylist alloc] init];
    playlist.playlistID = NSUUID.UUID.UUIDString;
    playlist.name = trimmedName;
    playlist.trackIDs = [normalizedTrackIDs copy];

    if (coverImage != nil) {
        NSString *coverFileName = [NSString stringWithFormat:@"%@.png", playlist.playlistID];
        NSURL *coverURL = [[self playlistCoversDirectoryURL] URLByAppendingPathComponent:coverFileName];
        NSData *coverData = SonoraEncodedCoverData(coverImage);
        if (coverData != nil && [coverData writeToURL:coverURL atomically:YES]) {
            playlist.customCoverFileName = coverFileName;
        }
    }

    NSMutableArray<SonoraPlaylist *> *updated = [self.cachedPlaylists mutableCopy];
    [updated addObject:playlist];
    self.cachedPlaylists = [updated copy];
    [self invalidateCoverCache];

    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];

    return playlist;
}

- (BOOL)renamePlaylistWithID:(NSString *)playlistID newName:(NSString *)newName {
    NSString *trimmedName = [newName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (playlistID.length == 0 || trimmedName.length == 0) {
        return NO;
    }

    SonoraPlaylist *playlist = [self playlistWithID:playlistID];
    if (playlist == nil) {
        return NO;
    }

    if ([playlist.name isEqualToString:trimmedName]) {
        return YES;
    }

    playlist.name = trimmedName;
    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)deletePlaylistWithID:(NSString *)playlistID {
    if (playlistID.length == 0 || self.cachedPlaylists.count == 0) {
        return NO;
    }

    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < self.cachedPlaylists.count; i += 1) {
        SonoraPlaylist *playlist = self.cachedPlaylists[i];
        if ([playlist.playlistID isEqualToString:playlistID]) {
            index = i;
            break;
        }
    }

    if (index == NSNotFound) {
        return NO;
    }

    SonoraPlaylist *playlist = self.cachedPlaylists[index];
    [self removeCustomCoverIfNeededForPlaylist:playlist];

    NSMutableArray<SonoraPlaylist *> *updated = [self.cachedPlaylists mutableCopy];
    [updated removeObjectAtIndex:index];
    self.cachedPlaylists = [updated copy];
    [self invalidateCoverCache];

    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)addTrackIDs:(NSArray<NSString *> *)trackIDs toPlaylistID:(NSString *)playlistID {
    if (playlistID.length == 0 || trackIDs.count == 0) {
        return NO;
    }

    SonoraPlaylist *playlist = [self playlistWithID:playlistID];
    if (playlist == nil) {
        return NO;
    }

    NSMutableArray<NSString *> *updatedTrackIDs = [playlist.trackIDs mutableCopy] ?: [NSMutableArray array];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet setWithArray:updatedTrackIDs];
    BOOL changed = NO;

    for (NSString *trackID in trackIDs) {
        if (![trackID isKindOfClass:NSString.class] || trackID.length == 0 || [seenIDs containsObject:trackID]) {
            continue;
        }

        [updatedTrackIDs addObject:trackID];
        [seenIDs addObject:trackID];
        changed = YES;
    }

    if (!changed) {
        return NO;
    }

    playlist.trackIDs = [updatedTrackIDs copy];
    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)replaceTrackIDs:(NSArray<NSString *> *)trackIDs forPlaylistID:(NSString *)playlistID {
    if (playlistID.length == 0) {
        return NO;
    }

    SonoraPlaylist *playlist = [self playlistWithID:playlistID];
    if (playlist == nil) {
        return NO;
    }

    NSMutableArray<NSString *> *normalizedTrackIDs = [NSMutableArray arrayWithCapacity:trackIDs.count];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet setWithCapacity:trackIDs.count];
    for (NSString *trackID in trackIDs) {
        if (![trackID isKindOfClass:NSString.class] || trackID.length == 0 || [seenIDs containsObject:trackID]) {
            continue;
        }
        [normalizedTrackIDs addObject:trackID];
        [seenIDs addObject:trackID];
    }

    NSArray<NSString *> *updatedIDs = [normalizedTrackIDs copy];
    if ([playlist.trackIDs isEqualToArray:updatedIDs]) {
        return YES;
    }

    playlist.trackIDs = updatedIDs;
    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)removeTrackID:(NSString *)trackID fromPlaylistID:(NSString *)playlistID {
    if (trackID.length == 0 || playlistID.length == 0) {
        return NO;
    }

    SonoraPlaylist *playlist = [self playlistWithID:playlistID];
    if (playlist == nil || playlist.trackIDs.count == 0) {
        return NO;
    }

    NSMutableArray<NSString *> *updated = [playlist.trackIDs mutableCopy];
    NSUInteger initialCount = updated.count;
    [updated removeObject:trackID];
    if (updated.count == initialCount) {
        return NO;
    }

    playlist.trackIDs = [updated copy];
    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)removeTrackIDFromAllPlaylists:(NSString *)trackID {
    if (trackID.length == 0 || self.cachedPlaylists.count == 0) {
        return NO;
    }

    BOOL changed = NO;
    for (SonoraPlaylist *playlist in self.cachedPlaylists) {
        if (playlist.trackIDs.count == 0) {
            continue;
        }

        NSMutableArray<NSString *> *updated = [playlist.trackIDs mutableCopy];
        NSUInteger initialCount = updated.count;
        [updated removeObject:trackID];
        if (updated.count != initialCount) {
            playlist.trackIDs = [updated copy];
            changed = YES;
        }
    }

    if (!changed) {
        return NO;
    }

    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)setCustomCoverImage:(nullable UIImage *)coverImage forPlaylistID:(NSString *)playlistID {
    if (playlistID.length == 0) {
        return NO;
    }

    SonoraPlaylist *playlist = [self playlistWithID:playlistID];
    if (playlist == nil) {
        return NO;
    }

    if (coverImage == nil) {
        if (playlist.customCoverFileName.length == 0) {
            return YES;
        }

        [self removeCustomCoverIfNeededForPlaylist:playlist];
        playlist.customCoverFileName = nil;
        [self invalidateCoverCache];
        [self persistPlaylists];
        [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
        return YES;
    }

    NSString *coverFileName = [NSString stringWithFormat:@"%@.png", playlist.playlistID];
    NSURL *coverURL = [[self playlistCoversDirectoryURL] URLByAppendingPathComponent:coverFileName];
    NSData *coverData = SonoraEncodedCoverData(coverImage);
    if (coverData == nil || ![coverData writeToURL:coverURL atomically:YES]) {
        return NO;
    }

    playlist.customCoverFileName = coverFileName;
    [self invalidateCoverCache];
    [self persistPlaylists];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    return YES;
}

- (NSArray<SonoraTrack *> *)tracksForPlaylist:(SonoraPlaylist *)playlist library:(SonoraLibraryManager *)library {
    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:playlist.trackIDs.count];
    for (NSString *trackID in playlist.trackIDs) {
        SonoraTrack *track = [library trackForIdentifier:trackID];
        if (track != nil) {
            [tracks addObject:track];
        }
    }
    return [tracks copy];
}

- (UIImage *)coverForPlaylist:(SonoraPlaylist *)playlist
                      library:(SonoraLibraryManager *)library
                         size:(CGSize)size {
    NSString *cacheKey = [self coverCacheKeyForPlaylist:playlist size:size];
    if (cacheKey.length > 0) {
        UIImage *cachedCover = [self.coverCache objectForKey:cacheKey];
        if (cachedCover != nil) {
            return cachedCover;
        }
    }

    UIImage *customCover = [self customCoverForPlaylist:playlist];
    if (customCover != nil) {
        if (cacheKey.length > 0) {
            [self.coverCache setObject:customCover forKey:cacheKey];
        }
        return customCover;
    }

    NSArray<SonoraTrack *> *playlistTracks = [self tracksForPlaylist:playlist library:library];
    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger index = 0; index < MIN(playlistTracks.count, 4); index += 1) {
        [images addObject:playlistTracks[index].artwork ?: SonoraPlaceholderArtwork(playlistTracks[index].title, size)];
    }

    if (images.count == 0) {
        UIImage *placeholder = SonoraPlaceholderArtwork(playlist.name, size);
        if (cacheKey.length > 0 && placeholder != nil) {
            [self.coverCache setObject:placeholder forKey:cacheKey];
        }
        return placeholder;
    }

    UIImage *cover = SonoraCollageCover(images, size);
    if (cacheKey.length > 0 && cover != nil) {
        [self.coverCache setObject:cover forKey:cacheKey];
    }
    return cover;
}

- (void)persistPlaylists {
    NSMutableArray<NSDictionary<NSString *, id> *> *data = [NSMutableArray arrayWithCapacity:self.cachedPlaylists.count];
    for (SonoraPlaylist *playlist in self.cachedPlaylists) {
        [data addObject:[playlist dictionaryRepresentation]];
    }
    [NSUserDefaults.standardUserDefaults setObject:data forKey:kPlaylistsDefaultsKey];
    [self writePlaylistsBackupWithDictionaries:data];
}

- (NSURL *)playlistCoversDirectoryURL {
    NSURL *documentsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directoryURL = [documentsURL URLByAppendingPathComponent:kPlaylistCoverFolderName isDirectory:YES];

    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&error];
    if (error != nil) {
        NSLog(@"Cannot create playlist cover directory: %@", error.localizedDescription);
    }

    return directoryURL;
}

- (nullable UIImage *)customCoverForPlaylist:(SonoraPlaylist *)playlist {
    if (playlist.customCoverFileName.length == 0) {
        return nil;
    }

    NSURL *coverURL = [[self playlistCoversDirectoryURL] URLByAppendingPathComponent:playlist.customCoverFileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:coverURL.path]) {
        return nil;
    }

    return [UIImage imageWithContentsOfFile:coverURL.path];
}

- (void)removeCustomCoverIfNeededForPlaylist:(SonoraPlaylist *)playlist {
    if (playlist.customCoverFileName.length == 0) {
        return;
    }

    NSURL *coverURL = [[self playlistCoversDirectoryURL] URLByAppendingPathComponent:playlist.customCoverFileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:coverURL.path]) {
        return;
    }

    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtURL:coverURL error:&error];
    if (error != nil) {
        NSLog(@"Cannot remove cover file: %@", error.localizedDescription);
    }
}

@end

#pragma mark - Playback

@interface SonoraPlaybackManager () <AVAudioPlayerDelegate>

@property (nonatomic, strong, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong, nullable) AVPlayer *streamingPlayer;
@property (nonatomic, strong, nullable) id streamTimeObserver;
@property (nonatomic, strong, nullable) id streamEndObserver;
@property (nonatomic, strong, nullable) id streamFailedObserver;
@property (nonatomic, copy) NSArray<SonoraTrack *> *queue;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong, nullable) NSTimer *progressTimer;
@property (nonatomic, strong, nullable) NSTimer *diagnosticsTimer;
@property (nonatomic, assign) SonoraRepeatMode repeatMode;
@property (nonatomic, assign, getter=isShuffleEnabled) BOOL shuffleEnabled;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *shuffleBag;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *shuffleHistory;
@property (nonatomic, copy) NSString *analyticsTrackID;
@property (nonatomic, assign) NSTimeInterval analyticsTrackDuration;
@property (nonatomic, assign) NSTimeInterval analyticsMaxProgressTime;
@property (nonatomic, assign) BOOL analyticsDidSeekNearEnd;
@property (nonatomic, assign) NSUInteger automaticAdvanceRequestToken;
@property (nonatomic, assign) float currentMeterLevel;
@property (nonatomic, copy) NSString *pendingRestoredTrackID;
@property (nonatomic, assign) NSTimeInterval pendingRestoredTime;
@property (nonatomic, assign) BOOL placeholderPlaybackActive;
@property (nonatomic, assign) BOOL streamSeekInFlight;
@property (nonatomic, assign) NSTimeInterval streamSeekTargetTime;
@property (nonatomic, assign) NSTimeInterval streamSeekStartedAt;

@end

@implementation SonoraPlaybackManager

+ (instancetype)sharedManager {
    static SonoraPlaybackManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SonoraPlaybackManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = @[];
        _currentIndex = NSNotFound;
        _repeatMode = SonoraRepeatModeNone;
        _shuffleEnabled = NO;
        _shuffleBag = [NSMutableArray array];
        _shuffleHistory = [NSMutableArray array];
        _analyticsTrackID = @"";
        _analyticsTrackDuration = 0.0;
        _analyticsMaxProgressTime = 0.0;
        _analyticsDidSeekNearEnd = NO;
        _automaticAdvanceRequestToken = 0;
        _currentMeterLevel = 0.0f;
        _pendingRestoredTrackID = @"";
        _pendingRestoredTime = 0.0;
        _placeholderPlaybackActive = NO;
        _streamSeekInFlight = NO;
        _streamSeekTargetTime = 0.0;
        [self restorePlaybackSessionFromDefaults];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(handleApplicationLifecyclePersist:)
                                                   name:UIApplicationDidEnterBackgroundNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(handleApplicationLifecyclePersist:)
                                                   name:UIApplicationWillTerminateNotification
                                                 object:nil];
        [self configureRemoteCommands];
        [self updateRemoteCommandAvailability];
        [self startDiagnosticsMonitorIfNeeded];
        SonoraDiagnosticsLog(@"diag", [NSString stringWithFormat:@"log_file=%@", SonoraDiagnosticsLogFilePath()]);
    }
    return self;
}

- (void)startDiagnosticsMonitorIfNeeded {
    if (self.diagnosticsTimer != nil) {
        return;
    }

    NSTimer *timer = [NSTimer timerWithTimeInterval:30.0
                                             target:self
                                           selector:@selector(handleDiagnosticsTimerTick)
                                           userInfo:nil
                                            repeats:YES];
    self.diagnosticsTimer = timer;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    [self handleDiagnosticsTimerTick];
}

- (void)handleDiagnosticsTimerTick {
    uint64_t footprint = SonoraProcessPhysicalFootprintBytes();
    double memoryMB = ((double)footprint) / (1024.0 * 1024.0);
    double cpuPercent = SonoraProcessCPUUsagePercent();
    NSString *mode = @"idle";
    if (self.audioPlayer != nil) {
        mode = @"audio";
    } else if (self.streamingPlayer != nil) {
        mode = @"stream";
    } else if (self.placeholderPlaybackActive) {
        mode = @"placeholder";
    }

    NSString *trackID = self.currentTrack.identifier ?: @"";
    SonoraDiagnosticsLog(@"runtime", [NSString stringWithFormat:@"memory_mb=%.1f cpu_pct=%.2f mode=%@ playing=%d queue=%lu current_track=%@",
                                      memoryMB,
                                      cpuPercent,
                                      mode,
                                      self.isPlaying,
                                      (unsigned long)self.queue.count,
                                      trackID]);
}

- (nullable SonoraTrack *)currentTrack {
    if (self.currentIndex == NSNotFound || self.currentIndex >= self.queue.count) {
        return nil;
    }
    return self.queue[self.currentIndex];
}

- (BOOL)isStreamingTrack:(SonoraTrack *)track {
    if (track == nil || track.url == nil) {
        return NO;
    }
    return !track.url.isFileURL;
}

- (NSTimeInterval)streamingCurrentTime {
    if (self.streamingPlayer == nil) {
        return 0.0;
    }
    NSTimeInterval value = CMTimeGetSeconds(self.streamingPlayer.currentTime);
    if (!isfinite(value) || value < 0.0) {
        return 0.0;
    }
    return value;
}

- (NSTimeInterval)streamingDuration {
    if (self.streamingPlayer == nil || self.streamingPlayer.currentItem == nil) {
        return 0.0;
    }
    NSTimeInterval value = CMTimeGetSeconds(self.streamingPlayer.currentItem.duration);
    if (!isfinite(value) || value <= 0.0) {
        NSArray<NSValue *> *seekableRanges = self.streamingPlayer.currentItem.seekableTimeRanges;
        if (seekableRanges.count > 0) {
            CMTimeRange range = seekableRanges.lastObject.CMTimeRangeValue;
            NSTimeInterval seekableEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
            if (isfinite(seekableEnd) && seekableEnd > 0.0) {
                value = seekableEnd;
            }
        }
    }
    if (!isfinite(value) || value < 0.0) {
        return 0.0;
    }
    return value;
}

- (void)removeStreamingPlayerObservers {
    if (self.streamTimeObserver != nil) {
        [self.streamingPlayer removeTimeObserver:self.streamTimeObserver];
        self.streamTimeObserver = nil;
    }
    if (self.streamEndObserver != nil) {
        [NSNotificationCenter.defaultCenter removeObserver:self.streamEndObserver];
        self.streamEndObserver = nil;
    }
    if (self.streamFailedObserver != nil) {
        [NSNotificationCenter.defaultCenter removeObserver:self.streamFailedObserver];
        self.streamFailedObserver = nil;
    }
}

- (void)stopStreamingPlayer {
    [self removeStreamingPlayerObservers];
    [self.streamingPlayer pause];
    self.streamingPlayer = nil;
    self.streamSeekInFlight = NO;
    self.streamSeekTargetTime = 0.0;
    self.streamSeekStartedAt = 0.0;
    self.streamSeekStartedAt = 0.0;
}

- (void)stopCurrentPlayers {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
    [self stopStreamingPlayer];
}

- (BOOL)isPlaying {
    if (self.audioPlayer != nil) {
        return self.audioPlayer.isPlaying;
    }
    if (self.streamingPlayer != nil) {
        return self.streamingPlayer.rate > 0.0;
    }
    return self.placeholderPlaybackActive && [self isPlaceholderTrack:self.currentTrack];
}

- (NSTimeInterval)currentTime {
    if (self.audioPlayer != nil) {
        return self.audioPlayer.currentTime;
    }
    if (self.streamingPlayer != nil) {
        if (self.streamSeekInFlight) {
            NSTimeInterval liveTime = [self streamingCurrentTime];
            NSTimeInterval targetTime = MAX(0.0, self.streamSeekTargetTime);
            NSTimeInterval distance = fabs(liveTime - targetTime);
            NSTimeInterval elapsed = 0.0;
            if (self.streamSeekStartedAt > 0.0) {
                elapsed = [[NSDate date] timeIntervalSince1970] - self.streamSeekStartedAt;
            }
            BOOL reachedTarget = isfinite(distance) && distance <= 1.2;
            BOOL seekTimedOut = elapsed >= 15.0;
            if (reachedTarget || seekTimedOut) {
                self.streamSeekInFlight = NO;
                self.streamSeekTargetTime = 0.0;
                self.streamSeekStartedAt = 0.0;
                return liveTime;
            }
            return targetTime;
        }
        return [self streamingCurrentTime];
    }
    if (self.currentTrack != nil) {
        return MAX(0.0, self.pendingRestoredTime);
    }
    return 0.0;
}

- (NSTimeInterval)duration {
    if (self.audioPlayer != nil) {
        return self.audioPlayer.duration;
    }
    if (self.streamingPlayer != nil) {
        NSTimeInterval streamingDuration = [self streamingDuration];
        if (isfinite(streamingDuration) && streamingDuration > 0.0) {
            return streamingDuration;
        }
    }
    SonoraTrack *track = self.currentTrack;
    return track != nil ? track.duration : 0.0;
}

- (NSArray<SonoraTrack *> *)currentQueue {
    return self.queue;
}

- (BOOL)isPlaceholderTrack:(SonoraTrack *)track {
    if (track == nil) {
        return NO;
    }
    NSString *identifier = track.identifier ?: @"";
    if (identifier.length == 0 || ![identifier hasPrefix:kMiniStreamingPlaceholderPrefix]) {
        return NO;
    }
    if (track.url == nil || !track.url.isFileURL) {
        return NO;
    }
    NSString *trackPath = track.url.path ?: @"";
    return trackPath.length == 0 || [trackPath isEqualToString:@"/dev/null"];
}

- (void)invalidatePendingAutomaticAdvance {
    self.automaticAdvanceRequestToken += 1;
}

- (NSTimeInterval)configuredTrackGapSeconds {
    NSTimeInterval value = SonoraSettingsTrackGapSeconds();
    if (!isfinite(value)) {
        return 0.0;
    }
    return MIN(MAX(value, 0.0), 8.0);
}

- (void)restorePlaybackSessionFromDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL preserveModes = SonoraShouldPreservePlayerModes(defaults);
    if (preserveModes) {
        _shuffleEnabled = [defaults boolForKey:kPlayerSettingsSavedShuffleKey];
        NSInteger savedRepeat = [defaults integerForKey:kPlayerSettingsSavedRepeatModeKey];
        if (savedRepeat < SonoraRepeatModeNone || savedRepeat > SonoraRepeatModeTrack) {
            savedRepeat = SonoraRepeatModeNone;
        }
        _repeatMode = (SonoraRepeatMode)savedRepeat;
    } else {
        _shuffleEnabled = NO;
        _repeatMode = SonoraRepeatModeNone;
    }

    NSArray<NSString *> *savedQueueTrackIDs = [defaults arrayForKey:kPlaybackSessionQueueTrackIDsKey];
    if (![savedQueueTrackIDs isKindOfClass:NSArray.class] || savedQueueTrackIDs.count == 0) {
        return;
    }

    NSMutableArray<SonoraTrack *> *resolvedQueue = [NSMutableArray arrayWithCapacity:savedQueueTrackIDs.count];
    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    for (id rawID in savedQueueTrackIDs) {
        if (![rawID isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *trackID = (NSString *)rawID;
        if (trackID.length == 0) {
            continue;
        }
        SonoraTrack *track = [library trackForIdentifier:trackID];
        if (track != nil) {
            [resolvedQueue addObject:track];
        }
    }
    if (resolvedQueue.count == 0) {
        return;
    }

    _queue = [resolvedQueue copy];
    _currentIndex = 0;
    NSString *savedCurrentTrackID = [defaults stringForKey:kPlaybackSessionCurrentTrackIDKey];
    if (savedCurrentTrackID.length > 0) {
        NSUInteger foundIndex = [resolvedQueue indexOfObjectPassingTest:^BOOL(SonoraTrack * _Nonnull obj, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            return [obj.identifier isEqualToString:savedCurrentTrackID];
        }];
        if (foundIndex != NSNotFound) {
            _currentIndex = (NSInteger)foundIndex;
        }
    }

    NSTimeInterval restoredTime = [defaults doubleForKey:kPlaybackSessionCurrentTimeKey];
    if (!isfinite(restoredTime) || restoredTime < 0.0) {
        restoredTime = 0.0;
    }
    NSString *fallbackTrackID = self.currentTrack.identifier ?: @"";
    _pendingRestoredTrackID = (savedCurrentTrackID.length > 0) ? savedCurrentTrackID : fallbackTrackID;
    _pendingRestoredTime = restoredTime;

    [self rebuildShuffleBagIfNeeded];

    // Always restore session in paused state, even if it was playing before app termination.
}

- (void)persistPlaybackSessionToDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL preserveModes = SonoraShouldPreservePlayerModes(defaults);
    [defaults setBool:(preserveModes ? self.isShuffleEnabled : NO) forKey:kPlayerSettingsSavedShuffleKey];
    [defaults setInteger:(preserveModes ? self.repeatMode : SonoraRepeatModeNone) forKey:kPlayerSettingsSavedRepeatModeKey];

    if (self.queue.count == 0 || self.currentTrack == nil) {
        [defaults removeObjectForKey:kPlaybackSessionQueueTrackIDsKey];
        [defaults removeObjectForKey:kPlaybackSessionCurrentTrackIDKey];
        [defaults removeObjectForKey:kPlaybackSessionCurrentTimeKey];
        [defaults removeObjectForKey:kPlaybackSessionWasPlayingKey];
        return;
    }

    NSMutableArray<NSString *> *queueTrackIDs = [NSMutableArray arrayWithCapacity:self.queue.count];
    for (SonoraTrack *track in self.queue) {
        if (track.identifier.length > 0) {
            [queueTrackIDs addObject:track.identifier];
        }
    }
    if (queueTrackIDs.count == 0 || self.currentTrack.identifier.length == 0) {
        [defaults removeObjectForKey:kPlaybackSessionQueueTrackIDsKey];
        [defaults removeObjectForKey:kPlaybackSessionCurrentTrackIDKey];
        [defaults removeObjectForKey:kPlaybackSessionCurrentTimeKey];
        [defaults removeObjectForKey:kPlaybackSessionWasPlayingKey];
        return;
    }

    NSTimeInterval currentTime = self.currentTime;
    if (!isfinite(currentTime) || currentTime < 0.0) {
        currentTime = 0.0;
    }

    [defaults setObject:[queueTrackIDs copy] forKey:kPlaybackSessionQueueTrackIDsKey];
    [defaults setObject:self.currentTrack.identifier forKey:kPlaybackSessionCurrentTrackIDKey];
    [defaults setDouble:currentTime forKey:kPlaybackSessionCurrentTimeKey];
    [defaults setBool:self.isPlaying forKey:kPlaybackSessionWasPlayingKey];
}

- (void)resetAnalyticsSession {
    self.analyticsTrackID = @"";
    self.analyticsTrackDuration = 0.0;
    self.analyticsMaxProgressTime = 0.0;
    self.analyticsDidSeekNearEnd = NO;
}

- (void)beginAnalyticsSessionForCurrentTrack {
    SonoraTrack *track = self.currentTrack;
    if (track.identifier.length == 0) {
        [self resetAnalyticsSession];
        return;
    }

    self.analyticsTrackID = track.identifier;
    NSTimeInterval duration = self.duration;
    if (!isfinite(duration) || duration <= 0.0) {
        duration = track.duration;
    }
    self.analyticsTrackDuration = MAX(0.0, duration);
    self.analyticsMaxProgressTime = MAX(0.0, self.currentTime);
    self.analyticsDidSeekNearEnd = NO;
}

- (void)updateAnalyticsProgressSnapshot {
    if (self.analyticsTrackID.length == 0) {
        return;
    }

    NSTimeInterval currentTime = self.currentTime;
    if (isfinite(currentTime) && currentTime > self.analyticsMaxProgressTime) {
        self.analyticsMaxProgressTime = currentTime;
    }
}

- (void)markSeekForAnalyticsToTime:(NSTimeInterval)targetTime {
    if (self.analyticsTrackID.length == 0) {
        return;
    }

    NSTimeInterval duration = self.analyticsTrackDuration;
    if (!isfinite(duration) || duration <= 0.0) {
        duration = self.duration;
    }
    if (!isfinite(duration) || duration <= 0.0) {
        return;
    }

    double currentRatio = self.analyticsMaxProgressTime / duration;
    double targetRatio = targetTime / duration;
    if (targetRatio >= 0.92 && currentRatio < 0.80) {
        self.analyticsDidSeekNearEnd = YES;
    }
}

- (void)finalizeAnalyticsForCurrentTrackFinished:(BOOL)finishedNaturally
                                 countSkipIfEarly:(BOOL)countSkipIfEarly {
    if (self.analyticsTrackID.length == 0) {
        return;
    }

    [self updateAnalyticsProgressSnapshot];

    NSTimeInterval duration = self.analyticsTrackDuration;
    if (!isfinite(duration) || duration <= 0.0) {
        duration = self.duration;
    }
    if (!isfinite(duration) || duration <= 0.0) {
        [self resetAnalyticsSession];
        return;
    }

    double listenedRatio = MAX(0.0, MIN(self.analyticsMaxProgressTime / duration, 1.0));
    BOOL shouldCountPlay = (!self.analyticsDidSeekNearEnd) && (finishedNaturally || listenedRatio >= 0.80);
    BOOL shouldCountSkip = countSkipIfEarly && (listenedRatio < 0.20);

    if (shouldCountPlay) {
        [SonoraTrackAnalyticsStore.sharedStore recordPlayForTrackID:self.analyticsTrackID];
    }
    if (shouldCountSkip) {
        [SonoraTrackAnalyticsStore.sharedStore recordSkipForTrackID:self.analyticsTrackID];
    }

    [self resetAnalyticsSession];
}

- (void)playTrack:(SonoraTrack *)track {
    if (track == nil) {
        return;
    }
    [self playTracks:@[track] startIndex:0];
}

- (void)playTracks:(NSArray<SonoraTrack *> *)tracks startIndex:(NSInteger)index {
    if (tracks.count == 0) {
        return;
    }

    [self invalidatePendingAutomaticAdvance];

    NSInteger normalizedIndex = index;
    if (normalizedIndex < 0 || normalizedIndex >= tracks.count) {
        normalizedIndex = 0;
    }

    [self resetAnalyticsSession];
    self.queue = [tracks copy];
    self.currentIndex = normalizedIndex;
    self.placeholderPlaybackActive = NO;

    [self.shuffleBag removeAllObjects];
    [self.shuffleHistory removeAllObjects];
    [self rebuildShuffleBagIfNeeded];
    [self updateRemoteCommandAvailability];

    [self startCurrentTrack];
}

- (void)togglePlayPause {
    if (self.queue.count == 0) {
        return;
    }

    [self invalidatePendingAutomaticAdvance];

    if (self.audioPlayer == nil && self.streamingPlayer == nil) {
        if ([self isPlaceholderTrack:self.currentTrack]) {
            self.placeholderPlaybackActive = !self.placeholderPlaybackActive;
            [self updateNowPlayingInfo];
            [self postStateDidChange];
            [self postProgressDidChange];
            return;
        }
        if (self.currentIndex == NSNotFound) {
            self.currentIndex = 0;
        }
        [self startCurrentTrack];
        return;
    }

    if (self.audioPlayer != nil && self.audioPlayer.isPlaying) {
        [self.audioPlayer pause];
        [self.progressTimer invalidate];
        self.progressTimer = nil;
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
    } else if (self.streamingPlayer != nil && self.streamingPlayer.rate > 0.0f) {
        [self.streamingPlayer pause];
        [self.progressTimer invalidate];
        self.progressTimer = nil;
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
    } else {
        if (self.audioPlayer != nil) {
            [self.audioPlayer play];
        } else if (self.streamingPlayer != nil) {
            [self.streamingPlayer play];
        }
        [self startProgressTimerIfNeeded];
    }

    [self updateNowPlayingInfo];
    [self postStateDidChange];
    [self postProgressDidChange];
}

- (void)playNext {
    [self invalidatePendingAutomaticAdvance];
    [self advanceToNextTrackAutomatically:NO];
}

- (void)playPrevious {
    if (self.queue.count == 0) {
        return;
    }

    [self invalidatePendingAutomaticAdvance];

    if ((self.audioPlayer != nil || self.streamingPlayer != nil) &&
        self.currentTime > 3.0) {
        [self seekToTime:0.0];
        return;
    }

    if (self.isShuffleEnabled) {
        if (self.shuffleHistory.count > 0) {
            NSInteger previousIndex = self.shuffleHistory.lastObject.integerValue;
            [self.shuffleHistory removeLastObject];
            [self finalizeAnalyticsForCurrentTrackFinished:NO countSkipIfEarly:YES];
            self.currentIndex = previousIndex;
            [self startCurrentTrack];
            return;
        }

        NSInteger randomIndex = [self randomIndexExcluding:self.currentIndex];
        if (randomIndex != NSNotFound) {
            [self finalizeAnalyticsForCurrentTrackFinished:NO countSkipIfEarly:YES];
            self.currentIndex = randomIndex;
            [self rebuildShuffleBagIfNeeded];
            [self startCurrentTrack];
            return;
        }

        [self restartCurrentTrack];
        return;
    }

    if (self.currentIndex == NSNotFound) {
        self.currentIndex = 0;
        [self startCurrentTrack];
        return;
    }

    NSInteger previous = self.currentIndex - 1;
    if (previous < 0) {
        if (self.repeatMode == SonoraRepeatModeQueue) {
            previous = self.queue.count - 1;
        } else {
            [self restartCurrentTrack];
            return;
        }
    }

    [self finalizeAnalyticsForCurrentTrackFinished:NO countSkipIfEarly:YES];
    self.currentIndex = previous;
    [self startCurrentTrack];
}

- (void)seekToTime:(NSTimeInterval)time {
    SonoraTrack *track = self.currentTrack;
    if (track == nil) {
        return;
    }

    NSTimeInterval duration = self.duration;
    NSTimeInterval clamped = MAX(0.0, time);
    if (isfinite(duration) && duration > 0.0) {
        clamped = MIN(clamped, duration);
    }
    self.pendingRestoredTrackID = track.identifier ?: @"";
    self.pendingRestoredTime = clamped;

    if (self.audioPlayer == nil && self.streamingPlayer == nil) {
        [self updateNowPlayingInfo];
        [self postProgressDidChange];
        return;
    }

    [self updateAnalyticsProgressSnapshot];
    [self markSeekForAnalyticsToTime:clamped];
    if (self.audioPlayer != nil) {
        self.audioPlayer.currentTime = clamped;
    } else {
        AVPlayerItem *currentItem = self.streamingPlayer.currentItem;
        if (currentItem != nil) {
            self.streamSeekInFlight = YES;
            self.streamSeekTargetTime = clamped;
            self.streamSeekStartedAt = [[NSDate date] timeIntervalSince1970];
            __weak typeof(self) weakSelf = self;
            [currentItem seekToTime:CMTimeMakeWithSeconds(clamped, NSEC_PER_SEC)
                  completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf == nil || !strongSelf.streamSeekInFlight) {
                        return;
                    }
                    if (!finished) {
                        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_seek_failed track=%@ target=%.2f",
                                                           strongSelf.currentTrack.identifier ?: @"",
                                                           clamped]);
                    }
                    [strongSelf updateNowPlayingInfo];
                    [strongSelf postProgressDidChange];
                });
            }];
        }
    }
    [self updateNowPlayingInfo];
    [self postProgressDidChange];
}

- (void)setShuffleEnabled:(BOOL)enabled {
    if (_shuffleEnabled == enabled) {
        return;
    }

    _shuffleEnabled = enabled;
    [self.shuffleHistory removeAllObjects];
    [self rebuildShuffleBagIfNeeded];
    [self persistPlaybackSessionToDefaults];
    [self updateRemoteCommandAvailability];
    [self postStateDidChange];
}

- (void)toggleShuffleEnabled {
    [self setShuffleEnabled:!self.isShuffleEnabled];
}

- (SonoraRepeatMode)cycleRepeatMode {
    switch (self.repeatMode) {
        case SonoraRepeatModeNone:
            self.repeatMode = SonoraRepeatModeQueue;
            break;
        case SonoraRepeatModeQueue:
            self.repeatMode = SonoraRepeatModeTrack;
            break;
        case SonoraRepeatModeTrack:
            self.repeatMode = SonoraRepeatModeNone;
            break;
    }

    [self persistPlaybackSessionToDefaults];
    [self updateRemoteCommandAvailability];
    [self postStateDidChange];
    return self.repeatMode;
}

- (nullable SonoraTrack *)predictedNextTrackForSkip {
    if (self.queue.count == 0) {
        return nil;
    }

    if (self.isShuffleEnabled) {
        if (self.queue.count == 1) {
            return self.queue.firstObject;
        }

        if (self.shuffleBag.count == 0) {
            if (self.repeatMode == SonoraRepeatModeNone) {
                return nil;
            }
            [self rebuildShuffleBagIfNeeded];
        }

        if (self.shuffleBag.count == 0) {
            return nil;
        }

        NSInteger nextIndex = self.shuffleBag.firstObject.integerValue;
        if (nextIndex < 0 || nextIndex >= self.queue.count) {
            return nil;
        }
        return self.queue[nextIndex];
    }

    NSInteger nextIndex = (self.currentIndex == NSNotFound) ? 0 : self.currentIndex + 1;
    if (nextIndex >= self.queue.count) {
        if (self.repeatMode == SonoraRepeatModeQueue) {
            nextIndex = 0;
        } else {
            return nil;
        }
    }

    return self.queue[nextIndex];
}

- (void)advanceToNextTrackAutomatically:(BOOL)automatic {
    if (self.queue.count == 0) {
        return;
    }

    if (automatic && self.repeatMode == SonoraRepeatModeTrack) {
        [self finalizeAnalyticsForCurrentTrackFinished:YES countSkipIfEarly:NO];
        [self restartCurrentTrack];
        return;
    }

    NSInteger previousIndex = self.currentIndex;
    NSInteger nextIndex = [self nextIndexForAdvanceAutomatic:automatic];

    if (nextIndex == NSNotFound) {
        if (automatic) {
            [self finalizeAnalyticsForCurrentTrackFinished:YES countSkipIfEarly:NO];
            [self stopPlaybackAtQueueEnd];
        }
        return;
    }

    if (self.isShuffleEnabled && previousIndex != NSNotFound && previousIndex != nextIndex) {
        [self.shuffleHistory addObject:@(previousIndex)];
    }

    [self finalizeAnalyticsForCurrentTrackFinished:automatic countSkipIfEarly:!automatic];
    self.currentIndex = nextIndex;
    [self startCurrentTrack];
}

- (NSInteger)nextIndexForAdvanceAutomatic:(BOOL)automatic {
    if (self.queue.count == 0) {
        return NSNotFound;
    }

    if (self.isShuffleEnabled) {
        if (self.queue.count == 1) {
            if (automatic && self.repeatMode == SonoraRepeatModeNone) {
                return NSNotFound;
            }
            return 0;
        }

        if (self.shuffleBag.count == 0) {
            if (self.repeatMode == SonoraRepeatModeNone) {
                return NSNotFound;
            }
            [self rebuildShuffleBagIfNeeded];
        }

        if (self.shuffleBag.count == 0) {
            return NSNotFound;
        }

        NSInteger next = self.shuffleBag.firstObject.integerValue;
        [self.shuffleBag removeObjectAtIndex:0];
        return next;
    }

    NSInteger next = (self.currentIndex == NSNotFound) ? 0 : self.currentIndex + 1;
    if (next < self.queue.count) {
        return next;
    }

    if (self.repeatMode == SonoraRepeatModeQueue) {
        return 0;
    }

    return NSNotFound;
}

- (void)restartCurrentTrack {
    if (self.queue.count == 0) {
        return;
    }

    [self invalidatePendingAutomaticAdvance];

    if (self.currentIndex == NSNotFound) {
        self.currentIndex = 0;
    }

    if (self.audioPlayer != nil) {
        self.audioPlayer.currentTime = 0.0;
        [self.audioPlayer play];
        [self startProgressTimerIfNeeded];
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
        return;
    }
    if (self.streamingPlayer != nil) {
        [self.streamingPlayer seekToTime:kCMTimeZero];
        [self.streamingPlayer play];
        [self startProgressTimerIfNeeded];
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
        return;
    }

    [self startCurrentTrack];
}

- (void)stopPlaybackAtQueueEnd {
    [self invalidatePendingAutomaticAdvance];
    [self.progressTimer invalidate];
    self.progressTimer = nil;

    [self stopCurrentPlayers];
    self.placeholderPlaybackActive = NO;
    self.currentMeterLevel = 0.0f;
    [self postMeterDidChangeWithLevel:0.0f];
    [self resetAnalyticsSession];

    [self updateRemoteCommandAvailability];
    [self updateNowPlayingInfo];
    [self postStateDidChange];
    [self postProgressDidChange];
}

- (void)rebuildShuffleBagIfNeeded {
    [self.shuffleBag removeAllObjects];

    if (!self.isShuffleEnabled || self.queue.count <= 1) {
        return;
    }

    for (NSInteger index = 0; index < self.queue.count; index += 1) {
        if (index != self.currentIndex) {
            [self.shuffleBag addObject:@(index)];
        }
    }

    for (NSInteger i = self.shuffleBag.count - 1; i > 0; i -= 1) {
        u_int32_t j = arc4random_uniform((u_int32_t)(i + 1));
        [self.shuffleBag exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

- (NSInteger)randomIndexExcluding:(NSInteger)excludedIndex {
    if (self.queue.count == 0) {
        return NSNotFound;
    }

    if (self.queue.count == 1) {
        return 0;
    }

    NSInteger randomIndex = excludedIndex;
    NSInteger guard = 0;
    while (randomIndex == excludedIndex && guard < 16) {
        randomIndex = (NSInteger)arc4random_uniform((u_int32_t)self.queue.count);
        guard += 1;
    }

    return randomIndex;
}

- (void)startCurrentTrack {
    [self invalidatePendingAutomaticAdvance];
    self.streamSeekInFlight = NO;
    self.streamSeekTargetTime = 0.0;

    if (self.currentIndex == NSNotFound && self.queue.count > 0) {
        self.currentIndex = 0;
    }

    SonoraTrack *track = self.currentTrack;
    if (track == nil) {
        self.placeholderPlaybackActive = NO;
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
        [self resetAnalyticsSession];
        [self updateRemoteCommandAvailability];
        return;
    }

    [self stopCurrentPlayers];
    [self.progressTimer invalidate];
    self.progressTimer = nil;

    if ([self isPlaceholderTrack:track]) {
        self.placeholderPlaybackActive = YES;
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
        [self resetAnalyticsSession];
        [self updateRemoteCommandAvailability];
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
        return;
    }

    if (![self isStreamingTrack:track]) {
        NSError *playerError = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:track.url error:&playerError];
        if (player == nil || playerError != nil) {
            NSLog(@"Playback init failed: %@", playerError.localizedDescription);
            self.currentMeterLevel = 0.0f;
            [self postMeterDidChangeWithLevel:0.0f];
            [self resetAnalyticsSession];
            self.placeholderPlaybackActive = NO;
            [self updateRemoteCommandAvailability];
            [self postStateDidChange];
            return;
        }

        player.delegate = self;
        player.meteringEnabled = YES;
        player.volume = 1.0f;
        [player prepareToPlay];

        if (![player play]) {
            NSLog(@"Playback start failed for %@", track.fileName);
            [self resetAnalyticsSession];
            self.placeholderPlaybackActive = NO;
            [self updateRemoteCommandAvailability];
            [self postStateDidChange];
            return;
        }

        self.audioPlayer = player;
        self.placeholderPlaybackActive = NO;
        if (self.pendingRestoredTrackID.length > 0 &&
            [self.pendingRestoredTrackID isEqualToString:track.identifier] &&
            self.pendingRestoredTime > 0.0) {
            player.currentTime = MIN(self.pendingRestoredTime, player.duration);
        }
        self.pendingRestoredTrackID = @"";
        self.pendingRestoredTime = 0.0;
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
        [SonoraPlaybackHistoryStore.sharedStore recordTrackID:track.identifier];
        [self beginAnalyticsSessionForCurrentTrack];

        [self startProgressTimerIfNeeded];
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
        return;
    }

    NSURL *streamURL = track.url;
    NSString *streamScheme = [[(streamURL.scheme ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    BOOL streamURLIsValid = (streamURL != nil &&
                             !streamURL.isFileURL &&
                             streamScheme.length > 0 &&
                             ([streamScheme isEqualToString:@"http"] || [streamScheme isEqualToString:@"https"]));
    if (!streamURLIsValid) {
        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_init_invalid_url track=%@ url=%@",
                                           track.identifier ?: @"",
                                           streamURL.absoluteString ?: @"<nil>"]);
        [self resetAnalyticsSession];
        self.placeholderPlaybackActive = NO;
        [self updateRemoteCommandAvailability];
        [self postStateDidChange];
        return;
    }

    AVPlayerItem *streamItem = nil;
    @try {
        streamItem = [AVPlayerItem playerItemWithURL:streamURL];
    } @catch (NSException *exception) {
        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_init_exception track=%@ reason=%@",
                                           track.identifier ?: @"",
                                           exception.reason ?: @"unknown"]);
    }
    if (streamItem == nil) {
        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_init_failed track=%@ url=%@",
                                           track.identifier ?: @"",
                                           streamURL.absoluteString ?: @"<nil>"]);
        [self resetAnalyticsSession];
        self.placeholderPlaybackActive = NO;
        [self updateRemoteCommandAvailability];
        [self postStateDidChange];
        return;
    }

    AVPlayer *streamingPlayer = [AVPlayer playerWithPlayerItem:streamItem];
    __weak typeof(self) weakSelf = self;
    id streamObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                       object:streamItem
                                                                        queue:NSOperationQueue.mainQueue
                                                                   usingBlock:^(NSNotification * _Nonnull note) {
        (void)note;
        [weakSelf handleStreamingPlayerDidFinish];
    }];
    id streamFailedObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                                                                              object:streamItem
                                                                               queue:NSOperationQueue.mainQueue
                                                                          usingBlock:^(NSNotification * _Nonnull note) {
        NSError *streamError = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_failed track=%@ error=%@",
                                           track.identifier ?: @"",
                                           streamError.localizedDescription ?: @"unknown"]);
        [weakSelf resetAnalyticsSession];
        [weakSelf stopStreamingPlayer];
        weakSelf.placeholderPlaybackActive = NO;
        [weakSelf updateRemoteCommandAvailability];
        [weakSelf updateNowPlayingInfo];
        [weakSelf postStateDidChange];
        [weakSelf postProgressDidChange];
    }];
    self.streamEndObserver = streamObserver;
    self.streamFailedObserver = streamFailedObserver;
    self.streamTimeObserver = nil;

    self.streamingPlayer = streamingPlayer;
    self.placeholderPlaybackActive = NO;
    if (self.pendingRestoredTrackID.length > 0 &&
        [self.pendingRestoredTrackID isEqualToString:track.identifier] &&
        self.pendingRestoredTime > 0.0) {
        [streamingPlayer seekToTime:CMTimeMakeWithSeconds(self.pendingRestoredTime, NSEC_PER_SEC)];
    }
    self.pendingRestoredTrackID = @"";
    self.pendingRestoredTime = 0.0;
    self.currentMeterLevel = 0.0f;
    [self postMeterDidChangeWithLevel:0.0f];
    [SonoraPlaybackHistoryStore.sharedStore recordTrackID:track.identifier];
    [self beginAnalyticsSessionForCurrentTrack];

    if (@available(iOS 10.0, *)) {
        streamingPlayer.automaticallyWaitsToMinimizeStalling = NO;
        [streamingPlayer playImmediatelyAtRate:1.0f];
    } else {
        [streamingPlayer play];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.streamingPlayer != streamingPlayer) {
            return;
        }
        if (streamingPlayer.rate > 0.0f) {
            return;
        }
        NSError *itemError = streamingPlayer.currentItem.error;
        AVPlayerItemStatus itemStatus = streamingPlayer.currentItem.status;
        SonoraDiagnosticsLog(@"playback", [NSString stringWithFormat:@"stream_not_started track=%@ status=%ld rate=%.2f error=%@",
                                           track.identifier ?: @"",
                                           (long)itemStatus,
                                           streamingPlayer.rate,
                                           itemError.localizedDescription ?: @"none"]);
    });
    [self startProgressTimerIfNeeded];
    [self updateNowPlayingInfo];
    [self postStateDidChange];
    [self postProgressDidChange];
}

- (void)handleStreamingPlayerDidFinish {
    if (self.streamingPlayer == nil) {
        return;
    }
    self.currentMeterLevel = 0.0f;
    [self postMeterDidChangeWithLevel:0.0f];
    NSTimeInterval gapSeconds = [self configuredTrackGapSeconds];
    if (!isfinite(gapSeconds) || gapSeconds <= 0.01) {
        [self advanceToNextTrackAutomatically:YES];
        return;
    }

    NSUInteger requestToken = self.automaticAdvanceRequestToken + 1;
    self.automaticAdvanceRequestToken = requestToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gapSeconds * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.automaticAdvanceRequestToken != requestToken) {
            return;
        }
        [self advanceToNextTrackAutomatically:YES];
    });
}

- (void)startProgressTimerIfNeeded {
    [self.progressTimer invalidate];
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                          target:self
                                                        selector:@selector(handleProgressTick)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)handleProgressTick {
    if (self.audioPlayer == nil && self.streamingPlayer == nil) {
        return;
    }

    if (self.audioPlayer != nil) {
        [self.audioPlayer updateMeters];
        float averagePower = [self.audioPlayer averagePowerForChannel:0];
        float normalizedLevel = isfinite(averagePower) ? powf(10.0f, averagePower / 20.0f) : 0.0f;
        self.currentMeterLevel = MIN(MAX(normalizedLevel, 0.0f), 1.0f);
        [self postMeterDidChangeWithLevel:self.currentMeterLevel];
    } else {
        self.currentMeterLevel = 0.0f;
        [self postMeterDidChangeWithLevel:0.0f];
    }

    [self updateAnalyticsProgressSnapshot];
    [self updateNowPlayingInfo];
    [self postProgressDidChange];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    (void)player;
    (void)flag;
    self.currentMeterLevel = 0.0f;
    [self postMeterDidChangeWithLevel:0.0f];
    NSTimeInterval gapSeconds = [self configuredTrackGapSeconds];
    if (!isfinite(gapSeconds) || gapSeconds <= 0.01) {
        [self advanceToNextTrackAutomatically:YES];
        return;
    }

    NSUInteger requestToken = self.automaticAdvanceRequestToken + 1;
    self.automaticAdvanceRequestToken = requestToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gapSeconds * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.automaticAdvanceRequestToken != requestToken) {
            return;
        }
        [self advanceToNextTrackAutomatically:YES];
    });
}

- (void)configureRemoteCommands {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;

    [center.playCommand addTarget:self action:@selector(handleRemotePlay:)];
    [center.pauseCommand addTarget:self action:@selector(handleRemotePause:)];
    [center.togglePlayPauseCommand addTarget:self action:@selector(handleRemoteToggle:)];
    [center.nextTrackCommand addTarget:self action:@selector(handleRemoteNext:)];
    [center.previousTrackCommand addTarget:self action:@selector(handleRemotePrevious:)];
    if (@available(iOS 9.1, *)) {
        [center.changePlaybackPositionCommand addTarget:self action:@selector(handleRemoteChangePlaybackPosition:)];
    }
    [self updateRemoteCommandAvailability];
}

- (MPRemoteCommandHandlerStatus)handleRemotePlay:(MPRemoteCommandEvent *)event {
    (void)event;
    BOOL hasNowPlayingContext = (self.currentTrack != nil ||
                                 self.audioPlayer != nil ||
                                 self.streamingPlayer != nil ||
                                 self.queue.count > 0);
    if (!hasNowPlayingContext) {
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }

    if ((self.audioPlayer != nil || self.streamingPlayer != nil) && !self.isPlaying) {
        [self togglePlayPause];
        return MPRemoteCommandHandlerStatusSuccess;
    }

    if (self.audioPlayer != nil || self.streamingPlayer != nil) {
        return MPRemoteCommandHandlerStatusSuccess;
    }

    if ([self isPlaceholderTrack:self.currentTrack]) {
        self.placeholderPlaybackActive = YES;
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
        return MPRemoteCommandHandlerStatusSuccess;
    }

    if (self.queue.count > 0 && self.currentIndex == NSNotFound) {
        self.currentIndex = 0;
    }

    if (self.queue.count > 0) {
        [self startCurrentTrack];
    }
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemotePause:(MPRemoteCommandEvent *)event {
    (void)event;
    BOOL hasNowPlayingContext = (self.currentTrack != nil ||
                                 self.audioPlayer != nil ||
                                 self.streamingPlayer != nil ||
                                 self.queue.count > 0);
    if (!hasNowPlayingContext) {
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }

    if (self.audioPlayer != nil || self.streamingPlayer != nil) {
        if (self.isPlaying) {
            [self togglePlayPause];
        }
        return MPRemoteCommandHandlerStatusSuccess;
    }

    if ([self isPlaceholderTrack:self.currentTrack]) {
        self.placeholderPlaybackActive = NO;
        [self updateNowPlayingInfo];
        [self postStateDidChange];
        [self postProgressDidChange];
    }
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteToggle:(MPRemoteCommandEvent *)event {
    (void)event;
    BOOL hasNowPlayingContext = (self.currentTrack != nil ||
                                 self.audioPlayer != nil ||
                                 self.streamingPlayer != nil ||
                                 self.queue.count > 0);
    if (!hasNowPlayingContext) {
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }
    [self togglePlayPause];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteNext:(MPRemoteCommandEvent *)event {
    (void)event;
    [self playNext];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemotePrevious:(MPRemoteCommandEvent *)event {
    (void)event;
    [self playPrevious];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteChangePlaybackPosition:(MPRemoteCommandEvent *)event {
    if (![event isKindOfClass:MPChangePlaybackPositionCommandEvent.class]) {
        return MPRemoteCommandHandlerStatusCommandFailed;
    }

    if (self.currentTrack == nil) {
        return MPRemoteCommandHandlerStatusNoSuchContent;
    }

    MPChangePlaybackPositionCommandEvent *positionEvent = (MPChangePlaybackPositionCommandEvent *)event;
    NSTimeInterval maxDuration = self.duration;
    NSTimeInterval targetTime = MAX(0.0, positionEvent.positionTime);
    if (isfinite(maxDuration) && maxDuration > 0.0) {
        targetTime = MIN(targetTime, maxDuration);
    }
    if (self.audioPlayer != nil || self.streamingPlayer != nil) {
        [self seekToTime:targetTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }

    self.pendingRestoredTrackID = self.currentTrack.identifier ?: @"";
    self.pendingRestoredTime = targetTime;
    [self updateNowPlayingInfo];
    [self postProgressDidChange];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (void)updateNowPlayingInfo {
    SonoraTrack *track = self.currentTrack;
    if (track == nil) {
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
        return;
    }

    NSMutableDictionary<NSString *, id> *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = track.title ?: @"Unknown Track";
    if (track.artist.length > 0) {
        info[MPMediaItemPropertyArtist] = track.artist;
    }
    NSTimeInterval duration = self.duration;
    if ((!isfinite(duration) || duration <= 0.0) && self.audioPlayer != nil) {
        duration = self.audioPlayer.duration;
    }
    if ((!isfinite(duration) || duration <= 0.0) && self.streamingPlayer.currentItem != nil) {
        NSTimeInterval streamDuration = CMTimeGetSeconds(self.streamingPlayer.currentItem.duration);
        if (isfinite(streamDuration) && streamDuration > 0.0) {
            duration = streamDuration;
        }
    }
    NSTimeInterval elapsed = self.currentTime;
    if (!isfinite(duration) || duration < 0.0) {
        duration = 0.0;
    }
    if (!isfinite(elapsed) || elapsed < 0.0) {
        elapsed = 0.0;
    }
    if (duration > 0.0) {
        elapsed = MIN(elapsed, duration);
    }
    if (duration > 0.0) {
        info[MPMediaItemPropertyPlaybackDuration] = @(duration);
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? @1.0 : @0.0;
    if (@available(iOS 10.0, *)) {
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @1.0;
    }
    NSInteger queueCount = (NSInteger)self.queue.count;
    NSInteger queueIndex = self.currentIndex;
    if (queueCount > 0) {
        if (queueIndex == NSNotFound) {
            queueIndex = 0;
        }
        queueIndex = MIN(MAX(queueIndex, 0), queueCount - 1);
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = @(queueCount);
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = @(queueIndex);
    }

    if (track.artwork != nil) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:track.artwork.size
                                                                       requestHandler:^UIImage * _Nonnull(CGSize size) {
            (void)size;
            return track.artwork;
        }];
        info[MPMediaItemPropertyArtwork] = artwork;
    }

    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
}

- (void)updateRemoteCommandAvailability {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    BOOL hasQueue = (self.queue.count > 0);
    BOOL hasTrack = (self.currentTrack != nil);
    BOOL hasPlayer = (self.audioPlayer != nil || self.streamingPlayer != nil);
    BOOL hasNowPlayingContext = (hasTrack || hasPlayer || hasQueue);
    NSTimeInterval duration = self.duration;
    if ((!isfinite(duration) || duration <= 0.0) && self.audioPlayer != nil) {
        duration = self.audioPlayer.duration;
    }
    if ((!isfinite(duration) || duration <= 0.0) && self.streamingPlayer.currentItem != nil) {
        NSTimeInterval streamDuration = CMTimeGetSeconds(self.streamingPlayer.currentItem.duration);
        if (isfinite(streamDuration) && streamDuration > 0.0) {
            duration = streamDuration;
        }
    }
    BOOL canSeek = (hasNowPlayingContext && isfinite(duration) && duration > 0.0);
    center.playCommand.enabled = hasNowPlayingContext && !self.isPlaying;
    center.pauseCommand.enabled = hasNowPlayingContext && self.isPlaying;
    center.togglePlayPauseCommand.enabled = hasNowPlayingContext;
    center.nextTrackCommand.enabled = hasNowPlayingContext;
    center.previousTrackCommand.enabled = hasNowPlayingContext;
    if (@available(iOS 9.1, *)) {
        center.changePlaybackPositionCommand.enabled = canSeek;
    }
}

- (void)handleApplicationLifecyclePersist:(NSNotification *)notification {
    (void)notification;
    [self persistPlaybackSessionToDefaults];
}

- (void)postStateDidChange {
    [self updateRemoteCommandAvailability];
    [self persistPlaybackSessionToDefaults];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaybackStateDidChangeNotification object:self];
}

- (void)postProgressDidChange {
    [self persistPlaybackSessionToDefaults];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaybackProgressDidChangeNotification object:self];
}

- (void)postMeterDidChangeWithLevel:(float)level {
    NSDictionary<NSString *, NSNumber *> *userInfo = @{
        @"level": @(MIN(MAX(level, 0.0f), 1.0f))
    };
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaybackMeterDidChangeNotification
                                                      object:self
                                                    userInfo:userInfo];
}

@end
