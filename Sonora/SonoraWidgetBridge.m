//
//  SonoraWidgetBridge.m
//  Sonora
//

#import "SonoraWidgetBridge.h"

#import <objc/message.h>

#import "SonoraServices.h"

static NSString * const SonoraWidgetAppGroupIdentifier = @"group.ru.hippo.Sonora.shared";
static NSString * const SonoraWidgetLovelyTracksDefaultsKey = @"sonora_widget_lovely_tracks_v1";
static NSString * const SonoraWidgetRandomTracksDefaultsKey = @"sonora_widget_random_tracks_v1";
static NSString * const SonoraWidgetArtworkDirectoryName = @"sonora_widget_artwork_v1";
static NSString * const SonoraWidgetArtworkFileNameKey = @"artworkFileName";
static NSString * const SonoraWidgetArtworkThumbKey = @"artworkThumb";
static NSString * const SonoraWidgetDeepLinkScheme = @"sonora";
static NSString * const SonoraWidgetDeepLinkHost = @"widget";
static NSString * const SonoraWidgetDeepLinkPath = @"/play";
static NSString * const SonoraWidgetDeepLinkTrackIDQueryItem = @"trackID";
static NSString * const SonoraLovelyPlaylistDefaultsKey = @"sonora_lovely_playlist_id_v1";
static NSString * const SonoraWidgetUpdatedAtDefaultsKey = @"sonora_widget_lovely_tracks_updated_at_v1";
static const NSTimeInterval SonoraWidgetRefreshThrottleInterval = 300.0;

static UIImage *SonoraWidgetPreparedArtworkImage(UIImage *image, CGSize targetSize) {
    if (image == nil) {
        return nil;
    }

    if (targetSize.width <= 1.0 || targetSize.height <= 1.0) {
        return image;
    }

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIColor blackColor] setFill];
        UIRectFill((CGRect){ .origin = CGPointZero, .size = targetSize });

        CGSize imageSize = image.size;
        if (imageSize.width <= 1.0 || imageSize.height <= 1.0) {
            [image drawInRect:(CGRect){ .origin = CGPointZero, .size = targetSize }];
            return;
        }

        CGFloat scale = MAX(targetSize.width / imageSize.width, targetSize.height / imageSize.height);
        CGSize drawSize = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
        CGRect drawRect = CGRectMake((targetSize.width - drawSize.width) * 0.5,
                                     (targetSize.height - drawSize.height) * 0.5,
                                     drawSize.width,
                                     drawSize.height);
        [image drawInRect:drawRect];
    }];
}

static NSData *SonoraWidgetThumbnailData(UIImage *image, CGSize targetSize) {
    UIImage *prepared = SonoraWidgetPreparedArtworkImage(image, targetSize);
    if (prepared == nil) {
        return nil;
    }

    NSData *jpeg = UIImageJPEGRepresentation(prepared, 0.78);
    if (jpeg.length > 0) {
        return jpeg;
    }

    return UIImagePNGRepresentation(prepared);
}

@implementation SonoraWidgetBridge

+ (NSArray<SonoraTrack *> *)lovelyTracksFromLibrary {
    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    if (library.tracks.count == 0) {
        [library reloadTracks];
    }

    NSArray<SonoraTrack *> *tracks = library.tracks;
    if (tracks.count == 0) {
        return @[];
    }

    SonoraTrackAnalyticsStore *analytics = SonoraTrackAnalyticsStore.sharedStore;
    NSArray<SonoraTrack *> *sorted = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack *first, SonoraTrack *second) {
        double firstScore = [analytics scoreForTrackID:first.identifier ?: @""];
        double secondScore = [analytics scoreForTrackID:second.identifier ?: @""];
        if (firstScore > secondScore) {
            return NSOrderedAscending;
        }
        if (firstScore < secondScore) {
            return NSOrderedDescending;
        }
        return [first.title ?: @"" compare:second.title ?: @"" options:NSCaseInsensitiveSearch];
    }];

    NSUInteger limit = MIN(sorted.count, 120);
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

+ (NSArray<SonoraTrack *> *)randomTracksFromLibrary {
    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    NSArray<SonoraTrack *> *tracks = library.tracks;
    if (tracks.count == 0) {
        tracks = [library reloadTracks];
    }
    return tracks ?: @[];
}

+ (nullable NSURL *)widgetArtworkDirectoryURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *containerURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:SonoraWidgetAppGroupIdentifier];
    if (containerURL == nil) {
        return nil;
    }

    NSURL *directoryURL = [containerURL URLByAppendingPathComponent:SonoraWidgetArtworkDirectoryName isDirectory:YES];
    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:directoryURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    if (directoryError != nil) {
        return nil;
    }

    return directoryURL;
}

+ (void)clearWidgetArtworkAtDirectoryURL:(nullable NSURL *)directoryURL {
    if (directoryURL == nil) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *listError = nil;
    NSArray<NSURL *> *files = [fileManager contentsOfDirectoryAtURL:directoryURL
                                          includingPropertiesForKeys:nil
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                               error:&listError];
    if (listError != nil || files.count == 0) {
        return;
    }

    for (NSURL *fileURL in files) {
        [fileManager removeItemAtURL:fileURL error:nil];
    }
}

+ (nullable NSString *)storeWidgetArtworkForTrack:(SonoraTrack *)track directoryURL:(nullable NSURL *)directoryURL {
    if (directoryURL == nil || track.artwork == nil || track.identifier.length == 0) {
        return nil;
    }

    UIImage *prepared = SonoraWidgetPreparedArtworkImage(track.artwork, CGSizeMake(420.0, 420.0));
    if (prepared == nil) {
        return nil;
    }

    NSData *artworkData = UIImageJPEGRepresentation(prepared, 0.84);
    if (artworkData.length == 0) {
        artworkData = UIImagePNGRepresentation(prepared);
    }
    if (artworkData.length == 0) {
        return nil;
    }

    NSString *fileName = [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString.lowercaseString];
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    BOOL success = [artworkData writeToURL:fileURL options:NSDataWritingAtomic error:&writeError];
    if (!success || writeError != nil) {
        return nil;
    }

    return fileName;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)serializedWidgetTracks:(NSArray<SonoraTrack *> *)tracks
                                                          artworkDirectoryURL:(nullable NSURL *)artworkDirectoryURL {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *payload = [NSMutableArray arrayWithCapacity:tracks.count];

    for (SonoraTrack *track in tracks) {
        if (track.identifier.length == 0) {
            continue;
        }

        NSString *title = track.title.length > 0 ? track.title : track.fileName;
        NSString *artist = track.artist.length > 0 ? track.artist : @"";
        NSMutableDictionary<NSString *, NSString *> *entry = [@{
            @"id": track.identifier,
            @"title": (title.length > 0 ? title : @"Unknown Song"),
            @"artist": artist
        } mutableCopy];

        NSString *artworkFileName = [self storeWidgetArtworkForTrack:track directoryURL:artworkDirectoryURL];
        if (artworkFileName.length > 0) {
            entry[SonoraWidgetArtworkFileNameKey] = artworkFileName;
        }

        NSData *thumbData = SonoraWidgetThumbnailData(track.artwork, CGSizeMake(96.0, 96.0));
        if (thumbData.length > 0) {
            entry[SonoraWidgetArtworkThumbKey] = [thumbData base64EncodedStringWithOptions:0];
        }

        [payload addObject:entry];

        if (payload.count >= 80) {
            break;
        }
    }

    return [payload copy];
}

+ (void)reloadWidgetTimelinesIfAvailable {
    if (@available(iOS 14.0, *)) {
        void (^reloadBlock)(void) = ^{
            Class widgetCenterClass = NSClassFromString(@"WidgetCenter");
            SEL sharedCenterSelector = NSSelectorFromString(@"sharedCenter");
            SEL reloadAllTimelinesSelector = NSSelectorFromString(@"reloadAllTimelines");
            if (widgetCenterClass == Nil || ![widgetCenterClass respondsToSelector:sharedCenterSelector]) {
                return;
            }

            id center = ((id (*)(id, SEL))objc_msgSend)(widgetCenterClass, sharedCenterSelector);
            if (center == nil || ![center respondsToSelector:reloadAllTimelinesSelector]) {
                return;
            }

            ((void (*)(id, SEL))objc_msgSend)(center, reloadAllTimelinesSelector);
        };

        if (NSThread.isMainThread) {
            reloadBlock();
        } else {
            dispatch_async(dispatch_get_main_queue(), reloadBlock);
        }
    }
}

+ (void)refreshSharedLovelyTracks {
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:SonoraWidgetAppGroupIdentifier];
    if (sharedDefaults == nil) {
        return;
    }

    NSArray *existingLovely = [sharedDefaults objectForKey:SonoraWidgetLovelyTracksDefaultsKey];
    NSArray *existingRandom = [sharedDefaults objectForKey:SonoraWidgetRandomTracksDefaultsKey];
    BOOL hasExistingPayload = ([existingLovely isKindOfClass:NSArray.class] && existingLovely.count > 0) ||
    ([existingRandom isKindOfClass:NSArray.class] && existingRandom.count > 0);

    NSDate *lastUpdatedAt = [sharedDefaults objectForKey:SonoraWidgetUpdatedAtDefaultsKey];
    if (hasExistingPayload && [lastUpdatedAt isKindOfClass:NSDate.class]) {
        NSTimeInterval age = fabs(lastUpdatedAt.timeIntervalSinceNow);
        if (age < SonoraWidgetRefreshThrottleInterval) {
            return;
        }
    }

    NSURL *artworkDirectoryURL = [self widgetArtworkDirectoryURL];
    [self clearWidgetArtworkAtDirectoryURL:artworkDirectoryURL];

    NSArray<SonoraTrack *> *lovelyTracks = [self lovelyTracksFromLibrary];
    NSArray<SonoraTrack *> *randomTracks = [self randomTracksFromLibrary];
    NSArray<NSDictionary<NSString *, NSString *> *> *lovelyPayload = [self serializedWidgetTracks:lovelyTracks
                                                                                artworkDirectoryURL:artworkDirectoryURL];
    NSArray<NSDictionary<NSString *, NSString *> *> *randomPayload = [self serializedWidgetTracks:randomTracks
                                                                                artworkDirectoryURL:artworkDirectoryURL];
    [sharedDefaults setObject:lovelyPayload forKey:SonoraWidgetLovelyTracksDefaultsKey];
    [sharedDefaults setObject:randomPayload forKey:SonoraWidgetRandomTracksDefaultsKey];
    [sharedDefaults setObject:NSDate.date forKey:SonoraWidgetUpdatedAtDefaultsKey];
    [sharedDefaults synchronize];
    [self reloadWidgetTimelinesIfAvailable];
}

+ (nullable NSString *)trackIDFromDeepLinkURL:(NSURL *)url {
    if (![url isKindOfClass:NSURL.class]) {
        return nil;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:SonoraWidgetDeepLinkScheme]) {
        return nil;
    }

    NSString *host = url.host.lowercaseString;
    if (![host isEqualToString:SonoraWidgetDeepLinkHost]) {
        return nil;
    }

    NSString *path = url.path ?: @"";
    if (path.length > 0 && ![path isEqualToString:SonoraWidgetDeepLinkPath]) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isEqualToString:SonoraWidgetDeepLinkTrackIDQueryItem]) {
            continue;
        }
        if (item.value.length > 0) {
            return item.value;
        }
        break;
    }

    return @"";
}

+ (void)playTrackWithIdentifier:(NSString *)trackID {
    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    if (library.tracks.count == 0) {
        [library reloadTracks];
    }

    SonoraTrack *track = nil;
    if (trackID.length > 0) {
        track = [library trackForIdentifier:trackID];
    }

    if (track == nil) {
        NSArray<SonoraTrack *> *lovelyTracks = [self lovelyTracksFromLibrary];
        if (lovelyTracks.count > 0) {
            NSUInteger index = arc4random_uniform((uint32_t)lovelyTracks.count);
            track = lovelyTracks[index];
        }
    }

    if (track == nil) {
        return;
    }

    [SonoraPlaybackManager.sharedManager playTrack:track];
}

+ (BOOL)handleWidgetDeepLinkURL:(NSURL *)url {
    NSString *trackID = [self trackIDFromDeepLinkURL:url];
    if (trackID == nil) {
        return NO;
    }

    if (NSThread.isMainThread) {
        [self playTrackWithIdentifier:trackID];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playTrackWithIdentifier:trackID];
        });
    }

    return YES;
}

@end
