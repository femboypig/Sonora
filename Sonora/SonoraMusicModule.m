//
//  SonoraMusicModule.m
//  Sonora
//

#import "SonoraMusicModule.h"

#import <limits.h>
#import <math.h>
#import <PhotosUI/PhotosUI.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SonoraCells.h"
#import "SonoraServices.h"

static UIColor *SonoraLovelyAccentRedColor(void) {
    return [UIColor colorWithRed:0.90 green:0.12 blue:0.15 alpha:1.0];
}

static NSString * const SonoraLovelyPlaylistDefaultsKey = @"sonora_lovely_playlist_id_v1";
static NSString * const SonoraLovelyPlaylistCoverMarkerKey = @"sonora_lovely_playlist_cover_marker_v2";
static NSString * const SonoraSettingsFontKey = @"sonora.settings.font";
static NSString * const SonoraSettingsAccentHexKey = @"sonora.settings.accentHex";
static NSString * const SonoraSettingsLegacyAccentColorKey = @"sonora.settings.accentColor";
static NSString * const SonoraSettingsArtworkStyleKey = @"sonora.settings.artworkStyle";
static NSString * const SonoraSettingsArtworkEqualizerKey = @"sonora.settings.showArtworkEqualizer";
static NSString * const SonoraSettingsMaxStorageMBKey = @"sonora.settings.maxStorageMB";
static NSString * const SonoraMiniStreamingDefaultBackendBaseURLString = @"https://api.corebrew.ru";
static NSString * const SonoraMiniStreamingBackendSearchPath = @"/api/spotify/search";
static NSString * const SonoraMiniStreamingBackendDownloadPath = @"/api/download";
static NSString * const SonoraMiniStreamingSpotifyTokenURLString = @"https://accounts.spotify.com/api/token";
static NSString * const SonoraMiniStreamingSpotifySearchURLString = @"https://api.spotify.com/v1/search";
static NSString * const SonoraMiniStreamingRapidAPIDownloadURLString = @"https://spotify-music-mp3-downloader-api.p.rapidapi.com/download";
static NSString * const SonoraMiniStreamingRapidAPIDownloader9URLString = @"https://spotify-downloader9.p.rapidapi.com/downloadSong";
static NSString * const SonoraMiniStreamingRapidAPIDownloader9Host = @"spotify-downloader9.p.rapidapi.com";
static NSString * const SonoraMiniStreamingDefaultRapidAPIHost = @"spotify-music-mp3-downloader-api.p.rapidapi.com";
static NSString * const SonoraMiniStreamingKeyBrokerAvailableURLString = @"https://api.corebrew.ru/api/available";
static NSString * const SonoraMiniStreamingKeyBrokerMarkURLString = @"https://api.corebrew.ru/api/mark";
static NSString * const SonoraMiniStreamingErrorDomain = @"SonoraMiniStreamingErrorDomain";
static NSString * const SonoraMiniStreamingPlaceholderPrefix = @"mini-streaming-placeholder-";
static NSString * const SonoraMiniStreamingInstalledTrackMapDefaultsKey = @"sonora.ministreaming.installedTrackPathsByTrackID.v1";
static NSString * const SonoraMiniStreamingInstallUnavailableMessage = @"Установка временно недоступна, попробуйте завтра.";
static NSUInteger const SonoraMiniStreamingSearchLimit = 8;
static NSString * const SonoraSharedPlaylistDefaultsKey = @"sonora.sharedPlaylists.v1";
static NSString * const SonoraSettingsCacheOnlinePlaylistTracksKey = @"sonora.settings.cacheOnlinePlaylistTracks";
static NSString * const SonoraSettingsOnlinePlaylistCacheMaxMBKey = @"sonora.settings.onlinePlaylistCacheMaxMB";
static NSString * const SonoraSharedPlaylistSyntheticPrefix = @"shared:";
static NSString * const SonoraSharedPlaylistDeepLinkHost = @"playlist";
static NSString * const SonoraSharedPlaylistDeepLinkPath = @"/shared";
static NSString * const SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey = @"sonora.sharedPlaylists.suppressDidChangeNotification";

static void SonoraPresentAlert(UIViewController *controller, NSString *title, NSString *message);
static NSString *SonoraSharedPlaylistSyntheticID(NSString *remoteID);
static NSString *SonoraSharedPlaylistBackendBaseURLString(void);
static NSString *SonoraSharedPlaylistStorageDirectoryPath(void);
static NSString *SonoraSharedPlaylistAudioCacheDirectoryPath(void);
static UIImage * _Nullable SonoraSharedPlaylistFetchImage(NSString *urlString);
static UIViewController * _Nullable SonoraTopMostViewController(void);
static UIAlertController * _Nullable SonoraPresentBlockingProgressAlert(UIViewController *controller, NSString *title, NSString *message);
static NSURL * _Nullable SonoraSharedPlaylistDownloadedFileURL(NSString *urlString, NSString *suggestedBaseName);
static NSData * _Nullable SonoraSharedPlaylistDataFromURL(NSURL *url, NSTimeInterval timeout, NSURLResponse * __autoreleasing _Nullable *responseOut);
static NSData * _Nullable SonoraSharedPlaylistPerformRequest(NSURLRequest *request, NSTimeInterval timeout, NSHTTPURLResponse * __autoreleasing _Nullable *responseOut);
static void SonoraSharedPlaylistAppendMultipartText(NSMutableData *body, NSString *boundary, NSString *name, NSString *value);
static void SonoraSharedPlaylistAppendMultipartFile(NSMutableData *body, NSString *boundary, NSString *name, NSString *filename, NSString *mimeType, NSData *data);

@interface SonoraSharedPlaylistSnapshot : NSObject

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *remoteID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shareURL;
@property (nonatomic, copy) NSString *sourceBaseURL;
@property (nonatomic, copy) NSString *contentSHA256;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, strong, nullable) UIImage *coverImage;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *trackArtworkURLByTrackID;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *trackRemoteFileURLByTrackID;

@end

static SonoraSharedPlaylistSnapshot * _Nullable SonoraSharedPlaylistSnapshotFromPayload(NSDictionary<NSString *, id> *payload, NSString *fallbackBaseURL) {
    if (![payload isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *remoteID = [payload[@"id"] isKindOfClass:NSString.class] ? payload[@"id"] : @"";
    NSString *name = [payload[@"name"] isKindOfClass:NSString.class] ? payload[@"name"] : @"Shared Playlist";
    if (remoteID.length == 0 || name.length == 0) {
        return nil;
    }

    SonoraSharedPlaylistSnapshot *snapshot = [[SonoraSharedPlaylistSnapshot alloc] init];
    snapshot.remoteID = remoteID;
    snapshot.playlistID = SonoraSharedPlaylistSyntheticID(remoteID);
    snapshot.name = name;
    snapshot.shareURL = [payload[@"shareUrl"] isKindOfClass:NSString.class] ? payload[@"shareUrl"] : ([payload[@"url"] isKindOfClass:NSString.class] ? payload[@"url"] : @"");
    snapshot.sourceBaseURL = [payload[@"sourceBaseURL"] isKindOfClass:NSString.class] ? payload[@"sourceBaseURL"] : fallbackBaseURL;
    snapshot.contentSHA256 = [payload[@"contentSha256"] isKindOfClass:NSString.class] ? payload[@"contentSha256"] : @"";

    NSString *coverURL = [payload[@"coverUrl"] isKindOfClass:NSString.class] ? payload[@"coverUrl"] : @"";
    snapshot.coverURL = coverURL;
    snapshot.coverImage = nil;

    NSArray *trackItems = [payload[@"tracks"] isKindOfClass:NSArray.class] ? payload[@"tracks"] : @[];
    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:trackItems.count];
    NSMutableDictionary<NSString *, NSString *> *trackArtworkURLByTrackID = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *trackRemoteFileURLByTrackID = [NSMutableDictionary dictionary];
    [trackItems enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull item, NSUInteger idx, __unused BOOL * _Nonnull stop) {
        if (![item isKindOfClass:NSDictionary.class]) {
            return;
        }
        SonoraTrack *track = [[SonoraTrack alloc] init];
        track.identifier = [NSString stringWithFormat:@"%@:%lu", snapshot.playlistID, (unsigned long)idx];
        track.title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : [NSString stringWithFormat:@"Track %lu", (unsigned long)(idx + 1)];
        track.artist = [item[@"artist"] isKindOfClass:NSString.class] ? item[@"artist"] : @"";
        track.duration = [item[@"durationMs"] respondsToSelector:@selector(doubleValue)] ? [item[@"durationMs"] doubleValue] / 1000.0 : 0.0;
        NSString *fileURLString = [item[@"fileUrl"] isKindOfClass:NSString.class] ? item[@"fileUrl"] : @"";
        track.url = [NSURL URLWithString:fileURLString] ?: [NSURL fileURLWithPath:@"/dev/null"];
        if (fileURLString.length > 0) {
            trackRemoteFileURLByTrackID[track.identifier] = fileURLString;
        }
        track.artwork = nil;
        NSString *artworkURLString = [item[@"artworkUrl"] isKindOfClass:NSString.class] ? item[@"artworkUrl"] : @"";
        if (artworkURLString.length > 0) {
            trackArtworkURLByTrackID[track.identifier] = artworkURLString;
        }
        [tracks addObject:track];
    }];
    snapshot.tracks = [tracks copy];
    snapshot.trackArtworkURLByTrackID = [trackArtworkURLByTrackID copy];
    snapshot.trackRemoteFileURLByTrackID = [trackRemoteFileURLByTrackID copy];
    return snapshot;
}

static BOOL SonoraSharedPlaylistShouldSuppressDidChangeNotification(void) {
    return [NSThread.currentThread.threadDictionary[SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey] boolValue];
}

static void SonoraSharedPlaylistPerformWithoutDidChangeNotification(dispatch_block_t block) {
    if (block == nil) {
        return;
    }
    NSMutableDictionary<NSString *, id> *threadDictionary = NSThread.currentThread.threadDictionary;
    id previousValue = threadDictionary[SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey];
    threadDictionary[SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey] = @YES;
    @try {
        block();
    } @finally {
        if (previousValue != nil) {
            threadDictionary[SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey] = previousValue;
        } else {
            [threadDictionary removeObjectForKey:SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey];
        }
    }
}

static void SonoraSharedPlaylistPostDidChangeNotification(void) {
    void (^postNotification)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    };
    if (NSThread.isMainThread) {
        postNotification();
    } else {
        dispatch_async(dispatch_get_main_queue(), postNotification);
    }
}

static void SonoraSharedPlaylistWarmPersistentCache(SonoraSharedPlaylistSnapshot *snapshot) {
    if (snapshot == nil) {
        return;
    }
    Class storeClass = NSClassFromString(@"SonoraSharedPlaylistStore");
    id store = nil;
    if (storeClass != Nil) {
        store = [storeClass performSelector:@selector(sharedStore)];
    }
    void (^persistSnapshotIfNeeded)(void) = ^{
        if ([store respondsToSelector:@selector(saveSnapshot:)]) {
            SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                [store performSelector:@selector(saveSnapshot:) withObject:snapshot];
            });
        }
    };
    if (snapshot.coverImage == nil && snapshot.coverURL.length > 0) {
        snapshot.coverImage = SonoraSharedPlaylistFetchImage(snapshot.coverURL);
        persistSnapshotIfNeeded();
    }
    for (SonoraTrack *track in snapshot.tracks) {
        if (track.artwork != nil || track.identifier.length == 0) {
            continue;
        }
        NSString *artworkURL = snapshot.trackArtworkURLByTrackID[track.identifier];
        if (artworkURL.length == 0) {
            continue;
        }
        track.artwork = SonoraSharedPlaylistFetchImage(artworkURL);
        persistSnapshotIfNeeded();
    }
    if ([NSUserDefaults.standardUserDefaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey]) {
        unsigned long long limitBytes = ULLONG_MAX;
        if ([NSUserDefaults.standardUserDefaults objectForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] != nil) {
            NSInteger maxMB = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
            if (maxMB > 0) {
                limitBytes = ((unsigned long long)maxMB) * 1024ULL * 1024ULL;
            }
        } else {
            limitBytes = 1024ULL * 1024ULL * 1024ULL;
        }
        NSString *audioDirectory = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:@"audio"];
        [[NSFileManager defaultManager] createDirectoryAtPath:audioDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            NSString *remoteFileURL = snapshot.trackRemoteFileURLByTrackID[track.identifier ?: @""];
            if (remoteFileURL.length == 0 && !track.url.isFileURL) {
                remoteFileURL = track.url.absoluteString ?: @"";
            }
            if (remoteFileURL.length == 0) {
                return;
            }

            NSString *existingLocalPath = track.url.isFileURL ? track.url.path : @"";
            if (existingLocalPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:existingLocalPath]) {
                [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate : NSDate.date }
                                               ofItemAtPath:existingLocalPath
                                                      error:nil];
                return;
            }

            NSURL *remoteURL = [NSURL URLWithString:remoteFileURL];
            if (remoteURL == nil) {
                return;
            }
            NSURLResponse *response = nil;
            NSData *audioData = SonoraSharedPlaylistDataFromURL(remoteURL, 600.0, &response);
            if (audioData.length == 0) {
                return;
            }
            if (limitBytes != ULLONG_MAX && (unsigned long long)audioData.length > limitBytes) {
                return;
            }

            NSString *extension = remoteURL.pathExtension.lowercaseString;
            if (extension.length == 0 && [response isKindOfClass:NSHTTPURLResponse.class]) {
                NSString *mimeType = ((NSHTTPURLResponse *)response).MIMEType.lowercaseString ?: @"";
                if ([mimeType containsString:@"mpeg"]) {
                    extension = @"mp3";
                } else if ([mimeType containsString:@"mp4"] || [mimeType containsString:@"aac"]) {
                    extension = @"m4a";
                } else if ([mimeType containsString:@"wav"]) {
                    extension = @"wav";
                } else if ([mimeType containsString:@"flac"]) {
                    extension = @"flac";
                }
            }
            if (extension.length == 0) {
                extension = @"audio";
            }

            NSString *fileName = [NSString stringWithFormat:@"%@_%lu.%@", snapshot.remoteID.length > 0 ? snapshot.remoteID : @"shared",
                                  (unsigned long)idx,
                                  extension];
            NSString *destinationPath = [audioDirectory stringByAppendingPathComponent:fileName];
            if (![audioData writeToFile:destinationPath atomically:YES]) {
                return;
            }
            [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate : NSDate.date }
                                           ofItemAtPath:destinationPath
                                                  error:nil];
            track.url = [NSURL fileURLWithPath:destinationPath];
            persistSnapshotIfNeeded();
        }];

        if (limitBytes != ULLONG_MAX) {
            NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:audioDirectory]
                                                                  includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                       error:nil];
            NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
            unsigned long long totalBytes = 0;
            for (NSURL *fileURL in files) {
                NSNumber *isRegularFile = nil;
                [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
                if (![isRegularFile boolValue]) {
                    continue;
                }
                NSNumber *fileSize = nil;
                NSDate *modifiedAt = nil;
                [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
                [fileURL getResourceValue:&modifiedAt forKey:NSURLContentModificationDateKey error:nil];
                unsigned long long currentSize = MAX(fileSize.unsignedLongLongValue, 0);
                totalBytes += currentSize;
                [entries addObject:@{
                    @"url": fileURL,
                    @"modifiedAt": modifiedAt ?: NSDate.distantPast,
                    @"size": @(currentSize)
                }];
            }
            [entries sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> * _Nonnull lhs, NSDictionary<NSString *,id> * _Nonnull rhs) {
                return [lhs[@"modifiedAt"] compare:rhs[@"modifiedAt"]];
            }];
            for (NSDictionary<NSString *, id> *entry in entries) {
                if (totalBytes <= limitBytes) {
                    break;
                }
                NSURL *fileURL = entry[@"url"];
                unsigned long long fileSize = [entry[@"size"] unsignedLongLongValue];
                [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
                totalBytes = (totalBytes > fileSize) ? (totalBytes - fileSize) : 0;
            }
            [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
                if (!track.url.isFileURL) {
                    return;
                }
                if (![NSFileManager.defaultManager fileExistsAtPath:track.url.path]) {
                    NSString *remoteFileURL = snapshot.trackRemoteFileURLByTrackID[track.identifier ?: @""];
                    track.url = [NSURL URLWithString:remoteFileURL] ?: [NSURL fileURLWithPath:@"/dev/null"];
                    persistSnapshotIfNeeded();
                }
            }];
        }
    }
    persistSnapshotIfNeeded();
}

BOOL SonoraHandleMusicModuleDeepLinkURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) {
        return NO;
    }
    if (![[url.scheme lowercaseString] isEqualToString:@"sonora"]) {
        return NO;
    }
    if (![[url.host lowercaseString] isEqualToString:SonoraSharedPlaylistDeepLinkHost]) {
        return NO;
    }
    if (![(url.path ?: @"") isEqualToString:SonoraSharedPlaylistDeepLinkPath]) {
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *playlistID = @"";
    NSString *sourceBaseURL = SonoraSharedPlaylistBackendBaseURLString();
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"id"] && item.value.length > 0) {
            playlistID = item.value;
        } else if ([item.name isEqualToString:@"source"] && item.value.length > 0) {
            sourceBaseURL = item.value;
        }
    }
    if (playlistID.length == 0) {
        return NO;
    }

    UIViewController *presenter = SonoraTopMostViewController();
    id sharedPlaylistStore = nil;
    Class sharedPlaylistStoreClass = NSClassFromString(@"SonoraSharedPlaylistStore");
    if (sharedPlaylistStoreClass != Nil) {
        sharedPlaylistStore = [sharedPlaylistStoreClass performSelector:@selector(sharedStore)];
    }
    SonoraSharedPlaylistSnapshot *cachedSnapshot = nil;
    if ([sharedPlaylistStore respondsToSelector:@selector(snapshotForPlaylistID:)]) {
        id cachedSnapshotObject = [sharedPlaylistStore performSelector:@selector(snapshotForPlaylistID:)
                                                           withObject:SonoraSharedPlaylistSyntheticID(playlistID)];
        if ([cachedSnapshotObject isKindOfClass:SonoraSharedPlaylistSnapshot.class]) {
            cachedSnapshot = (SonoraSharedPlaylistSnapshot *)cachedSnapshotObject;
        }
    }
    __block UIAlertController *progress = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        progress = SonoraPresentBlockingProgressAlert(presenter, @"Opening Playlist", @"Loading tracks from server...");
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *requestString = [[sourceBaseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByAppendingFormat:@"/api/shared-playlists/%@", playlistID];
        NSURL *requestURL = [NSURL URLWithString:requestString];
        NSData *data = requestURL != nil ? SonoraSharedPlaylistDataFromURL(requestURL, 120.0, nil) : nil;
        NSDictionary *payload = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        SonoraSharedPlaylistSnapshot *snapshot = SonoraSharedPlaylistSnapshotFromPayload(payload, sourceBaseURL);
        if (snapshot == nil && cachedSnapshot != nil) {
            snapshot = cachedSnapshot;
        } else if (snapshot != nil && cachedSnapshot != nil &&
                   snapshot.contentSHA256.length > 0 &&
                   [snapshot.contentSHA256 isEqualToString:(cachedSnapshot.contentSHA256 ?: @"")]) {
            snapshot = cachedSnapshot;
        } else if (snapshot != nil && cachedSnapshot != nil) {
            if ([sharedPlaylistStore respondsToSelector:@selector(saveSnapshot:)]) {
                SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                    [sharedPlaylistStore performSelector:@selector(saveSnapshot:) withObject:snapshot];
                });
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                SonoraSharedPlaylistWarmPersistentCache(snapshot);
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^finishOpening)(void) = ^{
                UIViewController *top = presenter ?: SonoraTopMostViewController();
                if (snapshot == nil || top == nil) {
                    if (top != nil) {
                        SonoraPresentAlert(top, @"Error", @"Could not open shared playlist.");
                    }
                    return;
                }
                Class detailClass = NSClassFromString(@"SonoraPlaylistDetailViewController");
                if (detailClass == Nil) {
                    SonoraPresentAlert(top, @"Error", @"Could not open shared playlist.");
                    return;
                }
                UIViewController *detail = [[detailClass alloc] performSelector:@selector(initWithSharedPlaylistSnapshot:) withObject:snapshot];
                detail.hidesBottomBarWhenPushed = YES;
                UINavigationController *nav = top.navigationController;
                if ([top isKindOfClass:UINavigationController.class]) {
                    nav = (UINavigationController *)top;
                }
                if (nav != nil) {
                    [nav pushViewController:detail animated:YES];
                } else {
                    [top presentViewController:[[UINavigationController alloc] initWithRootViewController:detail] animated:YES completion:nil];
                }
            };
            if (progress.presentingViewController != nil) {
                [progress dismissViewControllerAnimated:YES completion:finishOpening];
            } else {
                finishOpening();
            }
        });
    });
    return YES;
}

@implementation SonoraSharedPlaylistSnapshot
@end

@interface SonoraSharedPlaylistStore : NSObject

+ (instancetype)sharedStore;
- (NSArray<SonoraPlaylist *> *)likedPlaylists;
- (nullable SonoraSharedPlaylistSnapshot *)snapshotForPlaylistID:(NSString *)playlistID;
- (BOOL)isSnapshotLikedForPlaylistID:(NSString *)playlistID;
- (void)saveSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot;
- (void)removeSnapshotForPlaylistID:(NSString *)playlistID;
- (void)refreshAllPersistentCachesIfNeeded;

@end

static NSString *SonoraSharedPlaylistSyntheticID(NSString *remoteID) {
    NSString *normalized = [remoteID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (normalized.length == 0) {
        normalized = NSUUID.UUID.UUIDString.lowercaseString;
    }
    return [SonoraSharedPlaylistSyntheticPrefix stringByAppendingString:normalized];
}

static NSString *SonoraSharedPlaylistBackendBaseURLString(void) {
    NSString *configured = [NSBundle.mainBundle objectForInfoDictionaryKey:@"BACKEND_BASE_URL"];
    if ([configured isKindOfClass:NSString.class] && configured.length > 0) {
        return [configured stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return SonoraMiniStreamingDefaultBackendBaseURLString;
}

static NSString *SonoraSharedPlaylistStorageDirectoryPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"SonoraSharedPlaylists"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString *SonoraSharedPlaylistAudioCacheDirectoryPath(void) {
    NSString *directory = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:@"audio"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString *SonoraSharedPlaylistNormalizeText(NSString *value) {
    NSString *normalized = [[value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return normalized;
}

static UIImage * _Nullable SonoraSharedPlaylistImageFromData(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    return [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
}

static NSString * _Nullable SonoraSharedPlaylistWriteImage(UIImage *image, NSString *preferredName) {
    if (image == nil) {
        return nil;
    }
    NSData *data = UIImageJPEGRepresentation(image, 0.84);
    if (data.length == 0) {
        return nil;
    }
    NSString *fileName = preferredName.length > 0 ? preferredName : [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString.lowercaseString];
    NSString *path = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:fileName];
    if (![data writeToFile:path atomically:YES]) {
        return nil;
    }
    return path.lastPathComponent;
}

static UIImage * _Nullable SonoraSharedPlaylistReadImageNamed(NSString *fileName) {
    if (fileName.length == 0) {
        return nil;
    }
    NSString *path = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:fileName];
    NSData *data = [NSData dataWithContentsOfFile:path];
    return SonoraSharedPlaylistImageFromData(data);
}

static UIImage * _Nullable SonoraSharedPlaylistFetchImage(NSString *urlString) {
    if (urlString.length == 0) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    return SonoraSharedPlaylistImageFromData(data);
}

static NSString * _Nullable SonoraSharedPlaylistBase64ForImage(UIImage *image) {
    if (image == nil) {
        return nil;
    }
    NSData *data = UIImageJPEGRepresentation(image, 0.82);
    if (data.length == 0) {
        return nil;
    }
    return [data base64EncodedStringWithOptions:0];
}

static UIViewController * _Nullable SonoraTopMostViewController(void) {
    UIViewController *root = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                root = window.rootViewController;
                break;
            }
        }
        if (root != nil) {
            break;
        }
    }
    UIViewController *current = root;
    while (current.presentedViewController != nil) {
        current = current.presentedViewController;
    }
    if ([current isKindOfClass:UITabBarController.class]) {
        UITabBarController *tab = (UITabBarController *)current;
        current = tab.selectedViewController ?: current;
    }
    if ([current isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)current;
        current = nav.topViewController ?: nav;
    }
    return current;
}

static UIAlertController * _Nullable SonoraPresentBlockingProgressAlert(UIViewController *controller, NSString *title, NSString *message) {
    if (controller == nil) {
        return nil;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [controller presentViewController:alert animated:YES completion:nil];
    return alert;
}

static NSData * _Nullable SonoraSharedPlaylistDataFromURL(NSURL *url, NSTimeInterval timeout, NSURLResponse * __autoreleasing _Nullable *responseOut) {
    if (url == nil) {
        return nil;
    }
    __block NSData *result = nil;
    __block NSURLResponse *capturedResponse = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = MAX(timeout, 30.0);
    configuration.timeoutIntervalForResource = MAX(timeout * 2.0, 60.0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                        completionHandler:^(NSData * _Nullable data,
                                                            NSURLResponse * _Nullable response,
                                                            NSError * _Nullable error) {
        capturedResponse = response;
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error == nil && data.length > 0 && (http == nil || (http.statusCode >= 200 && http.statusCode < 300))) {
            result = data;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    if (responseOut != NULL) {
        *responseOut = capturedResponse;
    }
    return result;
}

static NSData * _Nullable SonoraSharedPlaylistPerformRequest(NSURLRequest *request, NSTimeInterval timeout, NSHTTPURLResponse * __autoreleasing _Nullable *responseOut) {
    if (request == nil) {
        return nil;
    }
    __block NSData *result = nil;
    __block NSHTTPURLResponse *capturedResponse = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = MAX(timeout, 30.0);
    configuration.timeoutIntervalForResource = MAX(timeout * 2.0, 60.0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            capturedResponse = (NSHTTPURLResponse *)response;
        }
        if (error == nil && capturedResponse != nil && capturedResponse.statusCode >= 200 && capturedResponse.statusCode < 300) {
            result = data ?: [NSData data];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    if (responseOut != NULL) {
        *responseOut = capturedResponse;
    }
    return result;
}

static void SonoraSharedPlaylistAppendMultipartText(NSMutableData *body, NSString *boundary, NSString *name, NSString *value) {
    if (body == nil || boundary.length == 0 || name.length == 0 || value == nil) {
        return;
    }
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

static void SonoraSharedPlaylistAppendMultipartFile(NSMutableData *body, NSString *boundary, NSString *name, NSString *filename, NSString *mimeType, NSData *data) {
    if (body == nil || boundary.length == 0 || name.length == 0 || data.length == 0) {
        return;
    }
    NSString *safeFilename = filename.length > 0 ? filename : @"file.bin";
    NSString *safeMime = mimeType.length > 0 ? mimeType : @"application/octet-stream";
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name, safeFilename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", safeMime] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

static NSString *SonoraSharedPlaylistSafeFileComponent(NSString *value) {
    NSString *trimmed = [[value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    if (trimmed.length == 0) {
        return @"track";
    }
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_ ."] invertedSet];
    NSString *safe = [[trimmed componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    while ([safe containsString:@"__"]) {
        safe = [safe stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    }
    return safe.length > 0 ? safe : @"track";
}

static NSURL * _Nullable SonoraSharedPlaylistDownloadedFileURL(NSString *urlString, NSString *suggestedBaseName) {
    NSURL *remoteURL = [NSURL URLWithString:urlString];
    if (remoteURL == nil) {
        return nil;
    }
    NSURLResponse *response = nil;
    NSData *data = SonoraSharedPlaylistDataFromURL(remoteURL, 600.0, &response);
    if (data.length == 0) {
        return nil;
    }
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    NSString *extension = response.suggestedFilename.pathExtension.lowercaseString;
    if (extension.length == 0) {
        extension = remoteURL.pathExtension.length > 0 ? remoteURL.pathExtension.lowercaseString : @"";
    }
    if (extension.length == 0) {
        NSString *mimeType = response.MIMEType.lowercaseString;
        if ([mimeType containsString:@"mp4"]) {
            extension = @"m4a";
        } else if ([mimeType containsString:@"aac"]) {
            extension = @"aac";
        } else if ([mimeType containsString:@"wav"]) {
            extension = @"wav";
        } else if ([mimeType containsString:@"ogg"]) {
            extension = @"ogg";
        } else if ([mimeType containsString:@"flac"]) {
            extension = @"flac";
        } else {
            extension = @"mp3";
        }
    }
    NSString *baseName = SonoraSharedPlaylistSafeFileComponent(suggestedBaseName);
    NSURL *destinationURL = [musicDirectoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, extension]];
    NSUInteger suffix = 1;
    while ([NSFileManager.defaultManager fileExistsAtPath:destinationURL.path]) {
        destinationURL = [musicDirectoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu.%@", baseName, (unsigned long)suffix, extension]];
        suffix += 1;
    }
    if (![data writeToURL:destinationURL atomically:YES]) {
        return nil;
    }
    return destinationURL;
}

static NSString *SonoraSleepTimerRemainingString(NSTimeInterval interval);
static void SonoraPresentSleepTimerActionSheet(UIViewController *controller,
                                               UIView *sourceView,
                                               dispatch_block_t updateHandler);
static void SonoraConfigureNavigationIconBarButtonItem(UIBarButtonItem *item, NSString *title) {
    if (![item isKindOfClass:UIBarButtonItem.class]) {
        return;
    }
    if (title.length == 0) {
        return;
    }
    item.title = title;
    item.accessibilityLabel = title;
}

typedef NS_ENUM(NSInteger, SonoraPlayerFontStyle) {
    SonoraPlayerFontStyleSystem = 0,
    SonoraPlayerFontStyleSerif = 1,
};

typedef NS_ENUM(NSInteger, SonoraPlayerArtworkStyle) {
    SonoraPlayerArtworkStyleSquare = 0,
    SonoraPlayerArtworkStyleRounded = 1,
};

static UIColor *SonoraDefaultAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *SonoraLegacyAccentColorForIndex(NSInteger raw) {
    switch (raw) {
        case 1:
            return [UIColor colorWithRed:0.31 green:0.64 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.22 green:0.83 blue:0.62 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.48 blue:0.40 alpha:1.0];
        case 0:
        default:
            return SonoraDefaultAccentColor();
    }
}

static UIColor *SonoraColorFromHexString(NSString *hexString) {
    if (hexString.length == 0) {
        return nil;
    }
    NSString *normalized = [[hexString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    }
    if (normalized.length != 6) {
        return nil;
    }

    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:normalized] scanHexInt:&rgb]) {
        return nil;
    }

    CGFloat red = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat green = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat blue = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

static UIColor *SonoraAccentYellowColor(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIColor *fromHex = SonoraColorFromHexString([defaults stringForKey:SonoraSettingsAccentHexKey]);
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraLegacyAccentColorForIndex([defaults integerForKey:SonoraSettingsLegacyAccentColorKey]);
}

static SonoraPlayerFontStyle SonoraPlayerFontStyleFromDefaults(void) {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsFontKey];
    if (raw < SonoraPlayerFontStyleSystem || raw > SonoraPlayerFontStyleSerif) {
        return SonoraPlayerFontStyleSystem;
    }
    return (SonoraPlayerFontStyle)raw;
}

static UIColor *SonoraPlayerBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.blackColor;
        }
        return UIColor.systemBackgroundColor;
    }];
}

static UIColor *SonoraPlayerPrimaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return UIColor.labelColor;
    }];
}

static UIColor *SonoraPlayerSecondaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.66];
        }
        return UIColor.secondaryLabelColor;
    }];
}

static UIColor *SonoraPlayerTimelineMaxColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.24];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.22];
    }];
}

static UIFont *SonoraHeadlineFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIFont *SonoraNewYorkFont(CGFloat size, UIFontWeight weight) {
    NSArray<NSString *> *candidates = @[@"NewYork-Regular"];
    if (weight >= UIFontWeightBold) {
        candidates = @[@"NewYork-Bold", @"NewYork-Semibold", @"NewYork-Medium", @"NewYork-Regular"];
    } else if (weight >= UIFontWeightSemibold) {
        candidates = @[@"NewYork-Semibold", @"NewYork-Medium", @"NewYork-Regular"];
    } else if (weight >= UIFontWeightMedium) {
        candidates = @[@"NewYork-Medium", @"NewYork-Regular"];
    }

    for (NSString *name in candidates) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font != nil) {
            return font;
        }
    }

    UIFontDescriptor *baseDescriptor = [UIFont systemFontOfSize:size weight:weight].fontDescriptor;
    UIFontDescriptor *serifDescriptor = [baseDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
    if (serifDescriptor != nil) {
        UIFont *font = [UIFont fontWithDescriptor:serifDescriptor size:size];
        if (font != nil) {
            return font;
        }
    }
    return [UIFont systemFontOfSize:size weight:weight];
}

static UIFont *SonoraPlayerFontForStyle(SonoraPlayerFontStyle style, CGFloat size, UIFontWeight weight) {
    switch (style) {
        case SonoraPlayerFontStyleSerif: {
            return SonoraNewYorkFont(size, weight);
        }
        case SonoraPlayerFontStyleSystem:
        default:
            return [UIFont systemFontOfSize:size weight:weight];
    }
}

static SonoraPlayerArtworkStyle SonoraPlayerArtworkStyleFromDefaults(void) {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsArtworkStyleKey];
    if (raw < SonoraPlayerArtworkStyleSquare || raw > SonoraPlayerArtworkStyleRounded) {
        return SonoraPlayerArtworkStyleRounded;
    }
    return (SonoraPlayerArtworkStyle)raw;
}

static BOOL SonoraArtworkEqualizerEnabledFromDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SonoraSettingsArtworkEqualizerKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SonoraSettingsArtworkEqualizerKey];
}

static CGFloat SonoraArtworkCornerRadiusForStyle(SonoraPlayerArtworkStyle style, CGFloat width) {
    switch (style) {
        case SonoraPlayerArtworkStyleSquare:
            return 0.0;
        case SonoraPlayerArtworkStyleRounded:
        default:
            return MIN(26.0, width * 0.08);
    }
}

static UIImage *SonoraLovelySongsCoverImage(CGSize size) {
    UIImage *sourceImage = [UIImage imageNamed:@"LovelyCover"];
    if (sourceImage == nil) {
        sourceImage = [UIImage imageNamed:@"lovely-cover"];
    }

    CGSize normalizedSize = CGSizeMake(MAX(size.width, 240.0), MAX(size.height, 240.0));
    if (sourceImage == nil || sourceImage.size.width <= 1.0 || sourceImage.size.height <= 1.0) {
        sourceImage = [UIImage systemImageNamed:@"heart.fill"];
        if (sourceImage == nil) {
            return nil;
        }
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [[UIColor colorWithRed:0.78 green:0.03 blue:0.08 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0.0, 0.0, normalizedSize.width, normalizedSize.height));

        CGFloat scale = MAX(normalizedSize.width / sourceImage.size.width,
                            normalizedSize.height / sourceImage.size.height);
        CGSize drawSize = CGSizeMake(sourceImage.size.width * scale, sourceImage.size.height * scale);
        CGRect drawRect = CGRectMake((normalizedSize.width - drawSize.width) * 0.5,
                                     (normalizedSize.height - drawSize.height) * 0.5,
                                     drawSize.width,
                                     drawSize.height);
        [sourceImage drawInRect:drawRect];
    }];
}

static UIView *SonoraWhiteSectionTitleLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return UIColor.blackColor;
    }];
    label.font = SonoraHeadlineFont(28.0);
    [label sizeToFit];

    if (@available(iOS 26.0, *)) {
        CGFloat horizontalPadding = 10.0;
        CGFloat width = ceil(CGRectGetWidth(label.bounds)) + (horizontalPadding * 2.0);
        CGFloat height = ceil(CGRectGetHeight(label.bounds));
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
        label.frame = CGRectMake(horizontalPadding, 0.0, ceil(CGRectGetWidth(label.bounds)), height);
        [container addSubview:label];
        return container;
    }
    return label;
}

static void SonoraPresentAlert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static NSString *SonoraNormalizedSearchText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.lowercaseString ?: @"";
}

static NSString *SonoraTrimmedStringValue(id value) {
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed ?: @"";
}

static NSString *SonoraMiniStreamingConfigValue(NSString *key, NSString *fallback) {
    NSString *environmentValue = SonoraTrimmedStringValue(NSProcessInfo.processInfo.environment[key]);
    if (environmentValue.length > 0) {
        return environmentValue;
    }

    NSString *plistValue = SonoraTrimmedStringValue([NSBundle.mainBundle objectForInfoDictionaryKey:key]);
    if (plistValue.length > 0) {
        return plistValue;
    }

    return SonoraTrimmedStringValue(fallback);
}

static NSString *SonoraSanitizedFileComponent(NSString *value) {
    NSString *trimmed = SonoraTrimmedStringValue(value);
    if (trimmed.length == 0) {
        return @"";
    }

    NSMutableCharacterSet *invalid = [NSMutableCharacterSet characterSetWithCharactersInString:@"<>:\"/\\|?*"];
    [invalid formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:invalid];
    NSString *joined = [parts componentsJoinedByString:@""];
    NSString *normalizedSpaces = [joined stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([normalizedSpaces containsString:@"  "]) {
        normalizedSpaces = [normalizedSpaces stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return normalizedSpaces ?: @"";
}

static NSSet<NSString *> *SonoraSupportedAudioExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"aiff", @"flac", @"caf"]];
    });
    return extensions;
}

static UIImage *SonoraMiniStreamingPlaceholderArtwork(NSString *seed, CGSize size) {
    CGSize normalizedSize = CGSizeMake(MAX(size.width, 180.0), MAX(size.height, 180.0));
    NSString *title = SonoraTrimmedStringValue(seed);
    if (title.length == 0) {
        title = @"Track";
    }

    NSUInteger hash = title.hash;
    CGFloat hue = ((CGFloat)(hash % 360u)) / 360.0f;
    UIColor *baseColor = [UIColor colorWithHue:hue saturation:0.52 brightness:0.82 alpha:1.0];
    UIColor *secondaryColor = [UIColor colorWithHue:fmod(hue + 0.12, 1.0) saturation:0.58 brightness:0.64 alpha:1.0];

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect rect = CGRectMake(0, 0, normalizedSize.width, normalizedSize.height);
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = rect;
        gradient.startPoint = CGPointMake(0.0, 0.0);
        gradient.endPoint = CGPointMake(1.0, 1.0);
        gradient.colors = @[
            (__bridge id)baseColor.CGColor,
            (__bridge id)secondaryColor.CGColor
        ];
        [gradient renderInContext:UIGraphicsGetCurrentContext()];

        NSString *symbol = [title substringToIndex:MIN((NSUInteger)1, title.length)].uppercaseString;
        NSDictionary<NSAttributedStringKey, id> *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:normalizedSize.width * 0.34 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        CGSize textSize = [symbol sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake((normalizedSize.width - textSize.width) * 0.5,
                                     (normalizedSize.height - textSize.height) * 0.5,
                                     textSize.width,
                                     textSize.height);
        [symbol drawInRect:textRect withAttributes:attributes];
    }];
}

static NSError *SonoraMiniStreamingError(NSInteger code, NSString *message) {
    NSString *resolvedMessage = message.length > 0 ? message : @"Unexpected mini streaming error.";
    return [NSError errorWithDomain:SonoraMiniStreamingErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey: resolvedMessage
                           }];
}

static BOOL SonoraTrackMatchesSearchQuery(SonoraTrack *track, NSString *query) {
    if (query.length == 0) {
        return YES;
    }

    NSString *title = track.title.lowercaseString ?: @"";
    NSString *artist = track.artist.lowercaseString ?: @"";
    NSString *fileName = track.fileName.lowercaseString ?: @"";
    return ([title containsString:query] ||
            [artist containsString:query] ||
            [fileName containsString:query]);
}

static NSArray<SonoraTrack *> *SonoraFilterTracksByQuery(NSArray<SonoraTrack *> *tracks, NSString *query) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (normalizedQuery.length == 0) {
        return tracks ?: @[];
    }

    NSMutableArray<SonoraTrack *> *filtered = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (SonoraTrackMatchesSearchQuery(track, normalizedQuery)) {
            [filtered addObject:track];
        }
    }
    return [filtered copy];
}

static NSInteger SonoraIndexOfTrackByIdentifier(NSArray<SonoraTrack *> *tracks, NSString *trackID) {
    if (trackID.length == 0 || tracks.count == 0) {
        return NSNotFound;
    }

    for (NSUInteger idx = 0; idx < tracks.count; idx += 1) {
        SonoraTrack *track = tracks[idx];
        if ([track.identifier isEqualToString:trackID]) {
            return (NSInteger)idx;
        }
    }
    return NSNotFound;
}

static BOOL SonoraTrackQueuesMatchByIdentifier(NSArray<SonoraTrack *> *first, NSArray<SonoraTrack *> *second) {
    if (first.count != second.count) {
        return NO;
    }

    for (NSUInteger idx = 0; idx < first.count; idx += 1) {
        SonoraTrack *leftTrack = first[idx];
        SonoraTrack *rightTrack = second[idx];
        if (![leftTrack.identifier isEqualToString:rightTrack.identifier]) {
            return NO;
        }
    }
    return YES;
}

static NSArray<SonoraPlaylist *> *SonoraFilterPlaylistsByQuery(NSArray<SonoraPlaylist *> *playlists, NSString *query) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (normalizedQuery.length == 0) {
        return playlists ?: @[];
    }

    NSMutableArray<SonoraPlaylist *> *filtered = [NSMutableArray arrayWithCapacity:playlists.count];
    for (SonoraPlaylist *playlist in playlists) {
        NSString *name = playlist.name.lowercaseString ?: @"";
        if ([name containsString:normalizedQuery]) {
            [filtered addObject:playlist];
        }
    }
    return [filtered copy];
}

static NSArray<NSString *> *SonoraArtistParticipantsFromText(NSString *artistText) {
    NSString *trimmed = [artistText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *chunks = [trimmed componentsSeparatedByString:@","];
    for (NSString *chunk in chunks) {
        NSString *value = [chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = SonoraNormalizedSearchText(value);
        if (key.length == 0 || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [values addObject:value];
    }
    return values;
}

static NSArray<NSDictionary<NSString *, id> *> *SonoraBuildArtistSearchResults(NSArray<SonoraTrack *> *tracks,
                                                                            NSString *query,
                                                                            NSUInteger limit) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *artistsByKey = [NSMutableDictionary dictionary];
    for (SonoraTrack *track in tracks) {
        NSArray<NSString *> *participants = SonoraArtistParticipantsFromText(track.artist ?: @"");
        for (NSString *participant in participants) {
            NSString *key = SonoraNormalizedSearchText(participant);
            if (normalizedQuery.length > 0 && ![key containsString:normalizedQuery]) {
                continue;
            }

            NSMutableDictionary<NSString *, id> *entry = artistsByKey[key];
            if (entry == nil) {
                entry = [@{
                    @"key": key,
                    @"title": participant,
                    @"tracks": [NSMutableArray array]
                } mutableCopy];
                artistsByKey[key] = entry;
            }
            NSMutableArray<SonoraTrack *> *matchedTracks = entry[@"tracks"];
            if (matchedTracks == nil) {
                matchedTracks = [NSMutableArray array];
                entry[@"tracks"] = matchedTracks;
            }
            BOOL alreadyIncluded = NO;
            for (SonoraTrack *existing in matchedTracks) {
                if ([existing.identifier isEqualToString:track.identifier]) {
                    alreadyIncluded = YES;
                    break;
                }
            }
            if (!alreadyIncluded) {
                [matchedTracks addObject:track];
            }
        }
    }

    NSArray<NSDictionary<NSString *, id> *> *sorted = [artistsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> * _Nonnull left,
                                                                                                                             NSDictionary<NSString *,id> * _Nonnull right) {
        NSArray *leftTracks = left[@"tracks"];
        NSArray *rightTracks = right[@"tracks"];
        if (leftTracks.count > rightTracks.count) {
            return NSOrderedAscending;
        }
        if (leftTracks.count < rightTracks.count) {
            return NSOrderedDescending;
        }
        NSString *leftTitle = left[@"title"] ?: @"";
        NSString *rightTitle = right[@"title"] ?: @"";
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

@interface SonoraMiniStreamingTrack : NSObject

@property (nonatomic, copy) NSString *trackID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artists;
@property (nonatomic, copy) NSString *spotifyURL;
@property (nonatomic, copy) NSString *artworkURL;
@property (nonatomic, assign) NSTimeInterval duration;

@end

@implementation SonoraMiniStreamingTrack
@end

@interface SonoraMiniStreamingArtist : NSObject

@property (nonatomic, copy) NSString *artistID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *artworkURL;

@end

@implementation SonoraMiniStreamingArtist
@end

typedef void (^SonoraMiniStreamingSearchCompletion)(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error);
typedef void (^SonoraMiniStreamingArtistSearchCompletion)(NSArray<SonoraMiniStreamingArtist *> *artists, NSError * _Nullable error);
typedef void (^SonoraMiniStreamingResolveCompletion)(NSDictionary<NSString *, id> * _Nullable payload, NSError * _Nullable error);

@interface SonoraMiniStreamingClient : NSObject

@property (nonatomic, copy) NSString *backendBaseURL;
@property (nonatomic, copy) NSString *spotifyClientID;
@property (nonatomic, copy) NSString *spotifyClientSecret;
@property (nonatomic, copy) NSString *rapidAPIHost;
@property (nonatomic, copy) NSString *rapidAPIKey;
@property (nonatomic, copy) NSString *brokerRapidAPIHost;
@property (nonatomic, copy) NSString *brokerRapidAPIKey;
@property (nonatomic, assign) NSTimeInterval brokerCredentialFetchedAt;
@property (nonatomic, assign) BOOL artistsSectionEnabled;
@property (nonatomic, copy) NSString *spotifyAccessToken;
@property (nonatomic, strong, nullable) NSDate *spotifyTokenExpiresAt;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentSearchTask;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentArtistSearchTask;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentArtistTopTracksTask;

- (BOOL)isConfigured;
- (void)searchTracks:(NSString *)query
               limit:(NSUInteger)limit
          completion:(SonoraMiniStreamingSearchCompletion)completion;
- (void)searchArtists:(NSString *)query
                limit:(NSUInteger)limit
           completion:(SonoraMiniStreamingArtistSearchCompletion)completion;
- (void)fetchTopTracksForArtistID:(NSString *)artistID
                            limit:(NSUInteger)limit
                       completion:(SonoraMiniStreamingSearchCompletion)completion;
- (void)resolveDownloadForTrackID:(NSString *)trackID
                       completion:(SonoraMiniStreamingResolveCompletion)completion;

@end

@implementation SonoraMiniStreamingClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _backendBaseURL = SonoraMiniStreamingConfigValue(@"BACKEND_BASE_URL", SonoraMiniStreamingDefaultBackendBaseURLString);
        if (_backendBaseURL.length == 0) {
            _backendBaseURL = SonoraMiniStreamingDefaultBackendBaseURLString;
        }
        while (_backendBaseURL.length > 1 && [_backendBaseURL hasSuffix:@"/"]) {
            _backendBaseURL = [_backendBaseURL substringToIndex:_backendBaseURL.length - 1];
        }
        _spotifyClientID = SonoraMiniStreamingConfigValue(@"SPOTIFY_CLIENT_ID", @"");
        _spotifyClientSecret = SonoraMiniStreamingConfigValue(@"SPOTIFY_CLIENT_SECRET", @"");
        _rapidAPIHost = SonoraMiniStreamingConfigValue(@"RAPIDAPI_HOST", SonoraMiniStreamingDefaultRapidAPIHost);
        _rapidAPIKey = SonoraMiniStreamingConfigValue(@"RAPIDAPI_KEY", @"");
        _brokerRapidAPIHost = SonoraMiniStreamingConfigValue(@"BROKER_RAPIDAPI_HOST", @"");
        _brokerRapidAPIKey = SonoraMiniStreamingConfigValue(@"BROKER_RAPIDAPI_KEY", @"");
        _brokerCredentialFetchedAt = 0.0;
        _artistsSectionEnabled = YES;
        _spotifyAccessToken = @"";
        _spotifyTokenExpiresAt = nil;
        _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    }
    return self;
}

- (BOOL)isConfigured {
    return (self.backendBaseURL.length > 0);
}

- (void)dispatchOnMainQueue:(dispatch_block_t)block {
    if (block == nil) {
        return;
    }
    if (NSThread.isMainThread) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

- (nullable NSURL *)miniStreamingBackendURLForPath:(NSString *)path
                                         queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems {
    NSString *base = SonoraTrimmedStringValue(self.backendBaseURL);
    if (base.length == 0) {
        return nil;
    }
    if (![base hasPrefix:@"http://"] && ![base hasPrefix:@"https://"]) {
        base = [NSString stringWithFormat:@"https://%@", base];
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:base];
    if (components == nil) {
        return nil;
    }

    NSString *normalizedPath = SonoraTrimmedStringValue(path);
    if (normalizedPath.length == 0) {
        normalizedPath = @"/";
    }
    if (![normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [@"/" stringByAppendingString:normalizedPath];
    }

    NSString *basePath = SonoraTrimmedStringValue(components.path);
    if (basePath.length > 0 && ![basePath isEqualToString:@"/"]) {
        NSString *trimmedBasePath = [basePath hasSuffix:@"/"] ? [basePath substringToIndex:basePath.length - 1] : basePath;
        normalizedPath = [trimmedBasePath stringByAppendingString:normalizedPath];
    }
    components.path = normalizedPath;
    components.queryItems = queryItems.count > 0 ? queryItems : nil;
    return components.URL;
}

- (NSDictionary *)miniStreamingPayloadNodeFromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) {
        return @{};
    }
    NSDictionary *dataNode = [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
    NSDictionary *nestedDataNode = [dataNode[@"data"] isKindOfClass:NSDictionary.class] ? dataNode[@"data"] : nil;
    return nestedDataNode ?: dataNode ?: json;
}

- (NSString *)miniStreamingErrorMessageFromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) {
        return @"";
    }

    NSString *message = SonoraTrimmedStringValue(json[@"message"]);
    if (message.length > 0) {
        return message;
    }

    id errorNode = json[@"error"];
    if ([errorNode isKindOfClass:NSString.class]) {
        message = SonoraTrimmedStringValue(errorNode);
        if (message.length > 0) {
            return message;
        }
    } else if ([errorNode isKindOfClass:NSDictionary.class]) {
        message = SonoraTrimmedStringValue(((NSDictionary *)errorNode)[@"message"]);
        if (message.length > 0) {
            return message;
        }
    }

    NSDictionary *dataNode = [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
    if (dataNode != nil) {
        message = SonoraTrimmedStringValue(dataNode[@"message"]);
        if (message.length == 0) {
            message = SonoraTrimmedStringValue(dataNode[@"error"]);
        }
        if (message.length == 0) {
            NSDictionary *nestedDataNode = [dataNode[@"data"] isKindOfClass:NSDictionary.class] ? dataNode[@"data"] : nil;
            message = SonoraTrimmedStringValue(nestedDataNode[@"message"]);
            if (message.length == 0) {
                message = SonoraTrimmedStringValue(nestedDataNode[@"error"]);
            }
        }
    }
    return message ?: @"";
}

- (void)markRapidAPIKeyBlockedForQuotaIfNeeded:(NSString *)apiKey {
    NSString *normalizedKey = SonoraTrimmedStringValue(apiKey);
    if (normalizedKey.length == 0) {
        return;
    }

    NSURL *url = [NSURL URLWithString:SonoraMiniStreamingKeyBrokerMarkURLString];
    if (url == nil) {
        return;
    }

    NSDictionary *payload = @{
        @"key": normalizedKey,
        @"minutes": @(1440),
        @"reason": @"manual"
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (body.length == 0) {
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 8.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    request.HTTPBody = body;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    [task resume];
}

- (void)fetchBrokerCredentialWithCompletion:(void (^)(NSString * _Nullable host, NSString * _Nullable key))completion {
    NSString *cachedHost = SonoraTrimmedStringValue(self.brokerRapidAPIHost);
    NSString *cachedKey = SonoraTrimmedStringValue(self.brokerRapidAPIKey);
    if (cachedHost.length == 0) {
        cachedHost = SonoraTrimmedStringValue(self.rapidAPIHost);
    }
    if (cachedKey.length == 0) {
        cachedKey = SonoraTrimmedStringValue(self.rapidAPIKey);
    }
    [self dispatchOnMainQueue:^{
        completion(cachedHost, cachedKey);
    }];
}

- (BOOL)canUseSpotifyFallback {
    return (SonoraTrimmedStringValue(self.spotifyClientID).length > 0 &&
            SonoraTrimmedStringValue(self.spotifyClientSecret).length > 0);
}

- (BOOL)canUseRapidResolveFallback {
    NSString *cachedHost = SonoraTrimmedStringValue(self.brokerRapidAPIHost);
    if (cachedHost.length == 0) {
        cachedHost = SonoraTrimmedStringValue(self.rapidAPIHost);
    }
    NSString *cachedKey = SonoraTrimmedStringValue(self.brokerRapidAPIKey);
    if (cachedKey.length == 0) {
        cachedKey = SonoraTrimmedStringValue(self.rapidAPIKey);
    }
    return (cachedHost.length > 0 && cachedKey.length > 0);
}

- (void)fetchSpotifyAccessTokenWithCompletion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion {
    NSTimeInterval ttl = [self.spotifyTokenExpiresAt timeIntervalSinceNow];
    if (self.spotifyAccessToken.length > 0 && ttl > 20.0) {
        completion(self.spotifyAccessToken, nil);
        return;
    }

    if (self.spotifyClientID.length == 0 || self.spotifyClientSecret.length == 0) {
        completion(nil, SonoraMiniStreamingError(1001, @"Spotify credentials are missing."));
        return;
    }

    NSURL *url = [NSURL URLWithString:SonoraMiniStreamingSpotifyTokenURLString];
    if (url == nil) {
        completion(nil, SonoraMiniStreamingError(1002, @"Spotify token URL is invalid."));
        return;
    }

    NSString *credentials = [NSString stringWithFormat:@"%@:%@", self.spotifyClientID, self.spotifyClientSecret];
    NSString *base64Auth = [[credentials dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20.0;
    request.HTTPBody = [@"grant_type=client_credentials" dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Basic %@", base64Auth] forHTTPHeaderField:@"Authorization"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data,
                                                                     NSURLResponse * _Nullable response,
                                                                     NSError * _Nullable error) {
        if (error != nil) {
            completion(nil, SonoraMiniStreamingError(1003, error.localizedDescription));
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger statusCode = http.statusCode;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)object;
            }
        }

        if (statusCode < 200 || statusCode >= 300) {
            NSString *message = SonoraTrimmedStringValue(json[@"error_description"]);
            if (message.length == 0) {
                message = SonoraTrimmedStringValue(json[@"error"]);
            }
            if (message.length == 0) {
                message = [NSString stringWithFormat:@"Spotify token request failed (%ld).", (long)statusCode];
            }
            completion(nil, SonoraMiniStreamingError(1004, message));
            return;
        }

        NSString *token = SonoraTrimmedStringValue(json[@"access_token"]);
        if (token.length == 0) {
            completion(nil, SonoraMiniStreamingError(1005, @"Spotify token response has no access_token."));
            return;
        }

        NSInteger expiresIn = [json[@"expires_in"] respondsToSelector:@selector(integerValue)] ? [json[@"expires_in"] integerValue] : 3600;
        if (expiresIn < 30) {
            expiresIn = 30;
        }

        self.spotifyAccessToken = token;
        self.spotifyTokenExpiresAt = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)MAX(30, expiresIn - 30)];
        completion(token, nil);
    }];
    [task resume];
}

- (nullable SonoraMiniStreamingTrack *)miniStreamingTrackFromSpotifyItem:(NSDictionary *)item {
    if (![item isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *trackID = SonoraTrimmedStringValue(item[@"id"]);
    if (trackID.length == 0) {
        return nil;
    }

    SonoraMiniStreamingTrack *track = [[SonoraMiniStreamingTrack alloc] init];
    track.trackID = trackID;
    track.title = SonoraTrimmedStringValue(item[@"name"]);
    if (track.title.length == 0) {
        track.title = @"Unknown track";
    }

    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    NSArray *artistItems = [item[@"artists"] isKindOfClass:NSArray.class] ? item[@"artists"] : @[];
    for (id artistObject in artistItems) {
        if (![artistObject isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *name = SonoraTrimmedStringValue(((NSDictionary *)artistObject)[@"name"]);
        if (name.length > 0) {
            [artists addObject:name];
        }
    }
    track.artists = artists.count > 0 ? [artists componentsJoinedByString:@", "] : @"Unknown artist";

    NSDictionary *externalURLs = [item[@"external_urls"] isKindOfClass:NSDictionary.class] ? item[@"external_urls"] : nil;
    NSString *spotifyURL = SonoraTrimmedStringValue(externalURLs[@"spotify"]);
    if (spotifyURL.length == 0) {
        spotifyURL = [NSString stringWithFormat:@"https://open.spotify.com/track/%@", trackID];
    }
    track.spotifyURL = spotifyURL;

    NSDictionary *albumNode = [item[@"album"] isKindOfClass:NSDictionary.class] ? item[@"album"] : nil;
    NSArray *images = [albumNode[@"images"] isKindOfClass:NSArray.class] ? albumNode[@"images"] : @[];
    NSString *artworkURL = @"";
    NSInteger bestWidth = -1;
    for (id imageObject in images) {
        if (![imageObject isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *imageNode = (NSDictionary *)imageObject;
        NSString *candidateURL = SonoraTrimmedStringValue(imageNode[@"url"]);
        if (candidateURL.length == 0) {
            continue;
        }
        NSInteger width = [imageNode[@"width"] respondsToSelector:@selector(integerValue)] ? [imageNode[@"width"] integerValue] : 0;
        if (width > bestWidth) {
            bestWidth = width;
            artworkURL = candidateURL;
        } else if (bestWidth < 0 && artworkURL.length == 0) {
            artworkURL = candidateURL;
        }
    }
    track.artworkURL = artworkURL ?: @"";

    NSInteger durationMS = [item[@"duration_ms"] respondsToSelector:@selector(integerValue)] ? [item[@"duration_ms"] integerValue] : 0;
    track.duration = durationMS > 0 ? ((NSTimeInterval)durationMS / 1000.0) : 0.0;
    return track;
}

- (void)searchTracks:(NSString *)query
               limit:(NSUInteger)limit
          completion:(SonoraMiniStreamingSearchCompletion)completion {
    NSString *normalizedQuery = SonoraTrimmedStringValue(query);
    if (normalizedQuery.length == 0) {
        [self dispatchOnMainQueue:^{
            completion(@[], nil);
        }];
        return;
    }

    if (self.currentSearchTask != nil) {
        [self.currentSearchTask cancel];
        self.currentSearchTask = nil;
    }

    NSUInteger boundedLimit = MIN(MAX(limit, (NSUInteger)1), (NSUInteger)50);
    BOOL canUseSpotifyFallback = [self canUseSpotifyFallback];
    __weak typeof(self) weakSelf = self;
    void (^startSpotifyFallback)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf fetchSpotifyAccessTokenWithCompletion:^(NSString * _Nullable token, NSError * _Nullable tokenError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            if (tokenError != nil || token.length == 0) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], tokenError ?: SonoraMiniStreamingError(1102, @"Cannot fetch Spotify token."));
                }];
                return;
            }

            NSURLComponents *components = [NSURLComponents componentsWithString:SonoraMiniStreamingSpotifySearchURLString];
            components.queryItems = @[
                [NSURLQueryItem queryItemWithName:@"q" value:normalizedQuery],
                [NSURLQueryItem queryItemWithName:@"type" value:@"track"],
                [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)boundedLimit]]
            ];

            NSURL *searchURL = components.URL;
            if (searchURL == nil) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1103, @"Spotify search URL is invalid."));
                }];
                return;
            }

            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:searchURL];
            request.HTTPMethod = @"GET";
            request.timeoutInterval = 20.0;
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

            innerSelf.currentSearchTask = [innerSelf.session dataTaskWithRequest:request
                                                               completionHandler:^(NSData * _Nullable data,
                                                                                   NSURLResponse * _Nullable response,
                                                                                   NSError * _Nullable error) {
                if (error != nil) {
                    if (error.code == NSURLErrorCancelled) {
                        return;
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1104, error.localizedDescription));
                    }];
                    return;
                }

                NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                NSInteger statusCode = http.statusCode;
                NSDictionary *json = nil;
                if (data.length > 0) {
                    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([object isKindOfClass:NSDictionary.class]) {
                        json = (NSDictionary *)object;
                    }
                }

                if (statusCode < 200 || statusCode >= 300) {
                    NSString *message = nil;
                    id errorNode = json[@"error"];
                    if ([errorNode isKindOfClass:NSDictionary.class]) {
                        message = SonoraTrimmedStringValue(errorNode[@"message"]);
                    }
                    if (message.length == 0) {
                        message = [NSString stringWithFormat:@"Spotify search failed (%ld).", (long)statusCode];
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1105, message));
                    }];
                    return;
                }

                NSDictionary *payloadNode = [innerSelf miniStreamingPayloadNodeFromJSON:json ?: @{}];
                id artistsFlagValue = payloadNode[@"artistsEnabled"];
                if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                    artistsFlagValue = payloadNode[@"showArtists"];
                }
                if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                    id artistsNode = payloadNode[@"artists"];
                    if (![artistsNode isKindOfClass:NSDictionary.class] && ![artistsNode isKindOfClass:NSArray.class]) {
                        artistsFlagValue = artistsNode;
                    }
                }
                if ((artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) &&
                    [json isKindOfClass:NSDictionary.class]) {
                    artistsFlagValue = json[@"artistsEnabled"];
                    if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                        artistsFlagValue = json[@"showArtists"];
                    }
                    if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                        id artistsNode = json[@"artists"];
                        if (![artistsNode isKindOfClass:NSDictionary.class] && ![artistsNode isKindOfClass:NSArray.class]) {
                            artistsFlagValue = artistsNode;
                        }
                    }
                }

                BOOL hasArtistsFlag = NO;
                BOOL artistsEnabled = innerSelf.artistsSectionEnabled;
                if ([artistsFlagValue respondsToSelector:@selector(boolValue)] &&
                    ![artistsFlagValue isKindOfClass:NSString.class]) {
                    hasArtistsFlag = YES;
                    artistsEnabled = [artistsFlagValue boolValue];
                } else if ([artistsFlagValue isKindOfClass:NSString.class]) {
                    NSString *normalizedArtistsFlag = SonoraTrimmedStringValue(artistsFlagValue).lowercaseString;
                    if (normalizedArtistsFlag.length > 0) {
                        if ([normalizedArtistsFlag isEqualToString:@"no"] ||
                            [normalizedArtistsFlag isEqualToString:@"false"] ||
                            [normalizedArtistsFlag isEqualToString:@"off"] ||
                            [normalizedArtistsFlag isEqualToString:@"0"] ||
                            [normalizedArtistsFlag isEqualToString:@"disabled"] ||
                            [normalizedArtistsFlag isEqualToString:@"hide"] ||
                            [normalizedArtistsFlag isEqualToString:@"hidden"]) {
                            hasArtistsFlag = YES;
                            artistsEnabled = NO;
                        } else if ([normalizedArtistsFlag isEqualToString:@"yes"] ||
                                   [normalizedArtistsFlag isEqualToString:@"true"] ||
                                   [normalizedArtistsFlag isEqualToString:@"on"] ||
                                   [normalizedArtistsFlag isEqualToString:@"1"] ||
                                   [normalizedArtistsFlag isEqualToString:@"enabled"] ||
                                   [normalizedArtistsFlag isEqualToString:@"show"] ||
                                   [normalizedArtistsFlag isEqualToString:@"visible"]) {
                            hasArtistsFlag = YES;
                            artistsEnabled = YES;
                        }
                    }
                }
                if (hasArtistsFlag) {
                    innerSelf.artistsSectionEnabled = artistsEnabled;
                }

                NSDictionary *tracksNode = [json[@"tracks"] isKindOfClass:NSDictionary.class] ? json[@"tracks"] : nil;
                NSArray *items = [tracksNode[@"items"] isKindOfClass:NSArray.class] ? tracksNode[@"items"] : @[];
                NSMutableArray<SonoraMiniStreamingTrack *> *results = [NSMutableArray arrayWithCapacity:items.count];
                for (id itemObject in items) {
                    SonoraMiniStreamingTrack *track = [innerSelf miniStreamingTrackFromSpotifyItem:itemObject];
                    if (track != nil) {
                        [results addObject:track];
                    }
                }

                [innerSelf dispatchOnMainQueue:^{
                    completion([results copy], nil);
                }];
            }];
            [innerSelf.currentSearchTask resume];
        }];
    };

    NSURL *backendSearchURL = [self miniStreamingBackendURLForPath:SonoraMiniStreamingBackendSearchPath
                                                         queryItems:@[
        [NSURLQueryItem queryItemWithName:@"q" value:normalizedQuery],
        [NSURLQueryItem queryItemWithName:@"type" value:@"track"],
        [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)boundedLimit]]
    ]];
    if (![self isConfigured] || backendSearchURL == nil) {
        if (canUseSpotifyFallback) {
            startSpotifyFallback();
        } else {
            NSInteger errorCode = [self isConfigured] ? 1103 : 1101;
            NSString *message = [self isConfigured] ? @"Mini streaming backend URL is invalid." : @"Mini streaming backend is missing.";
            [self dispatchOnMainQueue:^{
                completion(@[], SonoraMiniStreamingError(errorCode, message));
            }];
        }
        return;
    }

    NSMutableURLRequest *backendRequest = [NSMutableURLRequest requestWithURL:backendSearchURL];
    backendRequest.HTTPMethod = @"GET";
    backendRequest.timeoutInterval = 20.0;
    [backendRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [backendRequest setValue:@"Sonora-iOS/1.0" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakBackendSelf = self;
    self.currentSearchTask = [self.session dataTaskWithRequest:backendRequest
                                             completionHandler:^(NSData * _Nullable data,
                                                                 NSURLResponse * _Nullable response,
                                                                 NSError * _Nullable error) {
        __strong typeof(weakBackendSelf) strongBackendSelf = weakBackendSelf;
        if (strongBackendSelf == nil) {
            return;
        }
        if (error != nil) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1104, error.localizedDescription));
                }];
            }
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger statusCode = http.statusCode;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)object;
            }
        }

        if (statusCode < 200 || statusCode >= 300) {
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                NSString *message = [strongBackendSelf miniStreamingErrorMessageFromJSON:json ?: @{}];
                if (statusCode == 451) {
                    message = @"Требуется VPN из-за региональных ограничений (451).";
                } else if (message.length == 0) {
                    message = [NSString stringWithFormat:@"Mini streaming search failed (%ld).", (long)statusCode];
                }
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1105, message));
                }];
            }
            return;
        }

        NSDictionary *payloadNode = [strongBackendSelf miniStreamingPayloadNodeFromJSON:json ?: @{}];
        NSDictionary *tracksNode = [payloadNode[@"tracks"] isKindOfClass:NSDictionary.class] ? payloadNode[@"tracks"] : nil;
        NSArray *items = [tracksNode[@"items"] isKindOfClass:NSArray.class] ? tracksNode[@"items"] : @[];
        NSMutableArray<SonoraMiniStreamingTrack *> *results = [NSMutableArray arrayWithCapacity:items.count];
        for (id itemObject in items) {
            SonoraMiniStreamingTrack *track = [strongBackendSelf miniStreamingTrackFromSpotifyItem:itemObject];
            if (track != nil) {
                [results addObject:track];
            }
        }

        [strongBackendSelf dispatchOnMainQueue:^{
            completion([results copy], nil);
        }];
    }];
    [self.currentSearchTask resume];
}

- (void)searchArtists:(NSString *)query
                limit:(NSUInteger)limit
           completion:(SonoraMiniStreamingArtistSearchCompletion)completion {
    NSString *normalizedQuery = SonoraTrimmedStringValue(query);
    if (normalizedQuery.length == 0) {
        [self dispatchOnMainQueue:^{
            completion(@[], nil);
        }];
        return;
    }

    if (self.currentArtistSearchTask != nil) {
        [self.currentArtistSearchTask cancel];
        self.currentArtistSearchTask = nil;
    }

    NSUInteger boundedLimit = MIN(MAX(limit, (NSUInteger)1), (NSUInteger)50);
    BOOL canUseSpotifyFallback = [self canUseSpotifyFallback];
    __weak typeof(self) weakSelf = self;
    void (^startSpotifyFallback)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf fetchSpotifyAccessTokenWithCompletion:^(NSString * _Nullable token, NSError * _Nullable tokenError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            if (tokenError != nil || token.length == 0) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], tokenError ?: SonoraMiniStreamingError(1112, @"Cannot fetch Spotify token."));
                }];
                return;
            }

            NSURLComponents *components = [NSURLComponents componentsWithString:SonoraMiniStreamingSpotifySearchURLString];
            components.queryItems = @[
                [NSURLQueryItem queryItemWithName:@"q" value:normalizedQuery],
                [NSURLQueryItem queryItemWithName:@"type" value:@"artist"],
                [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)boundedLimit]]
            ];

            NSURL *searchURL = components.URL;
            if (searchURL == nil) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1113, @"Spotify artist search URL is invalid."));
                }];
                return;
            }

            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:searchURL];
            request.HTTPMethod = @"GET";
            request.timeoutInterval = 20.0;
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

            innerSelf.currentArtistSearchTask = [innerSelf.session dataTaskWithRequest:request
                                                                     completionHandler:^(NSData * _Nullable data,
                                                                                         NSURLResponse * _Nullable response,
                                                                                         NSError * _Nullable error) {
                if (error != nil) {
                    if (error.code == NSURLErrorCancelled) {
                        return;
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1114, error.localizedDescription));
                    }];
                    return;
                }

                NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                NSInteger statusCode = http.statusCode;
                NSDictionary *json = nil;
                if (data.length > 0) {
                    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([object isKindOfClass:NSDictionary.class]) {
                        json = (NSDictionary *)object;
                    }
                }

                if (statusCode < 200 || statusCode >= 300) {
                    NSString *message = nil;
                    id errorNode = json[@"error"];
                    if ([errorNode isKindOfClass:NSDictionary.class]) {
                        message = SonoraTrimmedStringValue(errorNode[@"message"]);
                    }
                    if (message.length == 0) {
                        message = [NSString stringWithFormat:@"Spotify artist search failed (%ld).", (long)statusCode];
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1115, message));
                    }];
                    return;
                }

                NSDictionary *artistsNode = [json[@"artists"] isKindOfClass:NSDictionary.class] ? json[@"artists"] : nil;
                NSArray *items = [artistsNode[@"items"] isKindOfClass:NSArray.class] ? artistsNode[@"items"] : @[];
                NSMutableArray<SonoraMiniStreamingArtist *> *results = [NSMutableArray arrayWithCapacity:items.count];
                for (id itemObject in items) {
                    if (![itemObject isKindOfClass:NSDictionary.class]) {
                        continue;
                    }
                    NSDictionary *item = (NSDictionary *)itemObject;
                    NSString *artistID = SonoraTrimmedStringValue(item[@"id"]);
                    if (artistID.length == 0) {
                        continue;
                    }

                    SonoraMiniStreamingArtist *artist = [[SonoraMiniStreamingArtist alloc] init];
                    artist.artistID = artistID;
                    artist.name = SonoraTrimmedStringValue(item[@"name"]);
                    if (artist.name.length == 0) {
                        artist.name = @"Unknown artist";
                    }

                    NSArray *images = [item[@"images"] isKindOfClass:NSArray.class] ? item[@"images"] : @[];
                    NSString *artworkURL = @"";
                    NSInteger bestWidth = -1;
                    for (id imageObject in images) {
                        if (![imageObject isKindOfClass:NSDictionary.class]) {
                            continue;
                        }
                        NSDictionary *imageNode = (NSDictionary *)imageObject;
                        NSString *candidateURL = SonoraTrimmedStringValue(imageNode[@"url"]);
                        if (candidateURL.length == 0) {
                            continue;
                        }
                        NSInteger width = [imageNode[@"width"] respondsToSelector:@selector(integerValue)] ? [imageNode[@"width"] integerValue] : 0;
                        if (width > bestWidth) {
                            bestWidth = width;
                            artworkURL = candidateURL;
                        } else if (bestWidth < 0 && artworkURL.length == 0) {
                            artworkURL = candidateURL;
                        }
                    }
                    artist.artworkURL = artworkURL ?: @"";
                    [results addObject:artist];
                }

                [innerSelf dispatchOnMainQueue:^{
                    completion([results copy], nil);
                }];
            }];
            [innerSelf.currentArtistSearchTask resume];
        }];
    };

    NSURL *backendSearchURL = [self miniStreamingBackendURLForPath:SonoraMiniStreamingBackendSearchPath
                                                         queryItems:@[
        [NSURLQueryItem queryItemWithName:@"q" value:normalizedQuery],
        [NSURLQueryItem queryItemWithName:@"type" value:@"artist"],
        [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)boundedLimit]]
    ]];
    if (![self isConfigured] || backendSearchURL == nil) {
        if (canUseSpotifyFallback) {
            startSpotifyFallback();
        } else {
            NSInteger errorCode = [self isConfigured] ? 1113 : 1111;
            NSString *message = [self isConfigured] ? @"Mini streaming backend URL is invalid." : @"Mini streaming backend is missing.";
            [self dispatchOnMainQueue:^{
                completion(@[], SonoraMiniStreamingError(errorCode, message));
            }];
        }
        return;
    }

    NSMutableURLRequest *backendRequest = [NSMutableURLRequest requestWithURL:backendSearchURL];
    backendRequest.HTTPMethod = @"GET";
    backendRequest.timeoutInterval = 20.0;
    [backendRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [backendRequest setValue:@"Sonora-iOS/1.0" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakBackendSelf = self;
    self.currentArtistSearchTask = [self.session dataTaskWithRequest:backendRequest
                                                    completionHandler:^(NSData * _Nullable data,
                                                                        NSURLResponse * _Nullable response,
                                                                        NSError * _Nullable error) {
        __strong typeof(weakBackendSelf) strongBackendSelf = weakBackendSelf;
        if (strongBackendSelf == nil) {
            return;
        }
        if (error != nil) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1114, error.localizedDescription));
                }];
            }
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger statusCode = http.statusCode;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)object;
            }
        }

        if (statusCode < 200 || statusCode >= 300) {
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                NSString *message = [strongBackendSelf miniStreamingErrorMessageFromJSON:json ?: @{}];
                if (statusCode == 451) {
                    message = @"Требуется VPN из-за региональных ограничений (451).";
                } else if (message.length == 0) {
                    message = [NSString stringWithFormat:@"Mini streaming artist search failed (%ld).", (long)statusCode];
                }
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1115, message));
                }];
            }
            return;
        }

        NSDictionary *payloadNode = [strongBackendSelf miniStreamingPayloadNodeFromJSON:json ?: @{}];
        id artistsFlagValue = payloadNode[@"artistsEnabled"];
        if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
            artistsFlagValue = payloadNode[@"showArtists"];
        }
        if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
            id artistsNodeRaw = payloadNode[@"artists"];
            if (![artistsNodeRaw isKindOfClass:NSDictionary.class] && ![artistsNodeRaw isKindOfClass:NSArray.class]) {
                artistsFlagValue = artistsNodeRaw;
            }
        }
        if ((artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) &&
            [json isKindOfClass:NSDictionary.class]) {
            artistsFlagValue = json[@"artistsEnabled"];
            if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                artistsFlagValue = json[@"showArtists"];
            }
            if (artistsFlagValue == nil || [artistsFlagValue isKindOfClass:NSNull.class]) {
                id artistsNodeRaw = json[@"artists"];
                if (![artistsNodeRaw isKindOfClass:NSDictionary.class] && ![artistsNodeRaw isKindOfClass:NSArray.class]) {
                    artistsFlagValue = artistsNodeRaw;
                }
            }
        }

        BOOL hasArtistsFlag = NO;
        BOOL artistsEnabled = strongBackendSelf.artistsSectionEnabled;
        if ([artistsFlagValue respondsToSelector:@selector(boolValue)] &&
            ![artistsFlagValue isKindOfClass:NSString.class]) {
            hasArtistsFlag = YES;
            artistsEnabled = [artistsFlagValue boolValue];
        } else if ([artistsFlagValue isKindOfClass:NSString.class]) {
            NSString *normalizedArtistsFlag = SonoraTrimmedStringValue(artistsFlagValue).lowercaseString;
            if (normalizedArtistsFlag.length > 0) {
                if ([normalizedArtistsFlag isEqualToString:@"no"] ||
                    [normalizedArtistsFlag isEqualToString:@"false"] ||
                    [normalizedArtistsFlag isEqualToString:@"off"] ||
                    [normalizedArtistsFlag isEqualToString:@"0"] ||
                    [normalizedArtistsFlag isEqualToString:@"disabled"] ||
                    [normalizedArtistsFlag isEqualToString:@"hide"] ||
                    [normalizedArtistsFlag isEqualToString:@"hidden"]) {
                    hasArtistsFlag = YES;
                    artistsEnabled = NO;
                } else if ([normalizedArtistsFlag isEqualToString:@"yes"] ||
                           [normalizedArtistsFlag isEqualToString:@"true"] ||
                           [normalizedArtistsFlag isEqualToString:@"on"] ||
                           [normalizedArtistsFlag isEqualToString:@"1"] ||
                           [normalizedArtistsFlag isEqualToString:@"enabled"] ||
                           [normalizedArtistsFlag isEqualToString:@"show"] ||
                           [normalizedArtistsFlag isEqualToString:@"visible"]) {
                    hasArtistsFlag = YES;
                    artistsEnabled = YES;
                }
            }
        }
        if (hasArtistsFlag) {
            strongBackendSelf.artistsSectionEnabled = artistsEnabled;
        }

        NSDictionary *artistsNode = [payloadNode[@"artists"] isKindOfClass:NSDictionary.class] ? payloadNode[@"artists"] : nil;
        NSArray *items = [artistsNode[@"items"] isKindOfClass:NSArray.class] ? artistsNode[@"items"] : @[];
        NSMutableArray<SonoraMiniStreamingArtist *> *results = [NSMutableArray arrayWithCapacity:items.count];
        for (id itemObject in items) {
            if (![itemObject isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSDictionary *item = (NSDictionary *)itemObject;
            NSString *artistID = SonoraTrimmedStringValue(item[@"id"]);
            if (artistID.length == 0) {
                continue;
            }

            SonoraMiniStreamingArtist *artist = [[SonoraMiniStreamingArtist alloc] init];
            artist.artistID = artistID;
            artist.name = SonoraTrimmedStringValue(item[@"name"]);
            if (artist.name.length == 0) {
                artist.name = @"Unknown artist";
            }

            NSArray *images = [item[@"images"] isKindOfClass:NSArray.class] ? item[@"images"] : @[];
            NSString *artworkURL = @"";
            NSInteger bestWidth = -1;
            for (id imageObject in images) {
                if (![imageObject isKindOfClass:NSDictionary.class]) {
                    continue;
                }
                NSDictionary *imageNode = (NSDictionary *)imageObject;
                NSString *candidateURL = SonoraTrimmedStringValue(imageNode[@"url"]);
                if (candidateURL.length == 0) {
                    continue;
                }
                NSInteger width = [imageNode[@"width"] respondsToSelector:@selector(integerValue)] ? [imageNode[@"width"] integerValue] : 0;
                if (width > bestWidth) {
                    bestWidth = width;
                    artworkURL = candidateURL;
                } else if (bestWidth < 0 && artworkURL.length == 0) {
                    artworkURL = candidateURL;
                }
            }
            artist.artworkURL = artworkURL ?: @"";
            [results addObject:artist];
        }

        [strongBackendSelf dispatchOnMainQueue:^{
            completion([results copy], nil);
        }];
    }];
    [self.currentArtistSearchTask resume];
}

- (void)fetchTopTracksForArtistID:(NSString *)artistID
                            limit:(NSUInteger)limit
                       completion:(SonoraMiniStreamingSearchCompletion)completion {
    NSString *normalizedArtistID = SonoraTrimmedStringValue(artistID);
    if (normalizedArtistID.length == 0) {
        [self dispatchOnMainQueue:^{
            completion(@[], SonoraMiniStreamingError(1121, @"Artist ID is empty."));
        }];
        return;
    }

    if (self.currentArtistTopTracksTask != nil) {
        [self.currentArtistTopTracksTask cancel];
        self.currentArtistTopTracksTask = nil;
    }

    NSUInteger boundedLimit = (limit == 0 || limit == NSUIntegerMax) ? 100 : MIN(MAX(limit, (NSUInteger)1), (NSUInteger)100);
    BOOL canUseSpotifyFallback = [self canUseSpotifyFallback];
    __weak typeof(self) weakSelf = self;
    void (^startSpotifyFallback)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf fetchSpotifyAccessTokenWithCompletion:^(NSString * _Nullable token, NSError * _Nullable tokenError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            if (tokenError != nil || token.length == 0) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], tokenError ?: SonoraMiniStreamingError(1123, @"Cannot fetch Spotify token."));
                }];
                return;
            }

            NSString *encodedFallbackArtistID = [normalizedArtistID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
            NSString *fallbackURLString = [NSString stringWithFormat:@"https://api.spotify.com/v1/artists/%@/top-tracks?market=US",
                                           encodedFallbackArtistID ?: @""];
            NSURL *fallbackURL = [NSURL URLWithString:fallbackURLString];
            if (fallbackURL == nil) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1124, @"Spotify top tracks URL is invalid."));
                }];
                return;
            }

            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:fallbackURL];
            request.HTTPMethod = @"GET";
            request.timeoutInterval = 20.0;
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

            innerSelf.currentArtistTopTracksTask = [innerSelf.session dataTaskWithRequest:request
                                                                         completionHandler:^(NSData * _Nullable data,
                                                                                             NSURLResponse * _Nullable response,
                                                                                             NSError * _Nullable error) {
                if (error != nil) {
                    if (error.code == NSURLErrorCancelled) {
                        return;
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1125, error.localizedDescription));
                    }];
                    return;
                }

                NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                NSInteger statusCode = http.statusCode;
                NSDictionary *json = nil;
                if (data.length > 0) {
                    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([object isKindOfClass:NSDictionary.class]) {
                        json = (NSDictionary *)object;
                    }
                }

                if (statusCode < 200 || statusCode >= 300) {
                    NSString *message = nil;
                    id errorNode = json[@"error"];
                    if ([errorNode isKindOfClass:NSDictionary.class]) {
                        message = SonoraTrimmedStringValue(errorNode[@"message"]);
                    }
                    if (message.length == 0) {
                        message = [NSString stringWithFormat:@"Spotify artist tracks failed (%ld).", (long)statusCode];
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(@[], SonoraMiniStreamingError(1126, message));
                    }];
                    return;
                }

                NSArray *items = [json[@"tracks"] isKindOfClass:NSArray.class] ? json[@"tracks"] : @[];
                NSMutableArray<SonoraMiniStreamingTrack *> *results = [NSMutableArray arrayWithCapacity:items.count];
                for (id itemObject in items) {
                    SonoraMiniStreamingTrack *track = [innerSelf miniStreamingTrackFromSpotifyItem:itemObject];
                    if (track == nil || track.trackID.length == 0) {
                        continue;
                    }
                    [results addObject:track];
                    if (results.count >= boundedLimit) {
                        break;
                    }
                }

                [innerSelf dispatchOnMainQueue:^{
                    completion([results copy], nil);
                }];
            }];
            [innerSelf.currentArtistTopTracksTask resume];
        }];
    };

    NSString *encodedArtistID = [normalizedArtistID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *topTracksPath = [NSString stringWithFormat:@"/api/spotify/artists/%@/top-tracks", encodedArtistID ?: @""];
    NSURL *backendTopTracksURL = [self miniStreamingBackendURLForPath:topTracksPath
                                                            queryItems:@[
        [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)boundedLimit]]
    ]];
    if (![self isConfigured] || backendTopTracksURL == nil) {
        if (canUseSpotifyFallback) {
            startSpotifyFallback();
        } else {
            NSInteger errorCode = [self isConfigured] ? 1124 : 1122;
            NSString *message = [self isConfigured] ? @"Mini streaming backend URL is invalid." : @"Mini streaming backend is missing.";
            [self dispatchOnMainQueue:^{
                completion(@[], SonoraMiniStreamingError(errorCode, message));
            }];
        }
        return;
    }

    NSMutableURLRequest *backendRequest = [NSMutableURLRequest requestWithURL:backendTopTracksURL];
    backendRequest.HTTPMethod = @"GET";
    backendRequest.timeoutInterval = 20.0;
    [backendRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [backendRequest setValue:@"Sonora-iOS/1.0" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakBackendSelf = self;
    self.currentArtistTopTracksTask = [self.session dataTaskWithRequest:backendRequest
                                                       completionHandler:^(NSData * _Nullable data,
                                                                           NSURLResponse * _Nullable response,
                                                                           NSError * _Nullable error) {
        __strong typeof(weakBackendSelf) strongBackendSelf = weakBackendSelf;
        if (strongBackendSelf == nil) {
            return;
        }
        if (error != nil) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1125, error.localizedDescription));
                }];
            }
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger statusCode = http.statusCode;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)object;
            }
        }

        if (statusCode < 200 || statusCode >= 300) {
            if (canUseSpotifyFallback) {
                startSpotifyFallback();
            } else {
                NSString *message = [strongBackendSelf miniStreamingErrorMessageFromJSON:json ?: @{}];
                if (statusCode == 451) {
                    message = @"Требуется VPN из-за региональных ограничений (451).";
                } else if (message.length == 0) {
                    message = [NSString stringWithFormat:@"Mini streaming top tracks failed (%ld).", (long)statusCode];
                }
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(@[], SonoraMiniStreamingError(1126, message));
                }];
            }
            return;
        }

        NSDictionary *payloadNode = [strongBackendSelf miniStreamingPayloadNodeFromJSON:json ?: @{}];
        NSArray *items = [payloadNode[@"tracks"] isKindOfClass:NSArray.class] ? payloadNode[@"tracks"] : nil;
        if (items.count == 0) {
            NSDictionary *tracksNode = [payloadNode[@"tracks"] isKindOfClass:NSDictionary.class] ? payloadNode[@"tracks"] : nil;
            if (tracksNode != nil) {
                items = [tracksNode[@"items"] isKindOfClass:NSArray.class] ? tracksNode[@"items"] : nil;
            }
        }
        if (items.count == 0) {
            items = [payloadNode[@"items"] isKindOfClass:NSArray.class] ? payloadNode[@"items"] : @[];
        }

        NSMutableArray<SonoraMiniStreamingTrack *> *results = [NSMutableArray arrayWithCapacity:items.count];
        for (id itemObject in items) {
            SonoraMiniStreamingTrack *track = [strongBackendSelf miniStreamingTrackFromSpotifyItem:itemObject];
            if (track == nil || track.trackID.length == 0) {
                continue;
            }
            [results addObject:track];
            if (results.count >= boundedLimit) {
                break;
            }
        }

        [strongBackendSelf dispatchOnMainQueue:^{
            completion([results copy], nil);
        }];
    }];
    [self.currentArtistTopTracksTask resume];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)rapidResolveCandidatesForTrackURL:(NSString *)trackURL
                                                                             brokerHost:(NSString *)brokerHost
                                                                              brokerKey:(NSString *)brokerKey {
    NSString *normalizedTrackURL = SonoraTrimmedStringValue(trackURL);
    if (normalizedTrackURL.length == 0) {
        return @[];
    }

    NSString *musicRequestURL = @"";
    NSURLComponents *musicComponents = [NSURLComponents componentsWithString:SonoraMiniStreamingRapidAPIDownloadURLString];
    if (musicComponents != nil) {
        musicComponents.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"link" value:normalizedTrackURL]
        ];
        musicRequestURL = SonoraTrimmedStringValue(musicComponents.URL.absoluteString);
    }

    NSString *downloader9RequestURL = @"";
    NSURLComponents *downloader9Components = [NSURLComponents componentsWithString:SonoraMiniStreamingRapidAPIDownloader9URLString];
    if (downloader9Components != nil) {
        downloader9Components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"songId" value:normalizedTrackURL]
        ];
        downloader9RequestURL = SonoraTrimmedStringValue(downloader9Components.URL.absoluteString);
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seenSignatures = [NSMutableSet set];
    void (^addCandidate)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *provider,
                                                                              NSString *requestURL,
                                                                              NSString *host,
                                                                              NSString *apiKey) {
        NSString *normalizedRequestURL = SonoraTrimmedStringValue(requestURL);
        NSString *normalizedCandidateHost = SonoraTrimmedStringValue(host);
        NSString *normalizedCandidateKey = SonoraTrimmedStringValue(apiKey);
        if (normalizedRequestURL.length == 0 || normalizedCandidateHost.length == 0 || normalizedCandidateKey.length == 0) {
            return;
        }
        NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@",
                               provider ?: @"",
                               normalizedCandidateHost,
                               normalizedCandidateKey,
                               normalizedRequestURL];
        if ([seenSignatures containsObject:signature]) {
            return;
        }
        [seenSignatures addObject:signature];
        [candidates addObject:@{
            @"provider": provider ?: @"",
            @"url": normalizedRequestURL,
            @"host": normalizedCandidateHost,
            @"key": normalizedCandidateKey
        }];
    };

    addCandidate(@"downloader9", downloader9RequestURL, brokerHost, brokerKey);

    return candidates;
}

- (BOOL)isRapidQuotaMessage:(NSString *)message {
    NSString *normalizedMessage = SonoraTrimmedStringValue(message).lowercaseString;
    if (normalizedMessage.length == 0) {
        return NO;
    }
    return ([normalizedMessage containsString:@"daily quota"] ||
            [normalizedMessage containsString:@"quota exceeded"] ||
            [normalizedMessage containsString:@"exceeded"]);
}

- (nullable NSDictionary<NSString *, id> *)miniStreamingPayloadFromRapidJSON:(NSDictionary *)json
                                                                      trackID:(NSString *)trackID {
    if (![json isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    BOOL success = YES;
    if ([json[@"success"] respondsToSelector:@selector(boolValue)]) {
        success = [json[@"success"] boolValue];
    }

    NSDictionary *levelOneNode = [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : json;
    if (levelOneNode == nil) {
        return nil;
    }
    if ([levelOneNode[@"success"] respondsToSelector:@selector(boolValue)]) {
        success = [levelOneNode[@"success"] boolValue];
    }
    NSDictionary *dataNode = [levelOneNode[@"data"] isKindOfClass:NSDictionary.class] ? levelOneNode[@"data"] : levelOneNode;
    if ([dataNode[@"success"] respondsToSelector:@selector(boolValue)]) {
        success = [dataNode[@"success"] boolValue];
    }

    NSArray *medias = [dataNode[@"medias"] isKindOfClass:NSArray.class] ? dataNode[@"medias"] : @[];
    NSString *downloadLink = @"";
    NSString *resolvedExtension = @"";
    for (id mediaObject in medias) {
        if (![mediaObject isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *mediaNode = (NSDictionary *)mediaObject;
        NSString *candidateURL = SonoraTrimmedStringValue(mediaNode[@"url"]);
        if (candidateURL.length == 0) {
            continue;
        }

        if (downloadLink.length == 0) {
            downloadLink = candidateURL;
            resolvedExtension = SonoraTrimmedStringValue(mediaNode[@"extension"]);
        }

        NSString *type = SonoraTrimmedStringValue(mediaNode[@"type"]).lowercaseString;
        NSString *ext = SonoraTrimmedStringValue(mediaNode[@"extension"]).lowercaseString;
        if ([type isEqualToString:@"audio"] || [ext isEqualToString:@"mp3"]) {
            downloadLink = candidateURL;
            resolvedExtension = SonoraTrimmedStringValue(mediaNode[@"extension"]);
            break;
        }
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(dataNode[@"downloadLink"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(dataNode[@"mediaUrl"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(dataNode[@"link"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(dataNode[@"url"]);
    }
    if (!success || downloadLink.length == 0) {
        return nil;
    }

    NSString *resolvedTitle = SonoraTrimmedStringValue(dataNode[@"title"]);
    NSString *resolvedArtist = SonoraTrimmedStringValue(dataNode[@"author"]);
    if (resolvedArtist.length == 0) {
        resolvedArtist = SonoraTrimmedStringValue(dataNode[@"artist"]);
    }
    NSString *resolvedAlbum = SonoraTrimmedStringValue(dataNode[@"album"]);
    if (resolvedAlbum.length == 0) {
        resolvedAlbum = SonoraTrimmedStringValue(dataNode[@"source"]);
    }
    NSString *resolvedArtwork = SonoraTrimmedStringValue(dataNode[@"thumbnail"]);
    if (resolvedArtwork.length == 0) {
        resolvedArtwork = SonoraTrimmedStringValue(dataNode[@"cover"]);
    }
    if (resolvedExtension.length == 0) {
        NSURL *downloadURL = [NSURL URLWithString:downloadLink];
        resolvedExtension = SonoraTrimmedStringValue(downloadURL.pathExtension).lowercaseString;
    }
    if (resolvedExtension.length == 0) {
        resolvedExtension = @"mp3";
    }

    return @{
        @"trackID": SonoraTrimmedStringValue(trackID),
        @"title": resolvedTitle,
        @"artist": resolvedArtist,
        @"album": resolvedAlbum,
        @"artworkURL": resolvedArtwork,
        @"extension": resolvedExtension,
        @"downloadLink": downloadLink
    };
}

- (void)resolveDownloadForTrackID:(NSString *)trackID
                       completion:(SonoraMiniStreamingResolveCompletion)completion {
    NSString *normalizedTrackID = SonoraTrimmedStringValue(trackID);
    if (normalizedTrackID.length == 0) {
        [self dispatchOnMainQueue:^{
            completion(nil, SonoraMiniStreamingError(1201, @"Track ID is empty."));
        }];
        return;
    }

    BOOL canUseRapidFallback = [self canUseRapidResolveFallback];
    NSString *spotifyTrackURL = [NSString stringWithFormat:@"https://open.spotify.com/track/%@", normalizedTrackID];
    __weak typeof(self) weakSelf = self;
    void (^startRapidFallback)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf fetchBrokerCredentialWithCompletion:^(NSString * _Nullable brokerHost, NSString * _Nullable brokerKey) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            NSArray<NSDictionary<NSString *, NSString *> *> *candidates = [innerSelf rapidResolveCandidatesForTrackURL:spotifyTrackURL
                                                                                                              brokerHost:brokerHost ?: @""
                                                                                                               brokerKey:brokerKey ?: @""];
            if (candidates.count == 0) {
                [innerSelf dispatchOnMainQueue:^{
                    completion(nil, SonoraMiniStreamingError(1203, SonoraMiniStreamingInstallUnavailableMessage));
                }];
                return;
            }

            __block NSString *lastMessage = @"";
            __block BOOL sawDailyQuota = NO;
            __block void (^attemptCandidateAtIndex)(NSUInteger) = nil;
            attemptCandidateAtIndex = ^(NSUInteger index) {
                if (index >= candidates.count) {
                    NSString *finalMessage = sawDailyQuota ? SonoraMiniStreamingInstallUnavailableMessage : lastMessage;
                    if (finalMessage.length == 0) {
                        finalMessage = SonoraMiniStreamingInstallUnavailableMessage;
                    }
                    [innerSelf dispatchOnMainQueue:^{
                        completion(nil, SonoraMiniStreamingError(1206, finalMessage));
                    }];
                    return;
                }

                NSDictionary<NSString *, NSString *> *candidate = candidates[index];
                NSURL *requestURL = [NSURL URLWithString:SonoraTrimmedStringValue(candidate[@"url"])];
                NSString *requestHost = SonoraTrimmedStringValue(candidate[@"host"]);
                NSString *requestKey = SonoraTrimmedStringValue(candidate[@"key"]);
                if (requestURL == nil || requestHost.length == 0 || requestKey.length == 0) {
                    attemptCandidateAtIndex(index + 1);
                    return;
                }

                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
                request.HTTPMethod = @"GET";
                request.timeoutInterval = 30.0;
                [request setValue:requestHost forHTTPHeaderField:@"x-rapidapi-host"];
                [request setValue:requestKey forHTTPHeaderField:@"x-rapidapi-key"];

                NSURLSessionDataTask *task = [innerSelf.session dataTaskWithRequest:request
                                                                   completionHandler:^(NSData * _Nullable data,
                                                                                       NSURLResponse * _Nullable response,
                                                                                       NSError * _Nullable error) {
                    if (error != nil) {
                        NSString *message = SonoraTrimmedStringValue(error.localizedDescription);
                        NSString *lowerMessage = message.lowercaseString;
                        if ([lowerMessage containsString:@"unable to resolve host"] ||
                            [lowerMessage containsString:@"no address associated with hostname"] ||
                            [lowerMessage containsString:@"could not resolve host"]) {
                            message = @"Требуется VPN из-за региональных ограничений (451).";
                        }
                        if (message.length > 0) {
                            lastMessage = message;
                        }
                        attemptCandidateAtIndex(index + 1);
                        return;
                    }

                    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                    NSInteger statusCode = http.statusCode;
                    NSDictionary *json = nil;
                    if (data.length > 0) {
                        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        if ([object isKindOfClass:NSDictionary.class]) {
                            json = (NSDictionary *)object;
                        }
                    }

                    NSDictionary<NSString *, id> *payload = [innerSelf miniStreamingPayloadFromRapidJSON:json trackID:normalizedTrackID];
                    if (statusCode >= 200 && statusCode < 300 && payload != nil) {
                        [innerSelf dispatchOnMainQueue:^{
                            completion(payload, nil);
                        }];
                        return;
                    }

                    NSString *message = SonoraTrimmedStringValue(json[@"message"]);
                    if (message.length == 0) {
                        message = SonoraTrimmedStringValue(json[@"error"]);
                    }
                    if (statusCode == 451) {
                        message = @"Требуется VPN из-за региональных ограничений (451).";
                    } else if (message.length == 0 && (statusCode < 200 || statusCode >= 300)) {
                        message = [NSString stringWithFormat:@"RapidAPI request failed (%ld).", (long)statusCode];
                    } else if (message.length == 0 && payload == nil) {
                        message = @"RapidAPI did not return media url.";
                    }
                    if (message.length > 0) {
                        lastMessage = message;
                        if ([innerSelf isRapidQuotaMessage:message]) {
                            sawDailyQuota = YES;
                            [innerSelf markRapidAPIKeyBlockedForQuotaIfNeeded:requestKey];
                        }
                    }
                    attemptCandidateAtIndex(index + 1);
                }];
                [task resume];
            };

            attemptCandidateAtIndex(0);
        }];
    };

    NSString *backendSpotifyTrackURL = [NSString stringWithFormat:@"https://open.spotify.com/track/%@", normalizedTrackID];
    NSURL *backendDownloadURL = [self miniStreamingBackendURLForPath:SonoraMiniStreamingBackendDownloadPath
                                                           queryItems:@[
        [NSURLQueryItem queryItemWithName:@"trackId" value:normalizedTrackID],
        [NSURLQueryItem queryItemWithName:@"trackUrl" value:backendSpotifyTrackURL]
    ]];
    if (![self isConfigured] || backendDownloadURL == nil) {
        if (canUseRapidFallback) {
            startRapidFallback();
        } else {
            NSInteger errorCode = [self isConfigured] ? 1203 : 1202;
            NSString *message = [self isConfigured] ? @"Mini streaming backend URL is invalid." : @"Mini streaming backend is missing.";
            [self dispatchOnMainQueue:^{
                completion(nil, SonoraMiniStreamingError(errorCode, message));
            }];
        }
        return;
    }

    NSMutableURLRequest *backendRequest = [NSMutableURLRequest requestWithURL:backendDownloadURL];
    backendRequest.HTTPMethod = @"GET";
    backendRequest.timeoutInterval = 30.0;
    [backendRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [backendRequest setValue:@"Sonora-iOS/1.0" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakBackendSelf = self;
    NSURLSessionDataTask *backendTask = [self.session dataTaskWithRequest:backendRequest
                                                         completionHandler:^(NSData * _Nullable data,
                                                                             NSURLResponse * _Nullable response,
                                                                             NSError * _Nullable error) {
        __strong typeof(weakBackendSelf) strongBackendSelf = weakBackendSelf;
        if (strongBackendSelf == nil) {
            return;
        }

        if (error != nil) {
            NSString *message = SonoraTrimmedStringValue(error.localizedDescription);
            NSString *lowerMessage = message.lowercaseString;
            if ([lowerMessage containsString:@"unable to resolve host"] ||
                [lowerMessage containsString:@"no address associated with hostname"] ||
                [lowerMessage containsString:@"could not resolve host"]) {
                message = @"Требуется VPN из-за региональных ограничений (451).";
            }
            if (message.length == 0) {
                message = SonoraMiniStreamingInstallUnavailableMessage;
            }
            if (canUseRapidFallback) {
                startRapidFallback();
            } else {
                [strongBackendSelf dispatchOnMainQueue:^{
                    completion(nil, SonoraMiniStreamingError(1204, message));
                }];
            }
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger statusCode = http.statusCode;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)object;
            }
        }

        NSDictionary<NSString *, id> *payload = [strongBackendSelf miniStreamingPayloadFromRapidJSON:(json ?: @{}) trackID:normalizedTrackID];
        if (statusCode >= 200 && statusCode < 300 && payload != nil) {
            [strongBackendSelf dispatchOnMainQueue:^{
                completion(payload, nil);
            }];
            return;
        }

        NSString *message = [strongBackendSelf miniStreamingErrorMessageFromJSON:json ?: @{}];
        if (statusCode == 451) {
            message = @"Требуется VPN из-за региональных ограничений (451).";
        } else if (message.length == 0 && (statusCode < 200 || statusCode >= 300)) {
            message = [NSString stringWithFormat:@"RapidAPI request failed (%ld).", (long)statusCode];
        } else if (message.length == 0 && payload == nil) {
            message = @"RapidAPI did not return media url.";
        }
        if ([strongBackendSelf isRapidQuotaMessage:message]) {
            message = SonoraMiniStreamingInstallUnavailableMessage;
        }
        if (message.length == 0) {
            message = SonoraMiniStreamingInstallUnavailableMessage;
        }

        if (canUseRapidFallback) {
            startRapidFallback();
        } else {
            [strongBackendSelf dispatchOnMainQueue:^{
                completion(nil, SonoraMiniStreamingError(1206, message));
            }];
        }
    }];
    [backendTask resume];
}

@end

typedef void (^SonoraMiniStreamingInstallHandler)(SonoraMiniStreamingTrack *track,
                                                  NSArray<SonoraMiniStreamingTrack *> *queue,
                                                  NSInteger startIndex,
                                                  UIImage * _Nullable artwork);

@interface SonoraMiniStreamingArtistViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithArtist:(SonoraMiniStreamingArtist *)artist
                        client:(SonoraMiniStreamingClient *)client
                installHandler:(SonoraMiniStreamingInstallHandler)installHandler;

@end

@interface SonoraMiniStreamingArtistViewController ()

@property (nonatomic, strong) SonoraMiniStreamingArtist *artist;
@property (nonatomic, strong) SonoraMiniStreamingClient *client;
@property (nonatomic, copy) SonoraMiniStreamingInstallHandler installHandler;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *tracks;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *artworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingArtworkURLs;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, assign) BOOL compactTitleVisible;

@end

@implementation SonoraMiniStreamingArtistViewController

- (instancetype)initWithArtist:(SonoraMiniStreamingArtist *)artist
                        client:(SonoraMiniStreamingClient *)client
                installHandler:(SonoraMiniStreamingInstallHandler)installHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _artist = artist;
        _client = client;
        _installHandler = [installHandler copy];
        _tracks = @[];
        _artworkCache = [[NSCache alloc] init];
        _artworkCache.countLimit = 64;
        _artworkCache.totalCostLimit = 48 * 1024 * 1024;
        _loadingArtworkURLs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.title = nil;
    self.navigationItem.rightBarButtonItem = nil;
    self.compactTitleVisible = NO;

    [self setupTableView];
    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateSleepButton];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    __weak typeof(self) weakSelf = self;
    [self.client fetchTopTracksForArtistID:self.artist.artistID
                                     limit:0
                                completion:^(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        (void)error;
        strongSelf.tracks = tracks ?: @[];
        NSUInteger prefetchCount = MIN((NSUInteger)strongSelf.tracks.count, (NSUInteger)12);
        for (NSUInteger index = 0; index < prefetchCount; index += 1) {
            [strongSelf loadArtworkIfNeededForTrack:strongSelf.tracks[index]];
        }
        [strongSelf.tableView reloadData];
        [strongSelf updateEmptyState];
        [strongSelf updatePlayButtonState];
        [strongSelf updateSleepButton];
        [strongSelf updateNavigationTitleVisibility];
    }];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
        [self updateSleepButton];
    }
    [self updateNavigationTitleVisibility];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self handlePlaybackChanged];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"MiniStreamingArtistTrackCell"];
    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 374.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat sideControlSize = 46.0;
    CGFloat controlsY = 272.0;
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sideControlSize,
                                   controlsY + (playSize - sideControlSize) * 0.5,
                                   sideControlSize,
                                   sideControlSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = SonoraPlayerPrimaryColor();
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepButton = sleepButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - sideControlSize) * 0.5,
                                     sideControlSize,
                                     sideControlSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = SonoraPlayerPrimaryColor();
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:sleepButton];
    [header addSubview:playButton];
    [header addSubview:shuffleButton];

    return header;
}

- (void)updateHeader {
    NSString *artistName = self.artist.name.length > 0 ? self.artist.name : @"Artist";
    self.nameLabel.text = artistName;

    UIImage *coverImage = [self cachedArtworkForURL:self.artist.artworkURL];
    if (coverImage != nil) {
        self.coverView.image = coverImage;
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.tintColor = nil;
        self.coverView.backgroundColor = UIColor.clearColor;
    } else {
        self.coverView.image = [UIImage systemImageNamed:@"person.fill"];
        self.coverView.contentMode = UIViewContentModeCenter;
        self.coverView.tintColor = UIColor.secondaryLabelColor;
        self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.08];
            }
            return [UIColor colorWithWhite:0.0 alpha:0.04];
        }];
        [self loadArtworkIfNeededForURL:self.artist.artworkURL];
    }
}

- (void)updatePlayButtonState {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL hasTracks = (self.tracks.count > 0);
    BOOL playingArtistTrack = NO;
    for (SonoraMiniStreamingTrack *track in self.tracks) {
        if ([self isPlaybackTrack:currentTrack matchingMiniTrack:track]) {
            playingArtistTrack = YES;
            break;
        }
    }

    self.playButton.enabled = hasTracks;
    self.playButton.alpha = hasTracks ? 1.0 : 0.45;
    NSString *symbolName = (playingArtistTrack && playback.isPlaying) ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                              weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbolName withConfiguration:playConfig] forState:UIControlStateNormal];
}

- (void)updateNavigationTitleVisibility {
    NSString *artistName = self.artist.name.length > 0 ? self.artist.name : @"Artist";
    BOOL shouldShowCompact = (self.tableView.contentOffset.y > 170.0);
    if (shouldShowCompact == self.compactTitleVisible) {
        return;
    }
    self.compactTitleVisible = shouldShowCompact;
    if (shouldShowCompact) {
        self.navigationItem.title = artistName;
    } else {
        self.navigationItem.title = nil;
    }
}

- (void)updateEmptyState {
    if (self.tracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.text = @"No tracks found for this artist.";
    self.tableView.backgroundView = label;
}

- (nullable UIImage *)cachedArtworkForURL:(NSString *)urlString {
    if (urlString.length == 0) {
        return nil;
    }
    return [self.artworkCache objectForKey:urlString];
}

- (nullable UIImage *)cachedArtworkForTrack:(SonoraMiniStreamingTrack *)track {
    return [self cachedArtworkForURL:track.artworkURL];
}

- (void)loadArtworkIfNeededForURL:(NSString *)urlString {
    if (urlString.length == 0 ||
        [self.artworkCache objectForKey:urlString] != nil ||
        [self.loadingArtworkURLs containsObject:urlString]) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    [self.loadingArtworkURLs addObject:urlString];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.loadingArtworkURLs removeObject:urlString];
            if (image != nil) {
                [strongSelf.artworkCache setObject:image forKey:urlString];
                [strongSelf.tableView reloadData];
                [strongSelf updateHeader];
            }
        });
    }];
    [task resume];
}

- (void)loadArtworkIfNeededForTrack:(SonoraMiniStreamingTrack *)track {
    [self loadArtworkIfNeededForURL:track.artworkURL];
}

- (SonoraTrack *)displayTrackForMiniTrack:(SonoraMiniStreamingTrack *)miniTrack artwork:(UIImage * _Nullable)artwork {
    SonoraTrack *track = [[SonoraTrack alloc] init];
    NSString *trackID = SonoraTrimmedStringValue(miniTrack.trackID);
    if (trackID.length == 0) {
        trackID = [NSUUID UUID].UUIDString;
    }
    track.identifier = [NSString stringWithFormat:@"mini-streaming-display-%@", trackID];
    track.title = miniTrack.title.length > 0 ? miniTrack.title : @"Track";
    track.artist = miniTrack.artists.length > 0 ? miniTrack.artists : @"Spotify";
    track.fileName = [NSString stringWithFormat:@"%@.placeholder", trackID];
    track.url = [NSURL fileURLWithPath:@"/dev/null"];
    track.duration = MAX(miniTrack.duration, 0.0);
    track.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(track.title, CGSizeMake(320.0, 320.0));
    return track;
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"No tracks found for this artist.");
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL hasCurrentArtistTrack = NO;
    for (SonoraMiniStreamingTrack *artistTrack in self.tracks) {
        if ([self isPlaybackTrack:playback.currentTrack matchingMiniTrack:artistTrack]) {
            hasCurrentArtistTrack = YES;
            break;
        }
    }
    if (hasCurrentArtistTrack) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    SonoraMiniStreamingTrack *track = self.tracks.firstObject;
    if (track != nil && self.installHandler != nil) {
        UIImage *artwork = [self cachedArtworkForTrack:track];
        self.installHandler(track, self.tracks, 0, artwork);
    }
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"No tracks found for this artist.");
        return;
    }
    if (self.installHandler == nil) {
        return;
    }

    NSMutableArray<SonoraMiniStreamingTrack *> *shuffledQueue = [self.tracks mutableCopy];
    for (NSInteger index = shuffledQueue.count - 1; index > 0; index -= 1) {
        NSInteger randomIndex = arc4random_uniform((u_int32_t)(index + 1));
        [shuffledQueue exchangeObjectAtIndex:(NSUInteger)index withObjectAtIndex:(NSUInteger)randomIndex];
    }
    SonoraMiniStreamingTrack *startTrack = shuffledQueue.firstObject ?: self.tracks.firstObject;
    if (startTrack == nil) {
        return;
    }
    UIImage *artwork = [self cachedArtworkForTrack:startTrack];
    self.installHandler(startTrack, [shuffledQueue copy], 0, artwork);
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepButton];
    });
}

- (void)updateSleepButton {
    if (self.sleepButton == nil) {
        return;
    }

    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    BOOL isActive = sleepTimer.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    UIColor *inactiveColor = SonoraPlayerPrimaryColor();
    self.sleepButton.tintColor = isActive ? SonoraAccentYellowColor() : inactiveColor;
    if (self.shuffleButton != nil) {
        self.shuffleButton.tintColor = inactiveColor;
    }
    self.sleepButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Sleep timer";
}

- (BOOL)isPlaybackTrack:(SonoraTrack * _Nullable)playbackTrack matchingMiniTrack:(SonoraMiniStreamingTrack *)miniTrack {
    if (playbackTrack == nil || miniTrack.trackID.length == 0) {
        return NO;
    }

    NSString *identifier = playbackTrack.identifier ?: @"";
    if ([identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        NSString *trackID = [identifier substringFromIndex:SonoraMiniStreamingPlaceholderPrefix.length];
        return [trackID isEqualToString:miniTrack.trackID];
    }

    NSString *playbackTitle = SonoraNormalizedSearchText(playbackTrack.title ?: @"");
    NSString *miniTitle = SonoraNormalizedSearchText(miniTrack.title ?: @"");
    if (playbackTitle.length == 0 || miniTitle.length == 0 || ![playbackTitle isEqualToString:miniTitle]) {
        return NO;
    }

    NSString *playbackArtist = SonoraNormalizedSearchText(playbackTrack.artist ?: @"");
    NSString *miniArtist = SonoraNormalizedSearchText(miniTrack.artists ?: @"");
    if (miniArtist.length == 0 || playbackArtist.length == 0) {
        return YES;
    }
    return ([playbackArtist containsString:miniArtist] ||
            [miniArtist containsString:playbackArtist]);
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
    [self updatePlayButtonState];
    [self updateSleepButton];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MiniStreamingArtistTrackCell" forIndexPath:indexPath];
    if (indexPath.row >= self.tracks.count) {
        return cell;
    }

    SonoraMiniStreamingTrack *track = self.tracks[indexPath.row];
    UIImage *artwork = [self cachedArtworkForTrack:track];
    [self loadArtworkIfNeededForTrack:track];
    SonoraTrack *displayTrack = [self displayTrackForMiniTrack:track artwork:artwork];
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isCurrent = [self isPlaybackTrack:playback.currentTrack matchingMiniTrack:track];
    [cell configureWithTrack:displayTrack
                   isCurrent:isCurrent
      showsPlaybackIndicator:(isCurrent && playback.isPlaying)];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= self.tracks.count) {
        return;
    }
    SonoraMiniStreamingTrack *track = self.tracks[indexPath.row];
    if (self.installHandler != nil) {
        UIImage *artwork = [self cachedArtworkForTrack:track];
        self.installHandler(track, self.tracks, indexPath.row, artwork);
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateNavigationTitleVisibility];
    }
}

@end

static UISearchController *SonoraBuildSearchController(id<UISearchResultsUpdating> updater, NSString *placeholder) {
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.hidesNavigationBarDuringPresentation = NO;
    searchController.searchResultsUpdater = updater;
    searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    if (placeholder.length > 0) {
        searchController.searchBar.placeholder = placeholder;
    }
    return searchController;
}

static CGFloat SonoraSearchPullDistance(UIScrollView *scrollView) {
    if (scrollView == nil) {
        return 0.0;
    }
    CGFloat topEdge = -scrollView.adjustedContentInset.top;
    return MAX(0.0, topEdge - scrollView.contentOffset.y);
}

static CGFloat const SonoraSearchRevealThreshold = 62.0;
static CGFloat const SonoraSearchDismissThreshold = 40.0;

static BOOL SonoraShouldAttachSearchController(BOOL currentlyAttached,
                                           UISearchController *searchController,
                                           UIScrollView *scrollView,
                                           CGFloat revealThreshold) {
    if (searchController == nil || scrollView == nil) {
        return NO;
    }

    BOOL hasQuery = searchController.searchBar.text.length > 0;
    if (currentlyAttached) {
        if (searchController.isActive || hasQuery) {
            return YES;
        }

        CGFloat topEdge = -scrollView.adjustedContentInset.top;
        BOOL scrolledIntoContent = (scrollView.contentOffset.y > topEdge + SonoraSearchDismissThreshold);
        return !scrolledIntoContent;
    }

    CGFloat pullDistance = SonoraSearchPullDistance(scrollView);
    return (pullDistance >= revealThreshold);
}

static void SonoraApplySearchControllerAttachment(UINavigationItem *navigationItem,
                                              UINavigationBar *navigationBar,
                                              UISearchController *searchController,
                                              BOOL shouldAttach,
                                              BOOL animated) {
    if (navigationItem == nil) {
        return;
    }

    UISearchController *targetController = shouldAttach ? searchController : nil;
    if (navigationItem.searchController == targetController) {
        return;
    }

    if (animated && navigationBar != nil) {
        [UIView transitionWithView:navigationBar
                          duration:0.20
                           options:(UIViewAnimationOptionTransitionCrossDissolve |
                                    UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionBeginFromCurrentState)
                        animations:^{
            navigationItem.searchController = targetController;
            [navigationBar layoutIfNeeded];
        }
                        completion:nil];
        return;
    }

    navigationItem.searchController = targetController;
}

static void SonoraPresentQuickAddTrackToPlaylist(UIViewController *controller,
                                             NSString *trackID,
                                             dispatch_block_t completionHandler) {
    if (controller == nil || trackID.length == 0) {
        return;
    }

    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    NSArray<SonoraPlaylist *> *playlists = SonoraPlaylistStore.sharedStore.playlists;
    if (playlists.count == 0) {
        SonoraPresentAlert(controller, @"No Playlists", @"Create a playlist first.");
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add To Playlist"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (SonoraPlaylist *playlist in playlists) {
        BOOL alreadyContains = [playlist.trackIDs containsObject:trackID];
        NSString *title = playlist.name ?: @"Playlist";
        if (alreadyContains) {
            title = [title stringByAppendingString:@"  ✓"];
        }

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(__unused UIAlertAction * _Nonnull selectedAction) {
            BOOL added = [SonoraPlaylistStore.sharedStore addTrackIDs:@[trackID] toPlaylistID:playlist.playlistID];
            if (!added) {
                SonoraPresentAlert(controller, @"Already Added", @"Track already exists in that playlist.");
                return;
            }
            if (completionHandler != nil) {
                completionHandler();
            }
        }];
        action.enabled = !alreadyContains;
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.sourceView = controller.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(controller.view.bounds),
                                        CGRectGetMidY(controller.view.bounds),
                                        1.0,
                                        1.0);
    }

    [controller presentViewController:sheet animated:YES completion:nil];
}

static UIButton *SonoraPlainIconButton(NSString *symbolName, CGFloat symbolSize, CGFloat weightValue) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageSymbolWeight weight = UIImageSymbolWeightRegular;
    if (weightValue >= 700.0) {
        weight = UIImageSymbolWeightBold;
    } else if (weightValue >= 600.0) {
        weight = UIImageSymbolWeightSemibold;
    }

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:symbolSize
                                                                                           weight:weight];
    [button setImage:[UIImage systemImageNamed:symbolName withConfiguration:config] forState:UIControlStateNormal];
    button.tintColor = SonoraPlayerPrimaryColor();
    button.backgroundColor = UIColor.clearColor;
    return button;
}

static UIImage *SonoraSliderThumbImage(CGFloat diameter, UIColor *color) {
    CGFloat normalizedDiameter = MAX(2.0, diameter);
    CGSize size = CGSizeMake(normalizedDiameter + 2.0, normalizedDiameter + 2.0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect circleRect = CGRectMake(1.0, 1.0, normalizedDiameter, normalizedDiameter);
        [color setFill];
        UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:circleRect];
        [path fill];
    }];
}

static NSString *SonoraSleepTimerRemainingString(NSTimeInterval interval) {
    NSInteger totalSeconds = (NSInteger)llround(MAX(0.0, interval));
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

static NSTimeInterval SonoraSleepTimerDurationFromInput(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return 0.0;
    }

    NSArray<NSString *> *colonParts = [trimmed componentsSeparatedByString:@":"];
    if (colonParts.count == 2 || colonParts.count == 3) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:colonParts.count];
        for (NSString *part in colonParts) {
            NSString *token = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (token.length == 0) {
                return 0.0;
            }

            NSScanner *scanner = [NSScanner scannerWithString:token];
            NSInteger value = 0;
            if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0) {
                return 0.0;
            }
            [values addObject:@(value)];
        }

        NSTimeInterval duration = 0.0;
        if (values.count == 2) {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            if (minutes >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60);
        } else {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            NSInteger seconds = values[2].integerValue;
            if (minutes >= 60 || seconds >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60 + seconds);
        }

        if (duration <= 0.0 || duration > 24.0 * 3600.0) {
            return 0.0;
        }
        return duration;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double minutesValue = 0.0;
    if (![scanner scanDouble:&minutesValue] || !scanner.isAtEnd) {
        return 0.0;
    }

    NSTimeInterval duration = minutesValue * 60.0;
    if (!isfinite(duration) || duration <= 0.0 || duration > 24.0 * 3600.0) {
        return 0.0;
    }
    return duration;
}

static void SonoraPresentCustomSleepTimerAlert(UIViewController *controller, dispatch_block_t updateHandler) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Sleep Timer"
                                                                   message:@"Enter minutes (e.g. 25) or h:mm (e.g. 1:30)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"25 or 1:30";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        NSTimeInterval remaining = SonoraSleepTimerManager.sharedManager.remainingTime;
        if (remaining > 0.0) {
            textField.text = [NSString stringWithFormat:@"%.0f", ceil(remaining / 60.0)];
        }
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Set Timer"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *rawValue = alert.textFields.firstObject.text ?: @"";
        NSTimeInterval duration = SonoraSleepTimerDurationFromInput(rawValue);
        if (duration <= 0.0) {
            SonoraPresentAlert(controller,
                           @"Invalid Time",
                           @"Use minutes (25) or h:mm (1:30). Max is 24 hours.");
            return;
        }

        [SonoraSleepTimerManager.sharedManager startWithDuration:duration];
        if (updateHandler != nil) {
            updateHandler();
        }
    }]];

    [controller presentViewController:alert animated:YES completion:nil];
}

static void SonoraPresentSleepTimerActionSheet(UIViewController *controller,
                                           UIView *sourceView,
                                           dispatch_block_t updateHandler) {
    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    NSString *message = sleepTimer.isActive
    ? [NSString stringWithFormat:@"Will stop playback in %@.", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Stop playback automatically after selected time.";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sleep Timer"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *durations = @[@(15 * 60), @(30 * 60), @(45 * 60), @(60 * 60)];
    for (NSNumber *durationValue in durations) {
        NSInteger minutes = durationValue.integerValue / 60;
        NSString *title = [NSString stringWithFormat:@"%ld min", (long)minutes];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager startWithDuration:durationValue.doubleValue];
            if (updateHandler != nil) {
                updateHandler();
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Custom..."
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SonoraPresentCustomSleepTimerAlert(controller, updateHandler);
        });
    }]];

    if (sleepTimer.isActive) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Turn Off Sleep Timer"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager cancel];
            if (updateHandler != nil) {
                updateHandler();
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        UIView *anchorView = sourceView ?: controller.view;
        popover.sourceView = anchorView;
        popover.sourceRect = anchorView.bounds;
    }

    [controller presentViewController:sheet animated:YES completion:nil];
}

@interface SonoraPlayerViewController : UIViewController
@end

@implementation SonoraSharedPlaylistStore

+ (instancetype)sharedStore {
    static SonoraSharedPlaylistStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SonoraSharedPlaylistStore alloc] init];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [store refreshAllPersistentCachesIfNeeded];
        });
    });
    return store;
}

- (NSArray<NSDictionary<NSString *, id> *> *)storedDictionaries {
    NSArray *items = [NSUserDefaults.standardUserDefaults arrayForKey:SonoraSharedPlaylistDefaultsKey];
    if (![items isKindOfClass:NSArray.class]) {
        return @[];
    }
    return items;
}

- (NSArray<SonoraPlaylist *> *)likedPlaylists {
    NSMutableArray<SonoraPlaylist *> *playlists = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *item in [self storedDictionaries]) {
        NSString *playlistID = [item[@"playlistID"] isKindOfClass:NSString.class] ? item[@"playlistID"] : @"";
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        NSArray *tracks = [item[@"tracks"] isKindOfClass:NSArray.class] ? item[@"tracks"] : @[];
        if (playlistID.length == 0 || name.length == 0) {
            continue;
        }
        NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
        for (NSUInteger index = 0; index < tracks.count; index += 1) {
            [trackIDs addObject:[NSString stringWithFormat:@"%@:%lu", playlistID, (unsigned long)index]];
        }
        SonoraPlaylist *playlist = [[SonoraPlaylist alloc] init];
        playlist.playlistID = playlistID;
        playlist.name = name;
        playlist.trackIDs = [trackIDs copy];
        [playlists addObject:playlist];
    }
    return [playlists copy];
}

- (void)refreshAllPersistentCachesIfNeeded {
    for (NSDictionary<NSString *, id> *item in [self storedDictionaries]) {
        NSString *playlistID = [item[@"playlistID"] isKindOfClass:NSString.class] ? item[@"playlistID"] : @"";
        if (playlistID.length == 0) {
            continue;
        }
        SonoraSharedPlaylistSnapshot *snapshot = [self snapshotForPlaylistID:playlistID];
        if (snapshot != nil) {
            SonoraSharedPlaylistWarmPersistentCache(snapshot);
        }
    }
}

- (nullable SonoraSharedPlaylistSnapshot *)snapshotForPlaylistID:(NSString *)playlistID {
    if (playlistID.length == 0) {
        return nil;
    }
    for (NSDictionary<NSString *, id> *item in [self storedDictionaries]) {
        if (![item[@"playlistID"] isKindOfClass:NSString.class] || ![item[@"playlistID"] isEqualToString:playlistID]) {
            continue;
        }
        SonoraSharedPlaylistSnapshot *snapshot = [[SonoraSharedPlaylistSnapshot alloc] init];
        snapshot.playlistID = item[@"playlistID"];
        snapshot.remoteID = [item[@"remoteID"] isKindOfClass:NSString.class] ? item[@"remoteID"] : @"";
        snapshot.name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"Shared Playlist";
        snapshot.shareURL = [item[@"shareURL"] isKindOfClass:NSString.class] ? item[@"shareURL"] : @"";
        snapshot.sourceBaseURL = [item[@"sourceBaseURL"] isKindOfClass:NSString.class] ? item[@"sourceBaseURL"] : SonoraSharedPlaylistBackendBaseURLString();
        snapshot.contentSHA256 = [item[@"contentSHA256"] isKindOfClass:NSString.class] ? item[@"contentSHA256"] : @"";
        snapshot.coverURL = [item[@"coverURL"] isKindOfClass:NSString.class] ? item[@"coverURL"] : @"";
        snapshot.coverImage = SonoraSharedPlaylistReadImageNamed([item[@"coverFileName"] isKindOfClass:NSString.class] ? item[@"coverFileName"] : @"");

        NSArray *trackItems = [item[@"tracks"] isKindOfClass:NSArray.class] ? item[@"tracks"] : @[];
        NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:trackItems.count];
        NSMutableDictionary<NSString *, NSString *> *trackArtworkURLByTrackID = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSString *> *trackRemoteFileURLByTrackID = [NSMutableDictionary dictionary];
        [trackItems enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull trackDict, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            if (![trackDict isKindOfClass:NSDictionary.class]) {
                return;
            }
            SonoraTrack *track = [[SonoraTrack alloc] init];
            track.identifier = [NSString stringWithFormat:@"%@:%lu", playlistID, (unsigned long)idx];
            track.title = [trackDict[@"title"] isKindOfClass:NSString.class] ? trackDict[@"title"] : [NSString stringWithFormat:@"Track %lu", (unsigned long)(idx + 1)];
            track.artist = [trackDict[@"artist"] isKindOfClass:NSString.class] ? trackDict[@"artist"] : @"";
            track.duration = [trackDict[@"durationMs"] respondsToSelector:@selector(doubleValue)] ? [trackDict[@"durationMs"] doubleValue] / 1000.0 : 0.0;
            NSString *fileURLString = [trackDict[@"fileURL"] isKindOfClass:NSString.class] ? trackDict[@"fileURL"] : @"";
            NSString *remoteFileURLString = [trackDict[@"remoteFileURL"] isKindOfClass:NSString.class] ? trackDict[@"remoteFileURL"] : @"";
            NSURL *resolvedURL = [NSURL URLWithString:fileURLString];
            if (resolvedURL.isFileURL && resolvedURL.path.length > 0 && ![NSFileManager.defaultManager fileExistsAtPath:resolvedURL.path]) {
                resolvedURL = nil;
            }
            if (resolvedURL == nil && remoteFileURLString.length > 0) {
                resolvedURL = [NSURL URLWithString:remoteFileURLString];
            }
            track.url = resolvedURL ?: [NSURL fileURLWithPath:@"/dev/null"];
            if (remoteFileURLString.length > 0) {
                trackRemoteFileURLByTrackID[track.identifier] = remoteFileURLString;
            } else if (fileURLString.length > 0 && !track.url.isFileURL) {
                trackRemoteFileURLByTrackID[track.identifier] = fileURLString;
            }
            track.artwork = SonoraSharedPlaylistReadImageNamed([trackDict[@"artworkFileName"] isKindOfClass:NSString.class] ? trackDict[@"artworkFileName"] : @"");
            NSString *artworkURLString = [trackDict[@"artworkURL"] isKindOfClass:NSString.class] ? trackDict[@"artworkURL"] : @"";
            if (artworkURLString.length > 0) {
                trackArtworkURLByTrackID[track.identifier] = artworkURLString;
            }
            [tracks addObject:track];
        }];
        snapshot.tracks = [tracks copy];
        snapshot.trackArtworkURLByTrackID = [trackArtworkURLByTrackID copy];
        snapshot.trackRemoteFileURLByTrackID = [trackRemoteFileURLByTrackID copy];
        return snapshot;
    }
    return nil;
}

- (BOOL)isSnapshotLikedForPlaylistID:(NSString *)playlistID {
    return ([self snapshotForPlaylistID:playlistID] != nil);
}

- (void)saveSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot {
    if (snapshot.playlistID.length == 0) {
        return;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *stored = [[self storedDictionaries] mutableCopy];
    NSIndexSet *matches = [stored indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *,id> * _Nonnull item, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
        return [item[@"playlistID"] isEqualToString:snapshot.playlistID];
    }];
    if (matches.count > 0) {
        [stored removeObjectsAtIndexes:matches];
    }

    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"playlistID"] = snapshot.playlistID;
    dictionary[@"remoteID"] = snapshot.remoteID ?: @"";
    dictionary[@"name"] = snapshot.name ?: @"Shared Playlist";
    dictionary[@"shareURL"] = snapshot.shareURL ?: @"";
    dictionary[@"sourceBaseURL"] = snapshot.sourceBaseURL ?: SonoraSharedPlaylistBackendBaseURLString();
    dictionary[@"contentSHA256"] = snapshot.contentSHA256 ?: @"";
    dictionary[@"coverURL"] = snapshot.coverURL ?: @"";

    NSString *coverFileName = SonoraSharedPlaylistWriteImage(snapshot.coverImage, [NSString stringWithFormat:@"%@_cover.jpg", snapshot.remoteID.length > 0 ? snapshot.remoteID : NSUUID.UUID.UUIDString.lowercaseString]);
    if (coverFileName.length > 0) {
        dictionary[@"coverFileName"] = coverFileName;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *trackItems = [NSMutableArray arrayWithCapacity:snapshot.tracks.count];
    [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
        NSMutableDictionary<NSString *, id> *trackDict = [NSMutableDictionary dictionary];
        trackDict[@"title"] = track.title ?: @"";
        trackDict[@"artist"] = track.artist ?: @"";
        trackDict[@"durationMs"] = @((NSInteger)llround(MAX(track.duration, 0.0) * 1000.0));
        trackDict[@"fileURL"] = track.url.absoluteString ?: @"";
        NSString *remoteFileURL = snapshot.trackRemoteFileURLByTrackID[track.identifier ?: @""];
        if (remoteFileURL.length == 0 && !track.url.isFileURL) {
            remoteFileURL = track.url.absoluteString ?: @"";
        }
        if (remoteFileURL.length > 0) {
            trackDict[@"remoteFileURL"] = remoteFileURL;
        }
        NSString *artworkURL = snapshot.trackArtworkURLByTrackID[track.identifier ?: @""];
        if (artworkURL.length > 0) {
            trackDict[@"artworkURL"] = artworkURL;
        }
        NSString *artworkName = SonoraSharedPlaylistWriteImage(track.artwork, [NSString stringWithFormat:@"%@_%lu.jpg", snapshot.remoteID.length > 0 ? snapshot.remoteID : @"shared", (unsigned long)idx]);
        if (artworkName.length > 0) {
            trackDict[@"artworkFileName"] = artworkName;
        }
        [trackItems addObject:trackDict];
    }];
    dictionary[@"tracks"] = [trackItems copy];

    [stored insertObject:[dictionary copy] atIndex:0];
    [NSUserDefaults.standardUserDefaults setObject:[stored copy] forKey:SonoraSharedPlaylistDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (!SonoraSharedPlaylistShouldSuppressDidChangeNotification()) {
        SonoraSharedPlaylistPostDidChangeNotification();
    }
}

- (void)removeSnapshotForPlaylistID:(NSString *)playlistID {
    if (playlistID.length == 0) {
        return;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *stored = [[self storedDictionaries] mutableCopy];
    NSIndexSet *matches = [stored indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *,id> * _Nonnull item, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
        return [item[@"playlistID"] isEqualToString:playlistID];
    }];
    if (matches.count == 0) {
        return;
    }
    NSArray<NSDictionary<NSString *, id> *> *itemsToRemove = [stored objectsAtIndexes:matches];
    NSString *audioCacheDirectory = SonoraSharedPlaylistAudioCacheDirectoryPath();
    for (NSDictionary<NSString *, id> *item in itemsToRemove) {
        NSString *coverFileName = [item[@"coverFileName"] isKindOfClass:NSString.class] ? item[@"coverFileName"] : @"";
        if (coverFileName.length > 0) {
            NSString *coverPath = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:coverFileName];
            [NSFileManager.defaultManager removeItemAtPath:coverPath error:nil];
        }
        NSArray *trackItems = [item[@"tracks"] isKindOfClass:NSArray.class] ? item[@"tracks"] : @[];
        for (NSDictionary<NSString *, id> *trackItem in trackItems) {
            NSString *artworkFileName = [trackItem[@"artworkFileName"] isKindOfClass:NSString.class] ? trackItem[@"artworkFileName"] : @"";
            if (artworkFileName.length > 0) {
                NSString *artworkPath = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:artworkFileName];
                [NSFileManager.defaultManager removeItemAtPath:artworkPath error:nil];
            }
            NSString *fileURLString = [trackItem[@"fileURL"] isKindOfClass:NSString.class] ? trackItem[@"fileURL"] : @"";
            NSURL *fileURL = [NSURL URLWithString:fileURLString];
            if (fileURL.isFileURL &&
                fileURL.path.length > 0 &&
                [fileURL.path hasPrefix:audioCacheDirectory]) {
                [NSFileManager.defaultManager removeItemAtPath:fileURL.path error:nil];
            }
        }
    }
    [stored removeObjectsAtIndexes:matches];
    [NSUserDefaults.standardUserDefaults setObject:[stored copy] forKey:SonoraSharedPlaylistDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (!SonoraSharedPlaylistShouldSuppressDidChangeNotification()) {
        SonoraSharedPlaylistPostDidChangeNotification();
    }
}

@end

@interface SonoraPlaylistNameViewController : UIViewController
@end

@interface SonoraPlaylistTrackPickerViewController : UIViewController
- (instancetype)initWithPlaylistName:(NSString *)playlistName tracks:(NSArray<SonoraTrack *> *)tracks;
@end

@interface SonoraPlaylistAddTracksViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistCoverPickerViewController : UIViewController <PHPickerViewControllerDelegate>
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistDetailViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

#pragma mark - Music

typedef NS_ENUM(NSInteger, SonoraSearchSectionType) {
    SonoraSearchSectionTypeMiniStreaming = 0,
    SonoraSearchSectionTypePlaylists = 1,
    SonoraSearchSectionTypeArtists = 2,
    SonoraSearchSectionTypeTracks = 3,
};

static NSString * const SonoraMusicSearchCardCellReuseID = @"SonoraMusicSearchCardCell";
static NSString * const SonoraMiniStreamingListCellReuseID = @"SonoraMiniStreamingListCell";
static NSString * const SonoraMusicSearchHeaderReuseID = @"SonoraMusicSearchHeader";

@interface SonoraMusicSearchCardCell : UICollectionViewCell

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage * _Nullable)image;

@end

@interface SonoraMusicSearchCardCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SonoraMusicSearchCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    coverView.layer.cornerRadius = 12.0;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [coverView.heightAnchor constraintEqualToAnchor:coverView.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:8.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage * _Nullable)image {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    if (image != nil) {
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.image = image;
    } else {
        UIImage *placeholder = [UIImage systemImageNamed:@"music.note"];
        self.coverView.contentMode = UIViewContentModeCenter;
        self.coverView.image = placeholder;
        self.coverView.tintColor = UIColor.secondaryLabelColor;
        self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.08];
            }
            return [UIColor colorWithWhite:0.0 alpha:0.04];
        }];
    }
}

@end

@interface SonoraMiniStreamingListCell : UICollectionViewCell

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               durationText:(NSString *)durationText
                     image:(UIImage * _Nullable)image
                  isCurrent:(BOOL)isCurrent
     showsPlaybackIndicator:(BOOL)showsPlaybackIndicator
             showsSeparator:(BOOL)showsSeparator;

@end

@interface SonoraMiniStreamingListCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIView *separatorView;

@end

@implementation SonoraMiniStreamingListCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;
    CGFloat separatorHeight = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    coverView.layer.cornerRadius = 6.0;
    coverView.layer.masksToBounds = YES;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    durationLabel.textColor = UIColor.secondaryLabelColor;
    durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel = durationLabel;

    UIView *separatorView = [[UIView alloc] init];
    separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    separatorView.backgroundColor = [UIColor separatorColor];
    self.separatorView = separatorView;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:durationLabel];
    [self.contentView addSubview:separatorView];
    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentFill;
    textStack.distribution = UIStackViewDistributionFill;
    textStack.spacing = 2.0;
    [self.contentView addSubview:textStack];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
        [coverView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [coverView.widthAnchor constraintEqualToConstant:34.0],
        [coverView.heightAnchor constraintEqualToConstant:34.0],

        [durationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
        [durationLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [durationLabel.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],

        [textStack.leadingAnchor constraintEqualToAnchor:coverView.trailingAnchor constant:10.0],
        [textStack.trailingAnchor constraintEqualToAnchor:durationLabel.leadingAnchor constant:-8.0],
        [textStack.centerYAnchor constraintEqualToAnchor:coverView.centerYAnchor],

        [separatorView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:62.0],
        [separatorView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [separatorView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [separatorView.heightAnchor constraintEqualToConstant:separatorHeight]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.durationLabel.text = nil;
    self.separatorView.hidden = NO;
    self.titleLabel.textColor = UIColor.labelColor;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               durationText:(NSString *)durationText
                     image:(UIImage * _Nullable)image
                  isCurrent:(BOOL)isCurrent
     showsPlaybackIndicator:(BOOL)showsPlaybackIndicator
             showsSeparator:(BOOL)showsSeparator {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.durationLabel.text = durationText ?: @"";
    self.subtitleLabel.hidden = (subtitle.length == 0);
    self.separatorView.hidden = !showsSeparator;
    self.titleLabel.textColor = isCurrent ? SonoraAccentYellowColor() : UIColor.labelColor;

    if (showsPlaybackIndicator && isCurrent) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                                                               weight:UIImageSymbolWeightSemibold];
        self.coverView.image = [UIImage systemImageNamed:@"pause.fill" withConfiguration:config];
        self.coverView.tintColor = UIColor.labelColor;
        self.coverView.backgroundColor = UIColor.clearColor;
        self.coverView.contentMode = UIViewContentModeCenter;
        return;
    }

    if (image != nil) {
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.image = image;
        return;
    }

    self.coverView.contentMode = UIViewContentModeCenter;
    self.coverView.image = [UIImage systemImageNamed:@"music.note"];
    self.coverView.tintColor = UIColor.secondaryLabelColor;
    self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.08];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.04];
    }];
}

@end

@interface SonoraMusicSearchHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title;

@end

@interface SonoraMusicSearchHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation SonoraMusicSearchHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = SonoraHeadlineFont(24.0);
        label.textColor = UIColor.labelColor;
        self.titleLabel = label;
        [self addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0.0],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title {
    self.titleLabel.text = title ?: @"";
}

@end

@interface SonoraMusicViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UICollectionViewDataSource, UICollectionViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *searchCollectionView;
@property (nonatomic, strong) SonoraMiniStreamingClient *miniStreamingClient;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *artistResults;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *miniStreamingTracks;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingArtist *> *miniStreamingArtists;
@property (nonatomic, assign) BOOL miniStreamingArtistsSectionVisible;
@property (nonatomic, copy) NSArray<NSNumber *> *visibleSections;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *miniStreamingArtworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *miniStreamingArtworkLoadingURLs;
@property (nonatomic, strong) NSMutableSet<NSString *> *miniStreamingInstallingTrackIDs;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *miniStreamingPlaybackQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *miniStreamingResolvedPayloadByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SonoraTrack *> *miniStreamingInstalledTracksByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *miniStreamingInstalledPathsByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *miniStreamingDownloadTasksByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *miniStreamingResolveRetryAfterByTrackID;
@property (nonatomic, copy, nullable) NSString *miniStreamingActiveTrackID;
@property (nonatomic, copy, nullable) NSString *miniStreamingCurrentPlaybackTrackID;
@property (nonatomic, strong) UITapGestureRecognizer *searchKeyboardDismissTapRecognizer;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL musicOnlyMode;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, assign) NSUInteger miniStreamingQueryToken;
@property (nonatomic, assign) NSUInteger reloadTracksRequestToken;
@property (nonatomic, assign) NSUInteger reloadPlaylistsRequestToken;
@property (nonatomic, assign) BOOL playbackSurfaceRefreshScheduled;
@property (nonatomic, copy, nullable) dispatch_block_t miniStreamingSearchDebounceWorkItem;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraMusicViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    self.title = nil;
    self.tabBarItem.title = @"";
    self.tabBarItem.titlePositionAdjustment = UIOffsetMake(0.0, 1000.0);
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(pageTitle)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
    }

    if (self.musicOnlyMode) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
        swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
        [self.view addGestureRecognizer:swipeRight];
    }

    [self setupTableView];
    [self setupSearchCollectionView];
    [self setupSearch];
    [self updatePresentationMode];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];
    self.miniStreamingClient = [[SonoraMiniStreamingClient alloc] init];
    self.miniStreamingTracks = @[];
    self.miniStreamingArtists = @[];
    self.miniStreamingArtistsSectionVisible = self.miniStreamingClient.artistsSectionEnabled;
    self.miniStreamingArtworkCache = [[NSCache alloc] init];
    self.miniStreamingArtworkCache.countLimit = 128;
    self.miniStreamingArtworkCache.totalCostLimit = 96 * 1024 * 1024;
    self.miniStreamingArtworkLoadingURLs = [NSMutableSet set];
    self.miniStreamingInstallingTrackIDs = [NSMutableSet set];
    self.miniStreamingResolvedPayloadByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingPlaybackQueue = @[];
    self.miniStreamingInstalledTracksByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingInstalledPathsByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingDownloadTasksByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingResolveRetryAfterByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingActiveTrackID = nil;
    self.miniStreamingCurrentPlaybackTrackID = nil;
    self.miniStreamingQueryToken = 0;
    [self loadMiniStreamingInstalledTrackMappingsFromDefaults];

    [self refreshNavigationItemsForMusicSelectionState];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadTracks)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaylistsChanged)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [self reloadTracks];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self updatePresentationMode];
    [self updateSearchControllerAttachment];
    [self reloadVisibleContentViews];
}

- (void)handleDismissSwipe {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"MusicTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearchCollectionView {
    UICollectionViewCompositionalLayout *layout = [self buildSearchCollectionLayout];
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = UIColor.systemBackgroundColor;
    collectionView.alwaysBounceVertical = YES;
    collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    collectionView.dataSource = self;
    collectionView.delegate = self;

    [collectionView registerClass:SonoraMusicSearchCardCell.class forCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID];
    [collectionView registerClass:SonoraMiniStreamingListCell.class forCellWithReuseIdentifier:SonoraMiniStreamingListCellReuseID];
    [collectionView registerClass:SonoraMusicSearchHeaderView.class
       forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
              withReuseIdentifier:SonoraMusicSearchHeaderReuseID];
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSearchBackgroundTap)];
    dismissTap.cancelsTouchesInView = NO;
    [collectionView addGestureRecognizer:dismissTap];
    self.searchKeyboardDismissTapRecognizer = dismissTap;

    self.searchCollectionView = collectionView;
    [self.view addSubview:collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)updatePresentationMode {
    self.tableView.hidden = !self.musicOnlyMode;
    self.searchCollectionView.hidden = self.musicOnlyMode;
}

- (UICollectionViewCompositionalLayout *)buildSearchCollectionLayout {
    __weak typeof(self) weakSelf = self;
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                                                                        __unused id<NSCollectionLayoutEnvironment> _Nonnull environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }
        SonoraSearchSectionType sectionType = [strongSelf sectionTypeForIndex:sectionIndex];
        return [strongSelf searchSectionLayoutForSectionType:sectionType];
    }];
}

- (NSCollectionLayoutSection *)searchSectionLayoutForSectionType:(SonoraSearchSectionType)sectionType {
    BOOL isSpotifyListSection = (sectionType == SonoraSearchSectionTypeMiniStreaming);
    NSCollectionLayoutSize *itemSize = nil;
    NSCollectionLayoutSize *groupSize = nil;
    CGFloat interGroupSpacing = 0.0;
    NSDirectionalEdgeInsets sectionInsets = NSDirectionalEdgeInsetsZero;
    UICollectionLayoutSectionOrthogonalScrollingBehavior scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;

    if (isSpotifyListSection) {
        itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:54.0]];
        groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                   heightDimension:[NSCollectionLayoutDimension absoluteDimension:54.0]];
        interGroupSpacing = 0.0;
        sectionInsets = NSDirectionalEdgeInsetsMake(8.0, 0.0, 12.0, 0.0);
        scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;
    } else {
        itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
        groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                   heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
        interGroupSpacing = 12.0;
        sectionInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
        scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    }

    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = interGroupSpacing;
    section.contentInsets = sectionInsets;
    section.orthogonalScrollingBehavior = scrolling;

    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                         heightDimension:[NSCollectionLayoutDimension estimatedDimension:36.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
                                                           boundarySupplementaryItemWithLayoutSize:headerSize
                                                           elementKind:UICollectionElementKindSectionHeader
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    section.boundarySupplementaryItems = @[header];
    return section;
}

- (void)setupSearch {
    NSString *placeholder = self.musicOnlyMode ? @"Search Music" : @"Search Spotify";
    self.searchController = SonoraBuildSearchController(self, placeholder);
    self.definesPresentationContext = YES;
    if (self.musicOnlyMode) {
        self.navigationItem.searchController = nil;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
        self.searchControllerAttached = NO;
    } else {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.searchControllerAttached = YES;
    }
}

- (void)updateSearchControllerAttachment {
    if (!self.musicOnlyMode) {
        if (!self.searchControllerAttached || self.navigationItem.searchController != self.searchController) {
            self.searchControllerAttached = YES;
            SonoraApplySearchControllerAttachment(self.navigationItem,
                                              self.navigationController.navigationBar,
                                              self.searchController,
                                              YES,
                                              (self.view.window != nil));
        }
        return;
    }

    UIScrollView *targetScroll = self.musicOnlyMode ? self.tableView : self.searchCollectionView;
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       targetScroll,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    self.playlists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
    if (self.musicOnlyMode) {
        self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        self.filteredPlaylists = @[];
        self.artistResults = @[];
        self.miniStreamingTracks = @[];
        self.miniStreamingArtists = @[];
    } else {
        NSArray<SonoraTrack *> *queryTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        if (normalizedQuery.length == 0) {
            NSArray<SonoraTrack *> *affinityTracks = [SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:self.tracks] ?: @[];
            queryTracks = affinityTracks.count > 0 ? affinityTracks : self.tracks;
        }
        if (queryTracks.count > 24) {
            self.filteredTracks = [queryTracks subarrayWithRange:NSMakeRange(0, 24)];
        } else {
            self.filteredTracks = queryTracks;
        }

        self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
        if (self.filteredPlaylists.count > 10) {
            self.filteredPlaylists = [self.filteredPlaylists subarrayWithRange:NSMakeRange(0, 10)];
        }
        self.artistResults = @[];
    }

    NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
    if (self.musicOnlyMode) {
        [sections addObject:@(SonoraSearchSectionTypeTracks)];
    } else {
        if (self.miniStreamingTracks.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeMiniStreaming)];
        }
        if (self.miniStreamingArtists.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeArtists)];
        }
        if (self.filteredPlaylists.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypePlaylists)];
        }
        if (self.filteredTracks.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeTracks)];
        }
    }
    self.visibleSections = [sections copy];

    [self reloadVisibleContentViews];
    [self updateEmptyState];
}

- (void)reloadVisibleContentViews {
    if (self.tableView != nil && !self.tableView.hidden) {
        [self.tableView reloadData];
    }
    if (self.searchCollectionView != nil && !self.searchCollectionView.hidden) {
        [self.searchCollectionView reloadData];
    }
}

- (void)schedulePlaybackStateSurfaceRefresh {
    if (self.playbackSurfaceRefreshScheduled) {
        return;
    }
    self.playbackSurfaceRefreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.playbackSurfaceRefreshScheduled = NO;
        if (strongSelf.viewIfLoaded.window == nil) {
            return;
        }
        [strongSelf reloadVisibleContentViews];
        [strongSelf ensureCurrentMiniStreamingPlaceholderIsInstalling];
    });
}

- (void)updateEmptyState {
    BOOL hasAnyResult = (self.filteredTracks.count > 0 ||
                         self.filteredPlaylists.count > 0 ||
                         self.miniStreamingTracks.count > 0 ||
                         self.miniStreamingArtists.count > 0);
    if (hasAnyResult) {
        self.tableView.backgroundView = nil;
        self.searchCollectionView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.musicOnlyMode) {
        if (self.tracks.count == 0) {
            label.text = @"No music files in On My iPhone/Sonora/Sonora";
        } else {
            label.text = @"No search results.";
        }
        self.tableView.backgroundView = label;
        self.searchCollectionView.backgroundView = nil;
    } else {
        NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
        if (normalizedQuery.length == 0) {
            label.text = @"Use Search above to find Spotify tracks and artists.";
        } else {
            label.text = @"No search results.";
        }
        self.searchCollectionView.backgroundView = label;
        self.tableView.backgroundView = nil;
    }
}

- (void)loadMiniStreamingInstalledTrackMappingsFromDefaults {
    [self.miniStreamingInstalledPathsByTrackID removeAllObjects];
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SonoraMiniStreamingInstalledTrackMapDefaultsKey];
    if (![stored isKindOfClass:NSDictionary.class]) {
        return;
    }
    [stored enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull rawTrackID, id  _Nonnull rawPath, __unused BOOL * _Nonnull stop) {
        if (![rawTrackID isKindOfClass:NSString.class] || ![rawPath isKindOfClass:NSString.class]) {
            return;
        }
        NSString *trackID = SonoraTrimmedStringValue((NSString *)rawTrackID);
        NSString *path = SonoraTrimmedStringValue((NSString *)rawPath);
        if (trackID.length == 0 || path.length == 0) {
            return;
        }
        self.miniStreamingInstalledPathsByTrackID[trackID] = path;
    }];
}

- (void)persistMiniStreamingInstalledTrackMappings {
    NSDictionary<NSString *, NSString *> *payload = [self.miniStreamingInstalledPathsByTrackID copy] ?: @{};
    [NSUserDefaults.standardUserDefaults setObject:payload forKey:SonoraMiniStreamingInstalledTrackMapDefaultsKey];
}

- (void)rememberMiniStreamingInstalledTrack:(SonoraTrack *)installedTrack trackID:(NSString *)trackID {
    if (installedTrack == nil || trackID.length == 0) {
        return;
    }
    self.miniStreamingInstalledTracksByTrackID[trackID] = installedTrack;
    if (installedTrack.identifier.length > 0) {
        self.miniStreamingInstalledPathsByTrackID[trackID] = installedTrack.identifier;
    } else if (installedTrack.url.path.length > 0) {
        self.miniStreamingInstalledPathsByTrackID[trackID] = installedTrack.url.path;
    } else {
        [self.miniStreamingInstalledPathsByTrackID removeObjectForKey:trackID];
    }
    [self persistMiniStreamingInstalledTrackMappings];
}

- (NSArray<NSString *> *)miniStreamingArtistTokensFromText:(NSString *)artistText {
    NSString *normalized = SonoraNormalizedSearchText(artistText ?: @"");
    if (normalized.length == 0) {
        return @[];
    }
    NSCharacterSet *splitSet = [NSCharacterSet characterSetWithCharactersInString:@",/&;|"];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:splitSet];
    for (NSString *part in parts) {
        NSString *token = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (token.length >= 2) {
            [tokens addObject:token];
        }
    }
    return [tokens copy];
}

- (nullable SonoraTrack *)installedLibraryTrackMatchingMiniStreamingTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil) {
        return nil;
    }
    NSString *targetTitle = SonoraNormalizedSearchText(track.title ?: @"");
    if (targetTitle.length == 0) {
        return nil;
    }
    NSString *targetArtist = SonoraNormalizedSearchText(track.artists ?: @"");
    NSArray<NSString *> *artistTokens = [self miniStreamingArtistTokensFromText:track.artists ?: @""];
    SonoraTrack *titleOnlyFallback = nil;
    for (SonoraTrack *candidate in self.tracks) {
        NSString *candidateTitle = SonoraNormalizedSearchText(candidate.title ?: @"");
        if (candidateTitle.length == 0 || ![candidateTitle isEqualToString:targetTitle]) {
            continue;
        }
        if (targetArtist.length == 0) {
            return candidate;
        }
        NSString *candidateArtist = SonoraNormalizedSearchText(candidate.artist ?: @"");
        if (candidateArtist.length == 0) {
            if (titleOnlyFallback == nil) {
                titleOnlyFallback = candidate;
            }
            continue;
        }
        if ([candidateArtist containsString:targetArtist] || [targetArtist containsString:candidateArtist]) {
            return candidate;
        }
        for (NSString *token in artistTokens) {
            if (token.length > 1 && [candidateArtist containsString:token]) {
                return candidate;
            }
        }
        if (titleOnlyFallback == nil) {
            titleOnlyFallback = candidate;
        }
    }
    return titleOnlyFallback;
}

- (void)rehydrateMiniStreamingInstalledTracksFromLibrary {
    NSMutableDictionary<NSString *, SonoraTrack *> *resolved = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *validPaths = [NSMutableDictionary dictionary];

    for (NSString *trackID in self.miniStreamingInstalledPathsByTrackID) {
        NSString *path = SonoraTrimmedStringValue(self.miniStreamingInstalledPathsByTrackID[trackID]);
        if (trackID.length == 0 || path.length == 0) {
            continue;
        }
        SonoraTrack *track = [SonoraLibraryManager.sharedManager trackForIdentifier:path];
        if (track == nil && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            track = [self installedTrackForDestinationURL:[NSURL fileURLWithPath:path]];
        }
        if (track == nil) {
            continue;
        }
        resolved[trackID] = track;
        if (track.identifier.length > 0) {
            validPaths[trackID] = track.identifier;
        } else if (track.url.path.length > 0) {
            validPaths[trackID] = track.url.path;
        }
    }

    [self.miniStreamingInstalledTracksByTrackID removeAllObjects];
    [self.miniStreamingInstalledTracksByTrackID addEntriesFromDictionary:resolved];

    NSDictionary<NSString *, NSString *> *currentPaths = [self.miniStreamingInstalledPathsByTrackID copy] ?: @{};
    if (![currentPaths isEqualToDictionary:validPaths]) {
        [self.miniStreamingInstalledPathsByTrackID removeAllObjects];
        [self.miniStreamingInstalledPathsByTrackID addEntriesFromDictionary:validPaths];
        [self persistMiniStreamingInstalledTrackMappings];
    }
}

- (nullable SonoraTrack *)knownInstalledMiniStreamingTrackForTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil || track.trackID.length == 0) {
        return nil;
    }
    SonoraTrack *installedTrack = self.miniStreamingInstalledTracksByTrackID[track.trackID];
    if (installedTrack != nil && installedTrack.url.path.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:installedTrack.url.path]) {
        return installedTrack;
    }

    NSString *savedPath = SonoraTrimmedStringValue(self.miniStreamingInstalledPathsByTrackID[track.trackID]);
    if (savedPath.length > 0) {
        SonoraTrack *savedTrack = [SonoraLibraryManager.sharedManager trackForIdentifier:savedPath];
        if (savedTrack == nil && [NSFileManager.defaultManager fileExistsAtPath:savedPath]) {
            savedTrack = [self installedTrackForDestinationURL:[NSURL fileURLWithPath:savedPath]];
        }
        if (savedTrack != nil) {
            [self rememberMiniStreamingInstalledTrack:savedTrack trackID:track.trackID];
            return savedTrack;
        }
        [self.miniStreamingInstalledPathsByTrackID removeObjectForKey:track.trackID];
        [self persistMiniStreamingInstalledTrackMappings];
    }

    SonoraTrack *matchedTrack = [self installedLibraryTrackMatchingMiniStreamingTrack:track];
    if (matchedTrack != nil) {
        [self rememberMiniStreamingInstalledTrack:matchedTrack trackID:track.trackID];
        return matchedTrack;
    }
    return nil;
}

- (void)reloadTracks {
    self.reloadTracksRequestToken += 1;
    NSUInteger requestToken = self.reloadTracksRequestToken;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<SonoraTrack *> *reloadedTracks = [SonoraLibraryManager.sharedManager reloadTracks] ?: @[];
        [SonoraPlaylistStore.sharedStore reloadPlaylists];
        NSArray<SonoraPlaylist *> *reloadedPlaylists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || requestToken != strongSelf.reloadTracksRequestToken) {
                return;
            }
            strongSelf.tracks = reloadedTracks;
            [strongSelf rehydrateMiniStreamingInstalledTracksFromLibrary];
            strongSelf.playlists = reloadedPlaylists;
            [strongSelf applySearchFilterAndReload];
        });
    });
}

- (void)handlePlaylistsChanged {
    self.reloadPlaylistsRequestToken += 1;
    NSUInteger requestToken = self.reloadPlaylistsRequestToken;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [SonoraPlaylistStore.sharedStore reloadPlaylists];
        NSArray<SonoraPlaylist *> *reloadedPlaylists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || requestToken != strongSelf.reloadPlaylistsRequestToken) {
                return;
            }
            strongSelf.playlists = reloadedPlaylists;
            [strongSelf applySearchFilterAndReload];
        });
    });
}

- (void)handlePlaybackChanged {
    NSString *currentMiniTrackID = [self miniStreamingTrackIDFromPlaybackTrack:SonoraPlaybackManager.sharedManager.currentTrack];
    NSString *previousMiniTrackID = self.miniStreamingCurrentPlaybackTrackID ?: @"";
    NSString *nextMiniTrackID = currentMiniTrackID ?: @"";
    if (![previousMiniTrackID isEqualToString:nextMiniTrackID]) {
        if (self.miniStreamingCurrentPlaybackTrackID.length > 0) {
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"cancel_download_on_track_change previous=%@ next=%@",
                                                     self.miniStreamingCurrentPlaybackTrackID,
                                                     nextMiniTrackID]);
            [self cancelMiniStreamingDownloadTaskForTrackID:self.miniStreamingCurrentPlaybackTrackID];
        }
    }
    self.miniStreamingCurrentPlaybackTrackID = nextMiniTrackID.length > 0 ? nextMiniTrackID : nil;

    [self schedulePlaybackStateSurfaceRefresh];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)handleSearchBackgroundTap {
    if (self.musicOnlyMode) {
        return;
    }
    [self.searchController.searchBar resignFirstResponder];
}

- (void)refreshMiniStreamingForCurrentQuery {
    if (self.musicOnlyMode) {
        return;
    }

    if (self.miniStreamingSearchDebounceWorkItem != nil) {
        dispatch_block_cancel(self.miniStreamingSearchDebounceWorkItem);
        self.miniStreamingSearchDebounceWorkItem = nil;
    }

    NSString *querySnapshot = self.searchQuery ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_block_t workItem = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.miniStreamingSearchDebounceWorkItem = nil;
        [strongSelf refreshMiniStreamingForQuery:querySnapshot];
    });

    self.miniStreamingSearchDebounceWorkItem = workItem;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   workItem);
}

- (void)refreshMiniStreamingForQuery:(NSString *)query {
    if (self.musicOnlyMode) {
        return;
    }

    self.miniStreamingQueryToken += 1;
    NSUInteger currentToken = self.miniStreamingQueryToken;
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);

    if (normalizedQuery.length < 2 || ![self.miniStreamingClient isConfigured]) {
        self.miniStreamingArtistsSectionVisible = self.miniStreamingClient.artistsSectionEnabled;
        if (self.miniStreamingTracks.count > 0 || self.miniStreamingArtists.count > 0) {
            self.miniStreamingTracks = @[];
            self.miniStreamingArtists = @[];
            [self applySearchFilterAndReload];
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    __block NSArray<SonoraMiniStreamingTrack *> *resolvedTracks = self.miniStreamingTracks ?: @[];
    __block NSArray<SonoraMiniStreamingArtist *> *resolvedArtists = self.miniStreamingArtists ?: @[];
    __block BOOL artistsSectionVisible = self.miniStreamingArtistsSectionVisible;
    __block BOOL tracksResolved = NO;
    __block BOOL artistsResolved = NO;

    void (^commitIfReady)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }
        if (!tracksResolved || !artistsResolved) {
            return;
        }
        strongSelf.miniStreamingTracks = resolvedTracks ?: @[];
        strongSelf.miniStreamingArtistsSectionVisible = artistsSectionVisible;
        strongSelf.miniStreamingArtists = artistsSectionVisible ? (resolvedArtists ?: @[]) : @[];
        [strongSelf applySearchFilterAndReload];
    };

    [self.miniStreamingClient searchTracks:normalizedQuery
                                     limit:SonoraMiniStreamingSearchLimit
                                completion:^(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }

        (void)error;
        resolvedTracks = tracks ?: @[];
        artistsSectionVisible = strongSelf.miniStreamingClient.artistsSectionEnabled;
        if (!artistsSectionVisible) {
            resolvedArtists = @[];
        }
        tracksResolved = YES;
        commitIfReady();
    }];

    [self.miniStreamingClient searchArtists:normalizedQuery
                                      limit:10
                                 completion:^(NSArray<SonoraMiniStreamingArtist *> *artists, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }

        (void)error;
        resolvedArtists = artists ?: @[];
        artistsSectionVisible = strongSelf.miniStreamingClient.artistsSectionEnabled;
        if (!artistsSectionVisible) {
            resolvedArtists = @[];
        }
        artistsResolved = YES;
        commitIfReady();
    }];
}

- (nullable UIImage *)cachedMiniStreamingArtworkForURL:(NSString *)urlString {
    if (urlString.length == 0) {
        return nil;
    }
    return [self.miniStreamingArtworkCache objectForKey:urlString];
}

- (void)loadMiniStreamingArtworkIfNeededForURL:(NSString *)urlString {
    if (urlString.length == 0 ||
        [self.miniStreamingArtworkCache objectForKey:urlString] != nil ||
        [self.miniStreamingArtworkLoadingURLs containsObject:urlString]) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    [self.miniStreamingArtworkLoadingURLs addObject:urlString];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.miniStreamingArtworkLoadingURLs removeObject:urlString];
            if (image != nil) {
                [strongSelf.miniStreamingArtworkCache setObject:image forKey:urlString];
                [strongSelf reloadMiniStreamingRowsForArtworkURL:urlString];
            }
        });
    }];
    [task resume];
}

- (nullable UIImage *)cachedMiniStreamingArtworkForTrack:(SonoraMiniStreamingTrack *)track {
    return [self cachedMiniStreamingArtworkForURL:track.artworkURL];
}

- (void)loadMiniStreamingArtworkIfNeededForTrack:(SonoraMiniStreamingTrack *)track {
    [self loadMiniStreamingArtworkIfNeededForURL:track.artworkURL];
}

- (nullable NSString *)miniStreamingTrackIDFromPlaybackIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    if ([identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        NSString *trackID = [identifier substringFromIndex:SonoraMiniStreamingPlaceholderPrefix.length];
        return trackID.length > 0 ? trackID : nil;
    }
    return nil;
}

- (nullable NSString *)miniStreamingTrackIDFromPlaybackTrack:(SonoraTrack * _Nullable)playbackTrack {
    if (playbackTrack == nil) {
        return nil;
    }

    __block NSString *trackIDFromIdentifier = [self miniStreamingTrackIDFromPlaybackIdentifier:playbackTrack.identifier ?: @""];
    if (trackIDFromIdentifier.length > 0) {
        return trackIDFromIdentifier;
    }

    [self.miniStreamingInstalledTracksByTrackID enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull trackID,
                                                                                     SonoraTrack * _Nonnull installedTrack,
                                                                                     BOOL * _Nonnull stop) {
        BOOL sameIdentifier = (installedTrack.identifier.length > 0 &&
                               [installedTrack.identifier isEqualToString:playbackTrack.identifier ?: @""]);
        BOOL samePath = (installedTrack.url.path.length > 0 &&
                         [installedTrack.url.path isEqualToString:playbackTrack.url.path ?: @""]);
        if (sameIdentifier || samePath) {
            trackIDFromIdentifier = trackID;
            *stop = YES;
        }
    }];

    return trackIDFromIdentifier.length > 0 ? trackIDFromIdentifier : nil;
}

- (BOOL)isMiniStreamingTrackIdentifierMiniPlaceholder:(NSString *)identifier {
    if (identifier.length == 0) {
        return NO;
    }
    if (![identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        return NO;
    }
    return YES;
}

- (BOOL)isMiniStreamingPlaceholderTrack:(SonoraTrack * _Nullable)track {
    if (![self isMiniStreamingTrackIdentifierMiniPlaceholder:track.identifier ?: @""]) {
        return NO;
    }

    NSURL *url = track.url;
    if (url == nil) {
        return YES;
    }
    if (!url.isFileURL) {
        return NO;
    }
    NSString *path = url.path ?: @"";
    return path.length == 0 || [path isEqualToString:@"/dev/null"];
}

- (nullable NSURL *)miniStreamingDownloadURLFromPayload:(NSDictionary<NSString *, id> *)payload {
    NSString *downloadLink = SonoraTrimmedStringValue(payload[@"downloadLink"]);
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"mediaUrl"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"link"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"url"]);
    }
    if (downloadLink.length == 0) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:downloadLink];
    if (url == nil) {
        NSString *encoded = [downloadLink stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet];
        if (encoded.length > 0) {
            url = [NSURL URLWithString:encoded];
        }
    }
    if (url == nil) {
        return nil;
    }
    NSString *scheme = SonoraTrimmedStringValue(url.scheme).lowercaseString;
    if (scheme.length == 0) {
        return nil;
    }
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    return url;
}

- (BOOL)isUsableMiniStreamingPayload:(NSDictionary<NSString *, id> * _Nullable)payload {
    return [self miniStreamingDownloadURLFromPayload:payload ?: @{}] != nil;
}

- (void)playMiniStreamingPlaybackQueueIfCurrentForTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil || track.trackID.length == 0) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSString *currentMiniTrackID = [self miniStreamingTrackIDFromPlaybackTrack:playback.currentTrack];
    BOOL targetIsActiveInstall = [self.miniStreamingActiveTrackID isEqualToString:track.trackID];
    if (currentMiniTrackID.length > 0 &&
        ![currentMiniTrackID isEqualToString:track.trackID] &&
        !targetIsActiveInstall) {
        return;
    }

    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = self.miniStreamingPlaybackQueue;
    if (normalizedQueue.count == 0) {
        normalizedQueue = @[];
    }

    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:normalizedQueue.count];
    NSInteger startIndex = 0;
    for (NSUInteger index = 0; index < normalizedQueue.count; index += 1) {
        SonoraMiniStreamingTrack *queueTrack = normalizedQueue[index];
        if ([queueTrack.trackID isEqualToString:track.trackID]) {
            startIndex = (NSInteger)index;
        }
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:queueTrack]];
    }

    if (playbackQueue.count == 0) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:track]];
    }
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:startIndex];
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_queue_switched track=%@ start_index=%ld queue=%lu",
                                             track.trackID,
                                             (long)startIndex,
                                             (unsigned long)playbackQueue.count]);
}

- (void)cancelMiniStreamingDownloadTaskForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return;
    }

    NSURLSessionDownloadTask *downloadTask = self.miniStreamingDownloadTasksByTrackID[trackID];
    if (downloadTask != nil) {
        [downloadTask cancel];
        [self.miniStreamingDownloadTasksByTrackID removeObjectForKey:trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_cancel track=%@", trackID]);
    }
    [self.miniStreamingInstallingTrackIDs removeObject:trackID];
}

- (nullable SonoraMiniStreamingTrack *)miniStreamingTrackFromPlaybackQueueByTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return nil;
    }

    for (SonoraMiniStreamingTrack *track in self.miniStreamingPlaybackQueue) {
        if ([track.trackID isEqualToString:trackID]) {
            return track;
        }
    }
    for (SonoraMiniStreamingTrack *track in self.miniStreamingTracks) {
        if ([track.trackID isEqualToString:trackID]) {
            return track;
        }
    }
    return nil;
}

- (SonoraTrack *)miniStreamingPlaceholderPlaybackTrackForTrack:(SonoraMiniStreamingTrack *)track {
    SonoraTrack *placeholderTrack = [[SonoraTrack alloc] init];
    placeholderTrack.identifier = [NSString stringWithFormat:@"%@%@", SonoraMiniStreamingPlaceholderPrefix, track.trackID];
    placeholderTrack.title = track.title.length > 0 ? track.title : @"Loading track...";
    placeholderTrack.artist = track.artists.length > 0 ? track.artists : @"Spotify";
    placeholderTrack.fileName = [NSString stringWithFormat:@"%@.placeholder", track.trackID];
    placeholderTrack.url = [NSURL fileURLWithPath:@"/dev/null"];
    placeholderTrack.duration = MAX(track.duration, 0.0);
    UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
    placeholderTrack.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(placeholderTrack.title, CGSizeMake(640.0, 640.0));
    return placeholderTrack;
}

- (SonoraTrack *)miniStreamingPlaybackTrackForMiniTrack:(SonoraMiniStreamingTrack *)miniTrack {
    SonoraTrack *installedTrack = self.miniStreamingInstalledTracksByTrackID[miniTrack.trackID];
    if (installedTrack == nil) {
        installedTrack = [self knownInstalledMiniStreamingTrackForTrack:miniTrack];
    }
    if (installedTrack != nil) {
        return installedTrack;
    }

    NSDictionary<NSString *, id> *payload = self.miniStreamingResolvedPayloadByTrackID[miniTrack.trackID];
    if ([self isUsableMiniStreamingPayload:payload]) {
        NSURL *downloadURL = [self miniStreamingDownloadURLFromPayload:payload];
        if (downloadURL != nil) {
            SonoraTrack *streamingTrack = [[SonoraTrack alloc] init];
            streamingTrack.identifier = [NSString stringWithFormat:@"%@%@", SonoraMiniStreamingPlaceholderPrefix, miniTrack.trackID];
            streamingTrack.title = miniTrack.title.length > 0 ? miniTrack.title : @"Track";
            streamingTrack.artist = miniTrack.artists.length > 0 ? miniTrack.artists : @"Spotify";
            streamingTrack.fileName = [NSString stringWithFormat:@"%@.mp3", miniTrack.trackID];
            streamingTrack.url = downloadURL;
            streamingTrack.duration = MAX(miniTrack.duration, 0.0);
            UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:miniTrack];
            streamingTrack.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(streamingTrack.title, CGSizeMake(640.0, 640.0));
            return streamingTrack;
        }
    }

    return [self miniStreamingPlaceholderPlaybackTrackForTrack:miniTrack];
}

- (NSArray<SonoraMiniStreamingTrack *> *)miniStreamingQueueFromContext:(NSArray<SonoraMiniStreamingTrack *> *)queue
                                                          selectedTrack:(SonoraMiniStreamingTrack *)selectedTrack {
    NSMutableArray<SonoraMiniStreamingTrack *> *normalized = [NSMutableArray array];
    for (SonoraMiniStreamingTrack *candidate in queue) {
        if (![candidate isKindOfClass:SonoraMiniStreamingTrack.class] || candidate.trackID.length == 0) {
            continue;
        }
        [normalized addObject:candidate];
    }

    if (normalized.count == 0 && selectedTrack != nil && selectedTrack.trackID.length > 0) {
        [normalized addObject:selectedTrack];
    }
    return [normalized copy];
}

- (BOOL)miniStreamingPlaybackQueueMatchesMiniTracks:(NSArray<SonoraMiniStreamingTrack *> *)miniTracks {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSArray<SonoraTrack *> *queue = playback.currentQueue ?: @[];
    if (miniTracks.count == 0 || queue.count != miniTracks.count) {
        return NO;
    }

    for (NSUInteger index = 0; index < miniTracks.count; index += 1) {
        SonoraMiniStreamingTrack *expectedTrack = miniTracks[index];
        SonoraTrack *queueTrack = queue[index];
        NSString *queueTrackID = [self miniStreamingTrackIDFromPlaybackTrack:queueTrack];
        if (queueTrackID.length == 0 || ![queueTrackID isEqualToString:expectedTrack.trackID]) {
            return NO;
        }
    }
    return YES;
}

- (void)ensureCurrentMiniStreamingPlaceholderIsInstalling {
    if (self.musicOnlyMode) {
        return;
    }

    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (![self isMiniStreamingPlaceholderTrack:currentTrack]) {
        return;
    }

    NSString *trackID = [self miniStreamingTrackIDFromPlaybackIdentifier:currentTrack.identifier ?: @""];
    if (trackID.length == 0) {
        return;
    }

    SonoraMiniStreamingTrack *miniTrack = [self miniStreamingTrackFromPlaybackQueueByTrackID:trackID];
    if (miniTrack == nil) {
        return;
    }

    [self startMiniStreamingInstallIfNeededForTrack:miniTrack showErrorUI:NO];
}

- (void)reloadMiniStreamingRowsForArtworkURL:(NSString *)artworkURL {
    if (artworkURL.length == 0) {
        return;
    }
    if (self.searchCollectionView == nil || self.searchCollectionView.hidden) {
        return;
    }

    NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray array];
    NSInteger miniTracksSectionIndex = NSNotFound;
    NSInteger artistsSectionIndex = NSNotFound;
    for (NSInteger section = 0; section < self.visibleSections.count; section += 1) {
        SonoraSearchSectionType sectionType = [self sectionTypeForIndex:section];
        if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
            miniTracksSectionIndex = section;
        } else if (sectionType == SonoraSearchSectionTypeArtists) {
            artistsSectionIndex = section;
        }
    }

    if (miniTracksSectionIndex != NSNotFound) {
        for (NSInteger index = 0; index < self.miniStreamingTracks.count; index += 1) {
            SonoraMiniStreamingTrack *track = self.miniStreamingTracks[index];
            if ([track.artworkURL isEqualToString:artworkURL]) {
                [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:miniTracksSectionIndex]];
            }
        }
    }

    if (artistsSectionIndex != NSNotFound) {
        for (NSInteger index = 0; index < self.miniStreamingArtists.count; index += 1) {
            SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[index];
            if ([artist.artworkURL isEqualToString:artworkURL]) {
                [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:artistsSectionIndex]];
            }
        }
    }

    if (indexPaths.count == 0) {
        return;
    }
    NSInteger sectionCount = [self.searchCollectionView numberOfSections];
    NSMutableArray<NSIndexPath *> *validIndexPaths = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.section < 0 || indexPath.section >= sectionCount) {
            continue;
        }
        NSInteger itemCount = [self.searchCollectionView numberOfItemsInSection:indexPath.section];
        if (indexPath.item < 0 || indexPath.item >= itemCount) {
            continue;
        }
        [validIndexPaths addObject:indexPath];
    }
    if (validIndexPaths.count == 0) {
        return;
    }
    [self.searchCollectionView reloadItemsAtIndexPaths:validIndexPaths];
}

- (void)openPlayerIfNeeded {
    if (self.navigationController == nil) {
        return;
    }
    UIViewController *top = self.navigationController.topViewController;
    if ([top isKindOfClass:SonoraPlayerViewController.class]) {
        return;
    }
    [self openPlayer];
}

- (void)prepareMiniStreamingInstallForTrack:(SonoraMiniStreamingTrack *)track
                                      queue:(NSArray<SonoraMiniStreamingTrack *> *)queue
                                 startIndex:(NSInteger)startIndex {
    if (track == nil || track.trackID.length == 0) {
        return;
    }
    self.miniStreamingActiveTrackID = track.trackID;

    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = [self miniStreamingQueueFromContext:queue selectedTrack:track];
    self.miniStreamingPlaybackQueue = normalizedQueue;
    for (SonoraMiniStreamingTrack *queueTrack in normalizedQueue) {
        [self loadMiniStreamingArtworkIfNeededForTrack:queueTrack];
    }

    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:normalizedQueue.count];
    for (SonoraMiniStreamingTrack *queueTrack in normalizedQueue) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:queueTrack]];
    }
    if (playbackQueue.count == 0) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:track]];
    }

    NSInteger resolvedStartIndex = NSNotFound;
    if (startIndex >= 0 && startIndex < (NSInteger)normalizedQueue.count) {
        SonoraMiniStreamingTrack *fromIndexTrack = normalizedQueue[(NSUInteger)startIndex];
        if ([fromIndexTrack.trackID isEqualToString:track.trackID]) {
            resolvedStartIndex = startIndex;
        }
    }
    if (resolvedStartIndex == NSNotFound) {
        for (NSUInteger idx = 0; idx < normalizedQueue.count; idx += 1) {
            if ([normalizedQueue[idx].trackID isEqualToString:track.trackID]) {
                resolvedStartIndex = (NSInteger)idx;
                break;
            }
        }
    }
    if (resolvedStartIndex == NSNotFound) {
        resolvedStartIndex = 0;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:resolvedStartIndex];
}

- (nullable SonoraTrack *)installedTrackForDestinationURL:(NSURL *)destinationURL {
    if (destinationURL.path.length == 0) {
        return nil;
    }

    SonoraTrack *track = [SonoraLibraryManager.sharedManager trackForIdentifier:destinationURL.path];
    if (track != nil) {
        return track;
    }

    for (SonoraTrack *candidate in self.tracks) {
        if ([candidate.identifier isEqualToString:destinationURL.path]) {
            return candidate;
        }
        if ([candidate.url.path isEqualToString:destinationURL.path]) {
            return candidate;
        }
    }
    return nil;
}

- (void)syncMiniStreamingPlaybackWithInstalledTrackAtURL:(NSURL *)destinationURL
                                                  trackID:(NSString *)trackID {
    if (destinationURL == nil || trackID.length == 0) {
        return;
    }

    SonoraTrack *installedTrack = [self installedTrackForDestinationURL:destinationURL];
    if (installedTrack == nil) {
        return;
    }
    [self rememberMiniStreamingInstalledTrack:installedTrack trackID:trackID];

    if ([self.miniStreamingActiveTrackID isEqualToString:trackID]) {
        self.miniStreamingActiveTrackID = nil;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentPlaybackTrack = playback.currentTrack;
    NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
    if (![currentTrackID isEqualToString:trackID]) {
        return;
    }

    BOOL shouldDeferSwap = (currentPlaybackTrack != nil &&
                            currentPlaybackTrack.url != nil &&
                            !currentPlaybackTrack.url.isFileURL &&
                            playback.isPlaying);
    if (shouldDeferSwap) {
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_completed_defer_swap track=%@", trackID]);
        return;
    }

    BOOL wasPlaying = playback.isPlaying;
    NSTimeInterval restoreTime = playback.currentTime;

    SonoraMiniStreamingTrack *queueTrack = [self miniStreamingTrackFromPlaybackQueueByTrackID:trackID];
    if (queueTrack == nil || self.miniStreamingPlaybackQueue.count == 0) {
        [playback setShuffleEnabled:NO];
        [playback playTrack:installedTrack];
        if (restoreTime > 0.0) {
            [playback seekToTime:restoreTime];
        }
        if (!wasPlaying && playback.isPlaying) {
            [playback togglePlayPause];
        }
        return;
    }

    NSInteger startIndex = 0;
    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:self.miniStreamingPlaybackQueue.count];
    for (NSUInteger idx = 0; idx < self.miniStreamingPlaybackQueue.count; idx += 1) {
        SonoraMiniStreamingTrack *miniTrack = self.miniStreamingPlaybackQueue[idx];
        if ([miniTrack.trackID isEqualToString:trackID]) {
            startIndex = (NSInteger)idx;
        }
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:miniTrack]];
    }
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:startIndex];
    if (restoreTime > 0.0) {
        [playback seekToTime:restoreTime];
    }
    if (!wasPlaying && playback.isPlaying) {
        [playback togglePlayPause];
    }
}

- (NSURL *)availableDestinationURLInDirectory:(NSURL *)directoryURL
                                     baseName:(NSString *)baseName
                                    extension:(NSString *)fileExtension {
    NSString *normalizedBaseName = SonoraSanitizedFileComponent(baseName);
    if (normalizedBaseName.length == 0) {
        normalizedBaseName = @"track";
    }

    NSString *normalizedExtension = SonoraTrimmedStringValue(fileExtension).lowercaseString;
    if (normalizedExtension.length == 0) {
        normalizedExtension = @"mp3";
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *candidateURL = [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", normalizedBaseName, normalizedExtension]];
    if (![fileManager fileExistsAtPath:candidateURL.path]) {
        return candidateURL;
    }

    for (NSUInteger index = 2; index <= 999; index += 1) {
        NSString *candidateName = [NSString stringWithFormat:@"%@ (%lu).%@", normalizedBaseName, (unsigned long)index, normalizedExtension];
        candidateURL = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![fileManager fileExistsAtPath:candidateURL.path]) {
            return candidateURL;
        }
    }

    NSString *uuid = [NSUUID UUID].UUIDString;
    return [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.%@", normalizedBaseName, uuid, normalizedExtension]];
}

- (void)startMiniStreamingBackgroundDownloadFromURL:(NSURL *)downloadURL
                                             payload:(NSDictionary<NSString *, id> *)payload
                                             trackID:(NSString *)trackID {
    if (downloadURL == nil || trackID.length == 0) {
        return;
    }
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_start track=%@ url=%@",
                                             trackID,
                                             downloadURL.absoluteString ?: @""]);

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *existingTask = self.miniStreamingDownloadTasksByTrackID[trackID];
    if (existingTask != nil) {
        [existingTask cancel];
    }

    NSURLSessionDownloadTask *downloadTask = [NSURLSession.sharedSession downloadTaskWithURL:downloadURL
                                                                            completionHandler:^(NSURL * _Nullable location,
                                                                                                NSURLResponse * _Nullable response,
                                                                                                NSError * _Nullable downloadError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        void (^cleanup)(void) = ^{
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:trackID];
            [strongSelf.miniStreamingDownloadTasksByTrackID removeObjectForKey:trackID];
        };

        if (downloadError != nil || location == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanup();
                SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_failed track=%@ error=%@",
                                                         trackID,
                                                         downloadError.localizedDescription ?: @"unknown"]);
                if ([strongSelf.miniStreamingActiveTrackID isEqualToString:trackID]) {
                    strongSelf.miniStreamingActiveTrackID = nil;
                }
            });
            return;
        }

        NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
        NSString *title = SonoraSanitizedFileComponent(payload[@"title"]);
        if (title.length == 0) {
            title = trackID;
        }
        NSString *artist = SonoraSanitizedFileComponent(payload[@"artist"]);
        NSString *baseName = (artist.length > 0) ? [NSString stringWithFormat:@"%@ - %@", artist, title] : title;

        NSString *resolvedExtension = SonoraTrimmedStringValue(response.suggestedFilename.pathExtension);
        if (resolvedExtension.length == 0) {
            resolvedExtension = SonoraTrimmedStringValue(downloadURL.pathExtension);
        }
        if (resolvedExtension.length == 0) {
            resolvedExtension = @"mp3";
        }

        NSURL *destinationURL = [strongSelf availableDestinationURLInDirectory:musicDirectoryURL
                                                                       baseName:baseName
                                                                      extension:resolvedExtension];
        NSError *moveError = nil;
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:location toURL:destinationURL error:&moveError];
        if (!moved || moveError != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanup();
                SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_move_failed track=%@ error=%@",
                                                         trackID,
                                                         moveError.localizedDescription ?: @"unknown"]);
                if ([strongSelf.miniStreamingActiveTrackID isEqualToString:trackID]) {
                    strongSelf.miniStreamingActiveTrackID = nil;
                }
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            cleanup();
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_completed track=%@ path=%@",
                                                     trackID,
                                                     destinationURL.path ?: @""]);
            [strongSelf reloadTracks];
            [strongSelf syncMiniStreamingPlaybackWithInstalledTrackAtURL:destinationURL
                                                                 trackID:trackID];
        });
    }];
    downloadTask.priority = NSURLSessionTaskPriorityLow;
    self.miniStreamingDownloadTasksByTrackID[trackID] = downloadTask;
    [downloadTask resume];
}

- (void)scheduleMiniStreamingBackgroundDownloadFromURL:(NSURL *)downloadURL
                                                payload:(NSDictionary<NSString *, id> *)payload
                                                trackID:(NSString *)trackID {
    if (downloadURL == nil || trackID.length == 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSString *currentTrackID = strongSelf.miniStreamingCurrentPlaybackTrackID ?: @"";
        if (currentTrackID.length > 0 && ![currentTrackID isEqualToString:trackID]) {
            return;
        }
        [strongSelf startMiniStreamingBackgroundDownloadFromURL:downloadURL
                                                        payload:payload
                                                        trackID:trackID];
    });
}

- (void)stopMiniStreamingPlaceholderIfNeededForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentTrack];
    if (![currentTrackID isEqualToString:trackID]) {
        return;
    }
    if (![self isMiniStreamingPlaceholderTrack:currentTrack]) {
        return;
    }
    if (playback.isPlaying) {
        [playback togglePlayPause];
    }
}

- (BOOL)miniStreamingResolveCooldownActiveForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return NO;
    }

    NSDate *retryAfter = self.miniStreamingResolveRetryAfterByTrackID[trackID];
    if (retryAfter == nil) {
        return NO;
    }

    NSTimeInterval remaining = [retryAfter timeIntervalSinceNow];
    if (remaining <= 0.0) {
        [self.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:trackID];
        return NO;
    }

    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_skip_cooldown track=%@ wait=%.1f",
                                             trackID,
                                             remaining]);
    return YES;
}

- (void)startMiniStreamingInstallIfNeededForTrack:(SonoraMiniStreamingTrack *)track
                                       showErrorUI:(BOOL)showErrorUI {
    if (track == nil || track.trackID.length == 0) {
        return;
    }

    SonoraTrack *knownInstalledTrack = [self knownInstalledMiniStreamingTrackForTrack:track];
    if (knownInstalledTrack != nil && knownInstalledTrack.url.path.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:knownInstalledTrack.url.path]) {
        [self.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_installed track=%@", track.trackID]);
        [self syncMiniStreamingPlaybackWithInstalledTrackAtURL:knownInstalledTrack.url trackID:track.trackID];
        return;
    }

    NSDictionary<NSString *, id> *cachedPayload = self.miniStreamingResolvedPayloadByTrackID[track.trackID];
    if ([self isUsableMiniStreamingPayload:cachedPayload]) {
        [self.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_stream_cached_payload track=%@", track.trackID]);
        SonoraTrack *currentPlaybackTrack = SonoraPlaybackManager.sharedManager.currentTrack;
        NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
        BOOL shouldStartPlayback = showErrorUI ||
                                   [self isMiniStreamingPlaceholderTrack:currentPlaybackTrack] ||
                                   [currentTrackID isEqualToString:track.trackID];
        if (shouldStartPlayback) {
            [self playMiniStreamingPlaybackQueueIfCurrentForTrack:track];
        }
        NSURL *cachedDownloadURL = [self miniStreamingDownloadURLFromPayload:cachedPayload];
        if (cachedDownloadURL != nil) {
            [self scheduleMiniStreamingBackgroundDownloadFromURL:cachedDownloadURL
                                                         payload:cachedPayload
                                                         trackID:track.trackID];
        }
        return;
    } else if (cachedPayload != nil) {
        [self.miniStreamingResolvedPayloadByTrackID removeObjectForKey:track.trackID];
    }

    if ([self miniStreamingResolveCooldownActiveForTrackID:track.trackID]) {
        [self stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
        return;
    }

    if ([self.miniStreamingInstallingTrackIDs containsObject:track.trackID]) {
        return;
    }

    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_start track=%@", track.trackID]);
    [self.miniStreamingInstallingTrackIDs addObject:track.trackID];
    __weak typeof(self) weakSelf = self;
    [self.miniStreamingClient resolveDownloadForTrackID:track.trackID
                                             completion:^(NSDictionary<NSString *,id> * _Nullable payload, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (error != nil || payload == nil) {
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
            strongSelf.miniStreamingResolveRetryAfterByTrackID[track.trackID] = [NSDate dateWithTimeIntervalSinceNow:20.0];
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_failed track=%@ error=%@",
                                                     track.trackID,
                                                     error.localizedDescription ?: @"unknown"]);
            if ([strongSelf.miniStreamingActiveTrackID isEqualToString:track.trackID]) {
                strongSelf.miniStreamingActiveTrackID = nil;
            }
            [strongSelf stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
            if (showErrorUI) {
                NSString *message = error.localizedDescription ?: @"Could not resolve download link.";
                SonoraPresentAlert(strongSelf, @"Install Failed", message);
            }
            return;
        }

        if (![strongSelf isUsableMiniStreamingPayload:payload]) {
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
            strongSelf.miniStreamingResolveRetryAfterByTrackID[track.trackID] = [NSDate dateWithTimeIntervalSinceNow:20.0];
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_invalid_payload track=%@",
                                                     track.trackID]);
            if ([strongSelf.miniStreamingActiveTrackID isEqualToString:track.trackID]) {
                strongSelf.miniStreamingActiveTrackID = nil;
            }
            [strongSelf stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
            if (showErrorUI) {
                SonoraPresentAlert(strongSelf, @"Install Failed", @"RapidAPI returned invalid download URL.");
            }
            return;
        }

        [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        [strongSelf.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:track.trackID];
        strongSelf.miniStreamingResolvedPayloadByTrackID[track.trackID] = payload;
        NSURL *downloadURL = [strongSelf miniStreamingDownloadURLFromPayload:payload];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_succeeded track=%@ url=%@",
                                                 track.trackID,
                                                 downloadURL.absoluteString ?: @""]);
        SonoraTrack *currentPlaybackTrack = SonoraPlaybackManager.sharedManager.currentTrack;
        NSString *currentTrackID = [strongSelf miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
        BOOL shouldStartPlayback = showErrorUI ||
                                   [strongSelf isMiniStreamingPlaceholderTrack:currentPlaybackTrack] ||
                                   [currentTrackID isEqualToString:track.trackID];
        if (shouldStartPlayback) {
            [strongSelf playMiniStreamingPlaybackQueueIfCurrentForTrack:track];
        }
        [strongSelf scheduleMiniStreamingBackgroundDownloadFromURL:downloadURL
                                                           payload:payload
                                                           trackID:track.trackID];
    }];
}

- (void)installMiniStreamingTrack:(SonoraMiniStreamingTrack *)track
                             queue:(NSArray<SonoraMiniStreamingTrack *> *)queue
                        startIndex:(NSInteger)startIndex
                  preferredArtwork:(UIImage * _Nullable)preferredArtwork {
    if (track == nil || track.trackID.length == 0) {
        return;
    }
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"install_tap track=%@", track.trackID]);
    [self.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:track.trackID];

    if (![self.miniStreamingClient isConfigured]) {
        SonoraPresentAlert(self,
                       @"Mini Streaming Disabled",
                       @"Set BACKEND_BASE_URL in scheme env or Info.plist.");
        return;
    }

    if (preferredArtwork != nil && track.artworkURL.length > 0) {
        [self.miniStreamingArtworkCache setObject:preferredArtwork forKey:track.artworkURL];
    }
    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = [self miniStreamingQueueFromContext:queue selectedTrack:track];
    if (normalizedQueue.count == 0) {
        return;
    }
    [self prepareMiniStreamingInstallForTrack:track queue:normalizedQueue startIndex:startIndex];
    [self startMiniStreamingInstallIfNeededForTrack:track showErrorUI:YES];
}

- (void)addMusicTapped {
    if ([self isLibraryAtOrAboveStorageLimit]) {
        [self presentStorageLimitReachedAlert];
        return;
    }
    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        UTType *audioType = [UTType typeWithIdentifier:@"public.audio"];
        if (audioType != nil) {
            picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[audioType] asCopy:YES];
        }
    }
    if (picker == nil) {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"]
                                                                        inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (urls.count == 0) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    NSSet<NSString *> *allowedExtensions = SonoraSupportedAudioExtensions();
    NSUInteger importedCount = 0;
    NSUInteger failedCount = 0;
    NSUInteger skippedUnsupportedCount = 0;
    BOOL blockedByStorageLimit = NO;

    for (NSURL *sourceURL in urls) {
        if (sourceURL == nil) {
            failedCount += 1;
            continue;
        }
        if ([self isLibraryAtOrAboveStorageLimit]) {
            blockedByStorageLimit = YES;
            break;
        }

        BOOL grantedAccess = [sourceURL startAccessingSecurityScopedResource];
        @try {
            NSString *extension = SonoraTrimmedStringValue(sourceURL.pathExtension).lowercaseString;
            if (extension.length == 0 || ![allowedExtensions containsObject:extension]) {
                skippedUnsupportedCount += 1;
                continue;
            }

            NSString *baseName = sourceURL.lastPathComponent.stringByDeletingPathExtension;
            if (baseName.length == 0) {
                baseName = @"track";
            }
            NSURL *destinationURL = [self availableDestinationURLInDirectory:musicDirectoryURL
                                                                     baseName:baseName
                                                                    extension:extension];
            NSError *copyError = nil;
            BOOL copied = [fileManager copyItemAtURL:sourceURL toURL:destinationURL error:&copyError];
            if (!copied || copyError != nil) {
                failedCount += 1;
                continue;
            }
            importedCount += 1;
        } @finally {
            if (grantedAccess) {
                [sourceURL stopAccessingSecurityScopedResource];
            }
        }
    }

    [self reloadTracks];

    if (blockedByStorageLimit) {
        [self presentStorageLimitReachedAlert];
    }
    if (failedCount == 0 && skippedUnsupportedCount == 0 && !blockedByStorageLimit) {
        if (importedCount == 0) {
            SonoraPresentAlert(self, @"No Music Added", @"No supported audio files were selected.");
        }
        return;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (importedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Imported: %lu", (unsigned long)importedCount]];
    }
    if (skippedUnsupportedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Unsupported files skipped: %lu", (unsigned long)skippedUnsupportedCount]];
    }
    if (failedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Failed: %lu", (unsigned long)failedCount]];
    }
    if (blockedByStorageLimit) {
        [parts addObject:@"Stopped: storage limit reached"];
    }
    NSString *message = [parts componentsJoinedByString:@"\n"];
    if (message.length == 0) {
        message = @"Could not import selected files.";
    }
    SonoraPresentAlert(self, @"Import Result", message);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (unsigned long long)currentLibraryUsageBytes {
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    if (musicDirectoryURL == nil) {
        return 0ULL;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSURL *> *enumerator =
    [fileManager enumeratorAtURL:musicDirectoryURL
      includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                    errorHandler:nil];
    unsigned long long totalBytes = 0ULL;
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue) {
            continue;
        }
        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        totalBytes += fileSize.unsignedLongLongValue;
    }
    return totalBytes;
}

- (unsigned long long)maxLibraryStorageBytes {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey];
    NSInteger valueMB = raw;
    if (valueMB <= 0) {
        return ULLONG_MAX;
    }
    NSArray<NSNumber *> *allowed = @[@512, @1024, @2048, @3072, @4096, @6144, @8192];
    NSInteger nearest = allowed.firstObject.integerValue;
    NSInteger delta = labs(valueMB - nearest);
    for (NSNumber *candidate in allowed) {
        NSInteger current = candidate.integerValue;
        NSInteger currentDelta = labs(valueMB - current);
        if (currentDelta < delta) {
            delta = currentDelta;
            nearest = current;
        }
    }
    return ((unsigned long long)nearest) * 1024ULL * 1024ULL;
}

- (BOOL)isLibraryAtOrAboveStorageLimit {
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return NO;
    }
    return [self currentLibraryUsageBytes] >= maxBytes;
}

- (void)presentStorageLimitReachedAlert {
    unsigned long long usedBytes = [self currentLibraryUsageBytes];
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return;
    }
    NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                        countStyle:NSByteCountFormatterCountStyleFile];
    NSString *maxText = [NSByteCountFormatter stringFromByteCount:(long long)maxBytes
                                                       countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = [NSString stringWithFormat:@"Library size %@ reached/over max %@.\nAdding music is blocked until you free space or increase Max player space in Settings.",
                         usedText,
                         maxText];
    SonoraPresentAlert(self, @"Storage limit reached", message);
}

- (void)refreshNavigationItemsForMusicSelectionState {
    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : pageTitle;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (!self.musicOnlyMode) {
        UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(searchButtonTapped)];
        SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
        self.navigationItem.rightBarButtonItems = @[searchItem];
        return;
    }

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelMusicSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(deleteSelectedTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                               target:self
                                                                               action:@selector(addMusicTapped)];
    SonoraConfigureNavigationIconBarButtonItem(addItem, @"Add Music");
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItems = @[searchItem, addItem];
}

- (void)cancelMusicSelectionTapped {
    [self setMusicSelectionModeEnabled:NO];
}

- (void)setMusicSelectionModeEnabled:(BOOL)enabled {
    if (!self.musicOnlyMode && enabled) {
        return;
    }
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)trackForMusicTableIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return nil;
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks) {
        return nil;
    }
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleMusicSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setMusicSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForMusicSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.musicOnlyMode || gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self trackForMusicTableIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setMusicSelectionModeEnabled:YES];
    [self toggleMusicSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
}

- (void)deleteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSArray<NSString *> *targetIDs = [self.selectedTrackIDs.array copy];
    NSError *firstError = nil;
    for (NSString *trackID in targetIDs) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:trackID error:&deleteError];
        if (!removed && firstError == nil) {
            firstError = deleteError;
        }
        if (removed) {
            [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
            [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:trackID];
        }
    }

    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
    if (firstError != nil) {
        NSString *message = firstError.localizedDescription ?: @"Could not delete one or more tracks.";
        SonoraPresentAlert(self, @"Delete Failed", message);
    }
}

- (SonoraSearchSectionType)sectionTypeForIndex:(NSInteger)section {
    if (section < 0 || section >= self.visibleSections.count) {
        return SonoraSearchSectionTypeTracks;
    }
    return (SonoraSearchSectionType)self.visibleSections[section].integerValue;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return 0;
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.artistResults.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return nil;
    }
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    if (normalizedQuery.length == 0) {
        return nil;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return nil;
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Tracks";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return [UITableViewCell new];
    }
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeTracks) {
        SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicTrackCell" forIndexPath:indexPath];

        SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
        SonoraTrack *track = self.filteredTracks[indexPath.row];
        SonoraTrack *currentTrack = playback.currentTrack;
        BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
        BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
        BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

        [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
        cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicSearchMetaCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MusicSearchMetaCell"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
            cell.imageView.image = [UIImage systemImageNamed:@"music.note.list"];
            cell.textLabel.text = playlist.name ?: @"Playlist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
        }
    } else if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row < self.artistResults.count) {
            NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
            NSArray *matchedTracks = artistEntry[@"tracks"];
            cell.imageView.image = [UIImage systemImageNamed:@"person.fill"];
            cell.textLabel.text = artistEntry[@"title"] ?: @"Artist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)matchedTracks.count];
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.musicOnlyMode) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self trackForMusicTableIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleMusicSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row >= self.artistResults.count) {
            return;
        }
        NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
        NSString *artistTitle = artistEntry[@"title"] ?: @"";
        self.searchQuery = artistTitle;
        self.searchController.searchBar.text = artistTitle;
        [self applySearchFilterAndReload];
        [self refreshMiniStreamingForCurrentQuery];
        return;
    }

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    NSArray<SonoraTrack *> *playlistQueue = self.tracks;
    if (playlistQueue.count == 0) {
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    NSInteger playlistIndex = SonoraIndexOfTrackByIdentifier(playlistQueue, selectedTrack.identifier);
    if (playlistIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, playlistQueue);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:playlistQueue startIndex:playlistIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                       __unused UIView * _Nonnull sourceView,
                                                                                       void (^ _Nonnull completionHandler)(BOOL)) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:track.identifier error:&deleteError];
        if (!removed) {
            NSString *message = deleteError.localizedDescription ?: @"Could not delete track file.";
            SonoraPresentAlert(self, @"Delete Failed", message);
            completionHandler(NO);
            return;
        }

        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:track.identifier];
        [self reloadTracks];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";
    UIColor *backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = backgroundColor;

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (NSString *)titleForSearchSectionType:(SonoraSearchSectionType)sectionType {
    switch (sectionType) {
        case SonoraSearchSectionTypeMiniStreaming:
            return @"Tracks";
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Music";
    }
    return @"";
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }

    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return self.miniStreamingTracks.count;
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.miniStreamingArtists.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return [UICollectionViewCell new];
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
        SonoraMiniStreamingListCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMiniStreamingListCellReuseID
                                                                                       forIndexPath:indexPath];
        if (indexPath.item < self.miniStreamingTracks.count) {
            SonoraMiniStreamingTrack *track = self.miniStreamingTracks[indexPath.item];
            UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
            [self loadMiniStreamingArtworkIfNeededForTrack:track];
            SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
            NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:playback.currentTrack];
            BOOL isCurrent = [currentTrackID isEqualToString:track.trackID];
            BOOL sameQueue = [self miniStreamingPlaybackQueueMatchesMiniTracks:self.miniStreamingTracks];
            BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);
            NSString *subtitle = track.artists.length > 0 ? track.artists : @"Spotify";
            [cell configureWithTitle:track.title
                            subtitle:subtitle
                         durationText:SonoraFormatDuration(track.duration)
                               image:artwork
                            isCurrent:isCurrent
               showsPlaybackIndicator:showsPlaybackIndicator
                       showsSeparator:(indexPath.item + 1 < self.miniStreamingTracks.count)];
        }
        return cell;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        SonoraMusicSearchCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID
                                                                                     forIndexPath:indexPath];
        if (indexPath.item < self.miniStreamingArtists.count) {
            SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[indexPath.item];
            UIImage *artwork = [self cachedMiniStreamingArtworkForURL:artist.artworkURL];
            [self loadMiniStreamingArtworkIfNeededForURL:artist.artworkURL];
            [cell configureWithTitle:artist.name subtitle:@"Artist" image:artwork];
        }
        return cell;
    }

    SonoraMusicSearchCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID
                                                                                 forIndexPath:indexPath];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
            UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                   library:SonoraLibraryManager.sharedManager
                                                                      size:CGSizeMake(220.0, 220.0)];
            NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
            [cell configureWithTitle:playlist.name subtitle:subtitle image:cover];
        }
    } else {
        if (indexPath.item < self.filteredTracks.count) {
            SonoraTrack *track = self.filteredTracks[indexPath.item];
            NSString *trackTitle = track.title.length > 0 ? track.title :
                (track.fileName.length > 0 ? track.fileName.stringByDeletingPathExtension : @"Unknown track");
            NSString *subtitle = track.artist.length > 0 ? track.artist : @"Track";
            [cell configureWithTitle:trackTitle subtitle:subtitle image:track.artwork];
        }
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
              viewForSupplementaryElementOfKind:(NSString *)kind
                                    atIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView ||
        ![kind isEqualToString:UICollectionElementKindSectionHeader] ||
        self.musicOnlyMode) {
        return [UICollectionReusableView new];
    }

    SonoraMusicSearchHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                          withReuseIdentifier:SonoraMusicSearchHeaderReuseID
                                                                                 forIndexPath:indexPath];
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    [header configureWithTitle:[self titleForSearchSectionType:sectionType]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return;
    }
    [self.searchController.searchBar resignFirstResponder];

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
        if (indexPath.item >= self.miniStreamingTracks.count) {
            return;
        }
        SonoraMiniStreamingTrack *track = self.miniStreamingTracks[indexPath.item];
        UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
        NSArray<SonoraMiniStreamingTrack *> *queueSnapshot = [self.miniStreamingTracks copy] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installMiniStreamingTrack:track
                                      queue:queueSnapshot
                                 startIndex:indexPath.item
                           preferredArtwork:artwork];
        });
        return;
    }

    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.item >= self.miniStreamingArtists.count) {
            return;
        }
        SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[indexPath.item];
        if (artist == nil || artist.artistID.length == 0) {
            return;
        }

        __weak typeof(self) weakSelf = self;
        SonoraMiniStreamingArtistViewController *artistView = [[SonoraMiniStreamingArtistViewController alloc] initWithArtist:artist
                                                                                                                        client:self.miniStreamingClient
                                                                                                                installHandler:^(SonoraMiniStreamingTrack * _Nonnull track,
                                                                                                                                NSArray<SonoraMiniStreamingTrack *> * _Nonnull queue,
                                                                                                                                NSInteger startIndex,
                                                                                                                                UIImage * _Nullable artwork) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf installMiniStreamingTrack:track
                                            queue:queue
                                       startIndex:startIndex
                                 preferredArtwork:artwork];
        }];
        artistView.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:artistView animated:YES];
        return;
    }

    if (indexPath.item >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.item];
    NSInteger startIndex = SonoraIndexOfTrackByIdentifier(self.tracks, selectedTrack.identifier);
    if (startIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:self.tracks startIndex:startIndex];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self refreshMiniStreamingForCurrentQuery];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.musicOnlyMode && (scrollView == self.tableView || scrollView == self.searchCollectionView)) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlists

@interface SonoraPlaylistsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL syncingLovelyPlaylist;
@property (nonatomic, assign) BOOL needsLovelyRefresh;

@end

@implementation SonoraPlaylistsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Playlists")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(markNeedsLovelyRefresh)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    self.needsLovelyRefresh = YES;
    [self reloadPlaylists];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    if (self.needsLovelyRefresh) {
        [self reloadPlaylists];
    }
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)markNeedsLovelyRefresh {
    self.needsLovelyRefresh = YES;
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 56.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraPlaylistCell.class forCellReuseIdentifier:@"PlaylistCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Playlists");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredPlaylists.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.playlists.count == 0) {
        label.text = @"Tap + to create a playlist";
    } else {
        label.text = @"No matching playlists.";
    }
    self.tableView.backgroundView = label;
}

- (void)addPlaylistTapped {
    SonoraPlaylistNameViewController *nameVC = [[SonoraPlaylistNameViewController alloc] init];
    nameVC.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:nameVC animated:YES];
}

- (NSArray<NSString *> *)lovelyTrackIDsFromLibraryTracks:(NSArray<SonoraTrack *> *)libraryTracks {
    if (libraryTracks.count == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }
    if (trackIDs.count == 0) {
        return @[];
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    SonoraFavoritesStore *favoritesStore = SonoraFavoritesStore.sharedStore;

    NSMutableArray<SonoraTrack *> *eligibleTracks = [NSMutableArray array];
    for (SonoraTrack *track in libraryTracks) {
        NSDictionary<NSString *, NSNumber *> *metrics = analyticsByTrackID[track.identifier] ?: @{};
        NSInteger playCount = [metrics[@"playCount"] integerValue];
        NSInteger skipCount = [metrics[@"skipCount"] integerValue];
        double score = [metrics[@"score"] doubleValue];
        NSInteger activity = playCount + skipCount;
        BOOL isFavorite = [favoritesStore isTrackFavoriteByID:track.identifier];

        // Rule:
        // (playCount + skipCount) >= 3
        // AND ((isFavorite && score >= 0.60 && playCount >= 2) || (score >= 0.80 && playCount >= 4))
        // AND skipCount <= 3
        BOOL matchesFavoriteRule = (isFavorite && score >= 0.60 && playCount >= 2);
        BOOL matchesHighScoreRule = (score >= 0.80 && playCount >= 4);
        if (activity < 3 || skipCount > 3 || !(matchesFavoriteRule || matchesHighScoreRule)) {
            continue;
        }

        [eligibleTracks addObject:track];
    }

    if (eligibleTracks.count == 0) {
        return @[];
    }

    [eligibleTracks sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};

        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];

        double leftScore = [leftMetrics[@"score"] doubleValue];
        double rightScore = [rightMetrics[@"score"] doubleValue];
        BOOL leftFavorite = [favoritesStore isTrackFavoriteByID:left.identifier];
        BOOL rightFavorite = [favoritesStore isTrackFavoriteByID:right.identifier];

        if (leftScore > rightScore) {
            return NSOrderedAscending;
        }
        if (leftScore < rightScore) {
            return NSOrderedDescending;
        }
        if (leftPlay > rightPlay) {
            return NSOrderedAscending;
        }
        if (leftPlay < rightPlay) {
            return NSOrderedDescending;
        }
        if (leftSkip < rightSkip) {
            return NSOrderedAscending;
        }
        if (leftSkip > rightSkip) {
            return NSOrderedDescending;
        }
        if (leftFavorite != rightFavorite) {
            return leftFavorite ? NSOrderedAscending : NSOrderedDescending;
        }

        NSString *leftTitle = left.title.length > 0 ? left.title : left.fileName;
        NSString *rightTitle = right.title.length > 0 ? right.title : right.fileName;
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:eligibleTracks.count];
    for (SonoraTrack *track in eligibleTracks) {
        if (track.identifier.length > 0) {
            [orderedIDs addObject:track.identifier];
        }
    }
    return [orderedIDs copy];
}

- (void)syncLovelyPlaylistIfNeeded {
    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }
    NSArray<NSString *> *lovelyTrackIDs = [self lovelyTrackIDsFromLibraryTracks:libraryTracks];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *storedPlaylistID = [defaults stringForKey:SonoraLovelyPlaylistDefaultsKey];

    SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
    SonoraPlaylist *lovelyPlaylist = (storedPlaylistID.length > 0)
    ? [store playlistWithID:storedPlaylistID]
    : nil;
    if (lovelyPlaylist == nil) {
        for (SonoraPlaylist *playlist in store.playlists) {
            if ([playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame) {
                lovelyPlaylist = playlist;
                [defaults setObject:playlist.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
                break;
            }
        }
    }

    if (lovelyPlaylist == nil) {
        [defaults removeObjectForKey:SonoraLovelyPlaylistDefaultsKey];
        [defaults removeObjectForKey:SonoraLovelyPlaylistCoverMarkerKey];
        if (lovelyTrackIDs.count == 0) {
            return;
        }

        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        SonoraPlaylist *created = [store addPlaylistWithName:@"Lovely songs"
                                                trackIDs:lovelyTrackIDs
                                              coverImage:coverImage];
        if (created != nil) {
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
        return;
    }

    if (![lovelyPlaylist.name isEqualToString:@"Lovely songs"]) {
        [store renamePlaylistWithID:lovelyPlaylist.playlistID newName:@"Lovely songs"];
    }

    if (![lovelyPlaylist.trackIDs isEqualToArray:lovelyTrackIDs]) {
        [store replaceTrackIDs:lovelyTrackIDs forPlaylistID:lovelyPlaylist.playlistID];
    }

    NSString *coverMarker = [defaults stringForKey:SonoraLovelyPlaylistCoverMarkerKey];
    BOOL shouldRefreshCover = (lovelyPlaylist.customCoverFileName.length == 0 ||
                               ![coverMarker isEqualToString:lovelyPlaylist.playlistID]);
    if (shouldRefreshCover) {
        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        BOOL coverSet = [store setCustomCoverImage:coverImage forPlaylistID:lovelyPlaylist.playlistID];
        if (coverSet) {
            [defaults setObject:lovelyPlaylist.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
    }
}

- (void)reloadPlaylists {
    if (self.syncingLovelyPlaylist) {
        return;
    }

    self.syncingLovelyPlaylist = YES;
    @try {
        SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
        [store reloadPlaylists];
        [self syncLovelyPlaylistIfNeeded];
        [store reloadPlaylists];

        NSMutableArray<SonoraPlaylist *> *orderedPlaylists = [store.playlists mutableCopy];
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        if (lovelyID.length > 0) {
            NSUInteger index = [orderedPlaylists indexOfObjectPassingTest:^BOOL(SonoraPlaylist * _Nonnull playlist, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
                return [playlist.playlistID isEqualToString:lovelyID];
            }];
            if (index != NSNotFound) {
                SonoraPlaylist *lovely = orderedPlaylists[index];
                if (lovely.trackIDs.count == 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                } else if (index != 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                    [orderedPlaylists insertObject:lovely atIndex:0];
                }
            }
        }

        NSArray<SonoraPlaylist *> *likedSharedPlaylists = [SonoraSharedPlaylistStore.sharedStore likedPlaylists];
        if (likedSharedPlaylists.count > 0) {
            [orderedPlaylists addObjectsFromArray:likedSharedPlaylists];
        }

        self.playlists = [orderedPlaylists copy];
        [self applySearchFilterAndReload];
    } @finally {
        self.needsLovelyRefresh = NO;
        self.syncingLovelyPlaylist = NO;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredPlaylists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraPlaylistCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistCell" forIndexPath:indexPath];

    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    UIImage *cover = nil;
    NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
    SonoraSharedPlaylistSnapshot *sharedSnapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:playlist.playlistID];
    if (sharedSnapshot != nil) {
        cover = sharedSnapshot.coverImage ?: sharedSnapshot.tracks.firstObject.artwork;
        BOOL cacheAudioEnabled = [NSUserDefaults.standardUserDefaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey];
        NSUInteger totalTracks = sharedSnapshot.tracks.count;
        NSUInteger cachedTracks = 0;
        for (SonoraTrack *track in sharedSnapshot.tracks) {
            if (track.url.isFileURL && track.url.path.length > 0 &&
                [NSFileManager.defaultManager fileExistsAtPath:track.url.path]) {
                cachedTracks += 1;
            }
        }
        if (!cacheAudioEnabled) {
            subtitle = @"Online playlist • Streaming";
        } else if (totalTracks == 0) {
            subtitle = @"Online playlist";
        } else if (cachedTracks >= totalTracks) {
            subtitle = @"Online playlist • Cached";
        } else {
            subtitle = [NSString stringWithFormat:@"Online playlist • Cached %lu/%lu",
                        (unsigned long)cachedTracks,
                        (unsigned long)totalTracks];
        }
    } else {
        cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                         library:SonoraLibraryManager.sharedManager
                                                            size:CGSizeMake(160.0, 160.0)];
    }

    [cell configureWithName:playlist.name subtitle:subtitle artwork:cover];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredPlaylists.count) {
        return;
    }
    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Favorites

@interface SonoraFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraFavoritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Favorites";
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Favorites")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItem = searchItem;

    [self setupTableView];
    [self setupSearch];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadFavorites)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [self refreshNavigationItemsForFavoritesSelectionState];
    [self reloadFavorites];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.hidesBackButton = YES;
    [self refreshNavigationItemsForFavoritesSelectionState];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"FavoriteTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Favorites");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    if (self.tracks.count == 0) {
        label.text = @"No favorites yet.\nTap heart in player to add tracks.";
    } else {
        label.text = @"No search results.";
    }
    self.tableView.backgroundView = label;
}

- (void)reloadFavorites {
    if (SonoraLibraryManager.sharedManager.tracks.count == 0 &&
        SonoraFavoritesStore.sharedStore.favoriteTrackIDs.count > 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    self.tracks = [SonoraFavoritesStore.sharedStore favoriteTracksWithLibrary:SonoraLibraryManager.sharedManager];
    [self applySearchFilterAndReload];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadFavorites];
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)refreshNavigationItemsForFavoritesSelectionState {
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : @"Favorites";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelFavoritesSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedFavoritesTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedFavoritesTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItems = @[searchItem];
}

- (void)cancelFavoritesSelectionTapped {
    [self setFavoritesSelectionModeEnabled:NO];
}

- (void)setFavoritesSelectionModeEnabled:(BOOL)enabled {
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForFavoritesSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)favoriteTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleFavoritesSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setFavoritesSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForFavoritesSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self favoriteTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setFavoritesSelectionModeEnabled:YES];
    [self toggleFavoritesSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

- (void)removeSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FavoriteTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL showsPlaybackIndicator = (isCurrent && playback.isPlaying);
    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self favoriteTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleFavoritesSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:@"Unfollow"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [self reloadFavorites];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"heart.slash.fill"];
    removeAction.backgroundColor = [UIColor colorWithWhite:0.40 alpha:1.0];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    (void)indexPath;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlist Name Step

@interface SonoraPlaylistNameViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UILabel *counterLabel;

@end

@implementation SonoraPlaylistNameViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Create Playlist";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self updateNameUI];
}

- (void)setupUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:content];

    UIView *heroCard = [[UIView alloc] init];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    heroCard.backgroundColor = UIColor.clearColor;

    UILabel *heroTitle = [[UILabel alloc] init];
    heroTitle.translatesAutoresizingMaskIntoConstraints = NO;
    heroTitle.text = @"Name Your Playlist";
    heroTitle.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightBold];
    heroTitle.textColor = UIColor.labelColor;
    heroTitle.numberOfLines = 1;

    [heroCard addSubview:heroTitle];

    UIView *inputCard = [[UIView alloc] init];
    inputCard.translatesAutoresizingMaskIntoConstraints = NO;
    inputCard.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.06];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    inputCard.layer.cornerRadius = 18.0;
    inputCard.layer.borderWidth = 1.0;
    inputCard.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.14];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.08];
    }].CGColor;

    UILabel *inputTitle = [[UILabel alloc] init];
    inputTitle.translatesAutoresizingMaskIntoConstraints = NO;
    inputTitle.text = @"Playlist Name";
    inputTitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    inputTitle.textColor = UIColor.secondaryLabelColor;

    UITextField *nameField = [[UITextField alloc] init];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.borderStyle = UITextBorderStyleNone;
    nameField.placeholder = @"Example: Late Night Drive";
    nameField.returnKeyType = UIReturnKeyNext;
    nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    nameField.delegate = self;
    nameField.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    nameField.textColor = UIColor.labelColor;
    [nameField addTarget:self action:@selector(nameDidChange) forControlEvents:UIControlEventEditingChanged];
    self.nameField = nameField;

    UILabel *counterLabel = [[UILabel alloc] init];
    counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    counterLabel.textColor = UIColor.secondaryLabelColor;
    counterLabel.textAlignment = NSTextAlignmentRight;
    self.counterLabel = counterLabel;

    [inputCard addSubview:inputTitle];
    [inputCard addSubview:nameField];
    [inputCard addSubview:counterLabel];

    UIButton *nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [nextButton setTitle:@"Next: Choose Music" forState:UIControlStateNormal];
    [nextButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    nextButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    nextButton.layer.cornerRadius = 14.0;
    [nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    self.nextButton = nextButton;

    [content addSubview:heroCard];
    [content addSubview:inputCard];
    [self.view addSubview:nextButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:nextButton.topAnchor constant:-12.0],

        [content.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],

        [heroCard.topAnchor constraintEqualToAnchor:content.topAnchor constant:16.0],
        [heroCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [heroCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [heroCard.heightAnchor constraintEqualToConstant:58.0],

        [heroTitle.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:8.0],
        [heroTitle.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:14.0],
        [heroTitle.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],

        [inputCard.topAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:10.0],
        [inputCard.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [inputCard.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [inputCard.heightAnchor constraintEqualToConstant:118.0],

        [inputTitle.topAnchor constraintEqualToAnchor:inputCard.topAnchor constant:14.0],
        [inputTitle.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor constant:14.0],
        [inputTitle.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor constant:-14.0],

        [nameField.topAnchor constraintEqualToAnchor:inputTitle.bottomAnchor constant:8.0],
        [nameField.leadingAnchor constraintEqualToAnchor:inputTitle.leadingAnchor],
        [nameField.trailingAnchor constraintEqualToAnchor:inputTitle.trailingAnchor],
        [nameField.heightAnchor constraintEqualToConstant:42.0],

        [counterLabel.trailingAnchor constraintEqualToAnchor:nameField.trailingAnchor],
        [counterLabel.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:-10.0],
        [counterLabel.widthAnchor constraintEqualToConstant:62.0],

        [content.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:24.0],

        [nextButton.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor],
        [nextButton.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor],
        [nextButton.heightAnchor constraintEqualToConstant:52.0]
    ]];

    if (@available(iOS 15.0, *)) {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12.0]];
    } else {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)nameDidChange {
    [self updateNameUI];
}

- (void)updateNameUI {
    NSString *trimmed = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger length = self.nameField.text.length;
    if (length > 32) {
        self.nameField.text = [self.nameField.text substringToIndex:32];
        length = 32;
    }

    self.counterLabel.text = [NSString stringWithFormat:@"%lu/32", (unsigned long)length];

    BOOL enabled = (trimmed.length > 0);
    self.nextButton.enabled = enabled;
    self.nextButton.alpha = enabled ? 1.0 : 0.45;
    self.nextButton.backgroundColor = enabled ? SonoraAccentYellowColor() : [UIColor colorWithWhite:0.65 alpha:0.4];
}

- (void)nextTapped {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) {
        SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
        return;
    }

    NSArray<SonoraTrack *> *tracks = [SonoraLibraryManager.sharedManager reloadTracks];
    if (tracks.count == 0) {
        SonoraPresentAlert(self, @"No Music", @"Add music files in Files app first.");
        return;
    }

    SonoraPlaylistTrackPickerViewController *picker = [[SonoraPlaylistTrackPickerViewController alloc] initWithPlaylistName:name tracks:tracks];
    picker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:picker animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    (void)textField;
    [self nextTapped];
    return YES;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *current = textField.text ?: @"";
    NSString *updated = [current stringByReplacingCharactersInRange:range withString:string ?: @""];
    return (updated.length <= 32);
}

@end

#pragma mark - Playlist Track Step

@interface SonoraPlaylistTrackPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistName;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;

@end

@implementation SonoraPlaylistTrackPickerViewController

- (instancetype)initWithPlaylistName:(NSString *)playlistName tracks:(NSArray<SonoraTrack *> *)tracks {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistName = [playlistName copy];
        _tracks = [[SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:tracks] copy];
        _filteredTracks = _tracks;
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Select Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Create"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(createTapped)];

    [self setupTableView];
    [self setupSearch];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateSearchControllerAttachment];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"TrackPickCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Tracks");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
}

- (void)createTapped {
    if (self.selectedTrackIDs.count == 0) {
        SonoraPresentAlert(self, @"No Music Selected", @"Select at least one track.");
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.tracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore addPlaylistWithName:self.playlistName
                                                                    trackIDs:orderedIDs
                                                                  coverImage:nil];
    if (playlist == nil) {
        SonoraPresentAlert(self, @"Error", @"Could not create playlist.");
        return;
    }

    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    UIViewController *root = self.navigationController.viewControllers.firstObject;
    if (root != nil) {
        [self.navigationController setViewControllers:@[root, detail] animated:YES];
    } else {
        [self.navigationController pushViewController:detail animated:YES];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TrackPickCell" forIndexPath:indexPath];

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlist Add Tracks

@interface SonoraPlaylistAddTracksViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSArray<SonoraTrack *> *availableTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation SonoraPlaylistAddTracksViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _availableTracks = @[];
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Add Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(addTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    [self setupTableView];
    [self reloadAvailableTracks];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistAddTrackCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadAvailableTracks {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSSet<NSString *> *existingIDs = [NSSet setWithArray:playlist.trackIDs ?: @[]];
    NSMutableArray<SonoraTrack *> *filteredTracks = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (![existingIDs containsObject:track.identifier]) {
            [filteredTracks addObject:track];
        }
    }

    self.availableTracks = [filteredTracks copy];
    [self.selectedTrackIDs removeAllObjects];
    [self.tableView reloadData];
    [self updateAddButtonState];
    [self updateEmptyState];
}

- (void)updateAddButtonState {
    self.navigationItem.rightBarButtonItem.enabled = (self.selectedTrackIDs.count > 0);
}

- (void)updateEmptyState {
    if (self.availableTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 2;

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        label.text = @"No tracks in library.";
    } else {
        label.text = @"All tracks are already in this playlist.";
    }

    self.tableView.backgroundView = label;
}

- (void)addTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.availableTracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    BOOL added = [SonoraPlaylistStore.sharedStore addTrackIDs:orderedIDs toPlaylistID:self.playlistID];
    if (!added) {
        SonoraPresentAlert(self, @"Nothing Added", @"Selected tracks are already in this playlist.");
        return;
    }

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.availableTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistAddTrackCell" forIndexPath:indexPath];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateAddButtonState];
}

@end

#pragma mark - Playlist Cover Picker

@interface SonoraPlaylistCoverPickerViewController ()

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong) UIImageView *previewView;

@end

@implementation SonoraPlaylistCoverPickerViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Change Playlist Cover";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self reloadPreview];
}

- (void)setupUI {
    UIImageView *previewView = [[UIImageView alloc] init];
    previewView.translatesAutoresizingMaskIntoConstraints = NO;
    previewView.contentMode = UIViewContentModeScaleAspectFill;
    previewView.layer.cornerRadius = 14.0;
    previewView.layer.masksToBounds = YES;
    self.previewView = previewView;

    UIButton *chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [chooseButton setTitle:@"Choose Image" forState:UIControlStateNormal];
    chooseButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [chooseButton addTarget:self action:@selector(chooseImageTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *autoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    autoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [autoButton setTitle:@"Use Auto Cover" forState:UIControlStateNormal];
    autoButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [autoButton addTarget:self action:@selector(resetAutoCoverTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.text = @"Select an image from Gallery.\nThis changes playlist cover only.";
    hintLabel.textColor = UIColor.secondaryLabelColor;
    hintLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.numberOfLines = 2;

    [self.view addSubview:previewView];
    [self.view addSubview:chooseButton];
    [self.view addSubview:autoButton];
    [self.view addSubview:hintLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [previewView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [previewView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [previewView.widthAnchor constraintEqualToConstant:220.0],
        [previewView.heightAnchor constraintEqualToConstant:220.0],

        [chooseButton.topAnchor constraintEqualToAnchor:previewView.bottomAnchor constant:20.0],
        [chooseButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [autoButton.topAnchor constraintEqualToAnchor:chooseButton.bottomAnchor constant:10.0],
        [autoButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [hintLabel.topAnchor constraintEqualToAnchor:autoButton.bottomAnchor constant:16.0],
        [hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0]
    ]];
}

- (void)reloadPreview {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    self.previewView.image = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                    library:SonoraLibraryManager.sharedManager
                                                                       size:CGSizeMake(320.0, 320.0)];
}

- (void)chooseImageTapped {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)resetAutoCoverTapped {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    UIImage *autoCover = [self randomAutoCoverImageForPlaylist:playlist];
    BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:autoCover forPlaylistID:self.playlistID];
    if (!success) {
        SonoraPresentAlert(self, @"Error", @"Could not reset cover.");
        return;
    }
    [self reloadPreview];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (result == nil) {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) {
        SonoraPresentAlert(self, @"Error", @"Cannot read this image.");
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class
              completionHandler:^(id<NSItemProviderReading>  _Nullable object, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            if (error != nil || ![object isKindOfClass:UIImage.class]) {
                SonoraPresentAlert(strongSelf, @"Error", @"Cannot read this image.");
                return;
            }

            UIImage *image = (UIImage *)object;
            BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:image forPlaylistID:strongSelf.playlistID];
            if (!success) {
                SonoraPresentAlert(strongSelf, @"Error", @"Could not set cover.");
                return;
            }

            [strongSelf reloadPreview];
        });
    }];
}

- (nullable UIImage *)randomAutoCoverImageForPlaylist:(SonoraPlaylist *)playlist {
    if (playlist == nil) {
        return nil;
    }

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSArray<SonoraTrack *> *playlistTracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:playlist library:SonoraLibraryManager.sharedManager];
    if (playlistTracks.count == 0) {
        return nil;
    }

    NSMutableArray<SonoraTrack *> *shuffledTracks = [playlistTracks mutableCopy];
    for (NSInteger i = shuffledTracks.count - 1; i > 0; i -= 1) {
        u_int32_t j = arc4random_uniform((u_int32_t)(i + 1));
        [shuffledTracks exchangeObjectAtIndex:i withObjectAtIndex:j];
    }

    NSUInteger limit = MIN((NSUInteger)4, shuffledTracks.count);
    NSMutableArray<NSString *> *randomTrackIDs = [NSMutableArray arrayWithCapacity:limit];
    for (NSUInteger index = 0; index < limit; index += 1) {
        SonoraTrack *track = shuffledTracks[index];
        if (track.identifier.length > 0) {
            [randomTrackIDs addObject:track.identifier];
        }
    }

    if (randomTrackIDs.count == 0) {
        return nil;
    }

    SonoraPlaylist *tempPlaylist = [[SonoraPlaylist alloc] init];
    tempPlaylist.playlistID = @"sonora-auto-cover-temp";
    tempPlaylist.name = playlist.name ?: @"Playlist";
    tempPlaylist.trackIDs = [randomTrackIDs copy];
    tempPlaylist.customCoverFileName = nil;

    return [SonoraPlaylistStore.sharedStore coverForPlaylist:tempPlaylist
                                                 library:SonoraLibraryManager.sharedManager
                                                    size:CGSizeMake(320.0, 320.0)];
}

@end

#pragma mark - Playlist Detail

@interface SonoraPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong, nullable) SonoraPlaylist *playlist;
@property (nonatomic, strong, nullable) SonoraSharedPlaylistSnapshot *sharedSnapshot;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL compactTitleVisible;
@property (nonatomic, assign) BOOL sharedCoverLoading;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *sharedArtworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *sharedArtworkLoadingTrackIDs;

@end

@implementation SonoraPlaylistDetailViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _tracks = @[];
        _filteredTracks = @[];
        _selectedTrackIDs = [NSMutableOrderedSet orderedSet];
        _multiSelectMode = NO;
        _sharedArtworkCache = [[NSCache alloc] init];
        _sharedArtworkLoadingTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithSharedPlaylistSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot {
    self = [self initWithPlaylistID:snapshot.playlistID ?: SonoraSharedPlaylistSyntheticID(snapshot.remoteID)];
    if (self) {
        _sharedSnapshot = snapshot;
    }
    return self;
}

- (BOOL)isSharedPlaylistMode {
    return (self.sharedSnapshot != nil ||
            [self.playlistID hasPrefix:SonoraSharedPlaylistSyntheticPrefix] ||
            [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:self.playlistID] != nil);
}

- (SonoraSharedPlaylistSnapshot * _Nullable)resolvedSharedSnapshot {
    SonoraSharedPlaylistSnapshot *storedSnapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:self.playlistID];
    if (storedSnapshot != nil) {
        self.sharedSnapshot = storedSnapshot;
        return storedSnapshot;
    }
    return self.sharedSnapshot;
}

- (NSString * _Nullable)sharedArtworkURLForTrack:(SonoraTrack *)track {
    if (track.identifier.length == 0 || ![self isSharedPlaylistMode]) {
        return nil;
    }
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *urlString = snapshot.trackArtworkURLByTrackID[track.identifier];
    return urlString.length > 0 ? urlString : nil;
}

- (void)loadSharedCoverIfNeeded {
    if (![self isSharedPlaylistMode] || self.sharedCoverLoading) {
        return;
    }
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *urlString = snapshot.coverURL ?: @"";
    if (snapshot == nil || snapshot.coverImage != nil || urlString.length == 0) {
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    self.sharedCoverLoading = YES;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.sharedCoverLoading = NO;
            if (image == nil) {
                return;
            }
            snapshot.coverImage = image;
            strongSelf.coverView.image = image;
            if ([SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
                SonoraSharedPlaylistSnapshot *snapshotToPersist = snapshot;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshotToPersist];
                    });
                });
            }
        });
    }];
    [task resume];
}

- (void)loadSharedArtworkIfNeededForTrack:(SonoraTrack *)track {
    if (track == nil || track.artwork != nil || ![self isSharedPlaylistMode]) {
        return;
    }
    NSString *trackID = track.identifier ?: @"";
    if (trackID.length == 0) {
        return;
    }
    UIImage *cachedImage = [self.sharedArtworkCache objectForKey:trackID];
    if (cachedImage != nil) {
        track.artwork = cachedImage;
        return;
    }
    if ([self.sharedArtworkLoadingTrackIDs containsObject:trackID]) {
        return;
    }
    NSString *urlString = [self sharedArtworkURLForTrack:track];
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (url == nil) {
        return;
    }

    [self.sharedArtworkLoadingTrackIDs addObject:trackID];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.sharedArtworkLoadingTrackIDs removeObject:trackID];
            if (image == nil) {
                return;
            }
            [strongSelf.sharedArtworkCache setObject:image forKey:trackID];
            track.artwork = image;
            SonoraSharedPlaylistSnapshot *snapshot = [strongSelf resolvedSharedSnapshot];
            if (snapshot != nil && [SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
                SonoraSharedPlaylistSnapshot *snapshotToPersist = snapshot;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshotToPersist];
                    });
                });
            }
            NSUInteger row = [strongSelf.filteredTracks indexOfObjectPassingTest:^BOOL(SonoraTrack * _Nonnull candidate, NSUInteger idx, BOOL * _Nonnull stop) {
                return [candidate.identifier isEqualToString:trackID];
            }];
            if (row != NSNotFound) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                if ([[strongSelf.tableView indexPathsForVisibleRows] containsObject:indexPath]) {
                    [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
            }
        });
    }];
    [task resume];
}

- (NSArray<NSString *> *)matchingLocalTrackIDsForSharedSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot {
    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }
    NSMutableArray<NSString *> *matched = [NSMutableArray array];
    for (SonoraTrack *remoteTrack in snapshot.tracks) {
        NSString *remoteTitle = SonoraSharedPlaylistNormalizeText(remoteTrack.title);
        NSString *remoteArtist = SonoraSharedPlaylistNormalizeText(remoteTrack.artist);
        if (remoteTitle.length == 0) {
            continue;
        }
        for (SonoraTrack *localTrack in libraryTracks) {
            if (localTrack.identifier.length == 0) {
                continue;
            }
            NSString *localTitle = SonoraSharedPlaylistNormalizeText(localTrack.title);
            NSString *localArtist = SonoraSharedPlaylistNormalizeText(localTrack.artist);
            if (![localTitle isEqualToString:remoteTitle]) {
                continue;
            }
            if (remoteArtist.length > 0 && localArtist.length > 0 &&
                ![localArtist containsString:remoteArtist] &&
                ![remoteArtist containsString:localArtist]) {
                continue;
            }
            [matched addObject:localTrack.identifier];
            break;
        }
    }
    return [[NSOrderedSet orderedSetWithArray:matched] array];
}

- (void)addSharedPlaylistLocallyTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    if (snapshot == nil) {
        return;
    }
    UIAlertController *progress = SonoraPresentBlockingProgressAlert(self, @"Adding Playlist", @"Downloading tracks...");
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSString *> *importedTrackIDs = [NSMutableArray array];
        for (SonoraTrack *track in snapshot.tracks) {
            NSString *suggestedName = track.artist.length > 0 ? [NSString stringWithFormat:@"%@ - %@", track.artist, track.title ?: @"Track"] : (track.title ?: @"Track");
            NSURL *savedURL = SonoraSharedPlaylistDownloadedFileURL(track.url.absoluteString ?: @"", suggestedName);
            if (savedURL != nil) {
                [importedTrackIDs addObject:savedURL.path ?: @""];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [progress dismissViewControllerAnimated:YES completion:nil];
            if (strongSelf == nil) {
                return;
            }
            [SonoraLibraryManager.sharedManager reloadTracks];
            NSMutableArray<NSString *> *resolvedTrackIDs = [NSMutableArray array];
            for (NSString *path in importedTrackIDs) {
                SonoraTrack *importedTrack = [SonoraLibraryManager.sharedManager trackForIdentifier:path];
                if (importedTrack.identifier.length > 0) {
                    [resolvedTrackIDs addObject:importedTrack.identifier];
                } else if (path.length > 0) {
                    [resolvedTrackIDs addObject:path];
                }
            }
            SonoraPlaylist *created = [SonoraPlaylistStore.sharedStore addPlaylistWithName:snapshot.name
                                                                                  trackIDs:[resolvedTrackIDs copy]
                                                                                coverImage:snapshot.coverImage];
            if (created == nil) {
                SonoraPresentAlert(strongSelf, @"Error", @"Could not create local playlist.");
                return;
            }
            strongSelf.sharedSnapshot = nil;
            SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:created.playlistID];
            NSMutableArray<UIViewController *> *stack = [strongSelf.navigationController.viewControllers mutableCopy];
            [stack removeLastObject];
            [stack addObject:detail];
            [strongSelf.navigationController setViewControllers:[stack copy] animated:YES];
        });
    });
}

- (void)toggleSharedPlaylistLikeTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    if (snapshot == nil) {
        return;
    }
    self.sharedSnapshot = snapshot;
    if ([SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
        [SonoraSharedPlaylistStore.sharedStore removeSnapshotForPlaylistID:snapshot.playlistID];
    } else {
        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshot];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            SonoraSharedPlaylistWarmPersistentCache(snapshot);
        });
    }
}

- (void)shareCurrentPlaylistLinkTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *shareURL = snapshot.shareURL ?: @"";
    if (shareURL.length == 0) {
        SonoraPresentAlert(self, @"Error", @"Share link is unavailable.");
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:share animated:YES completion:nil];
}

- (void)sharePlaylistTapped {
    if (self.playlist == nil || [self isSharedPlaylistMode]) {
        return;
    }
    UIAlertController *progress = SonoraPresentBlockingProgressAlert(self, @"Sharing Playlist", @"Uploading tracks to server...");
    __weak typeof(self) weakSelf = self;
    NSString *playlistName = self.playlist.name ?: @"Playlist";
    NSArray<SonoraTrack *> *tracksSnapshot = [self.tracks copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:self.playlist
                                                               library:SonoraLibraryManager.sharedManager
                                                                  size:CGSizeMake(768.0, 768.0)];
        NSMutableDictionary<NSString *, id> *manifest = [NSMutableDictionary dictionary];
        manifest[@"name"] = playlistName;
        NSMutableArray<NSDictionary<NSString *, id> *> *trackItems = [NSMutableArray arrayWithCapacity:tracksSnapshot.count];
        [tracksSnapshot enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            NSMutableDictionary<NSString *, id> *trackPayload = [NSMutableDictionary dictionary];
            trackPayload[@"id"] = track.identifier ?: @"";
            trackPayload[@"title"] = track.title ?: @"";
            trackPayload[@"artist"] = track.artist ?: @"";
            trackPayload[@"durationMs"] = @((NSInteger)llround(MAX(track.duration, 0.0) * 1000.0));
            [trackItems addObject:[trackPayload copy]];
        }];
        manifest[@"tracks"] = [trackItems copy];
        NSString *baseURLString = [SonoraSharedPlaylistBackendBaseURLString() stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSURL *requestURL = [NSURL URLWithString:[baseURLString stringByAppendingString:@"/api/shared-playlists"]];
        if (requestURL == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progress dismissViewControllerAnimated:YES completion:nil];
                SonoraPresentAlert(self, @"Error", @"Backend URL is invalid.");
            });
            return;
        }
        NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil];
        NSMutableURLRequest *createRequest = [NSMutableURLRequest requestWithURL:requestURL];
        createRequest.HTTPMethod = @"POST";
        createRequest.timeoutInterval = 120.0;
        [createRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [createRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        createRequest.HTTPBody = manifestData;
        NSHTTPURLResponse *createResponse = nil;
        NSData *createData = SonoraSharedPlaylistPerformRequest(createRequest, 120.0, &createResponse);
        NSDictionary *createPayload = createData.length > 0 ? [NSJSONSerialization JSONObjectWithData:createData options:0 error:nil] : nil;
        NSString *remoteID = [createPayload[@"id"] isKindOfClass:NSString.class] ? createPayload[@"id"] : @"";
        NSString *shareURL = [createPayload[@"shareUrl"] isKindOfClass:NSString.class] ? createPayload[@"shareUrl"] : createPayload[@"url"];
        if (remoteID.length == 0 || shareURL.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progress dismissViewControllerAnimated:YES completion:nil];
                SonoraPresentAlert(self, @"Error", @"Could not share playlist.");
            });
            return;
        }

        NSString *(^encodedFilename)(NSString *) = ^NSString *(NSString *value) {
            NSString *safeValue = value.length > 0 ? value : @"file.bin";
            return [safeValue stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: safeValue;
        };

        BOOL (^uploadBinaryFile)(NSString *, NSString *, NSString *, NSData *) = ^BOOL(NSString *endpointPath, NSString *filename, NSString *mimeType, NSData *data) {
            if (data.length == 0) {
                return YES;
            }
            NSString *urlString = [NSString stringWithFormat:@"%@%@?filename=%@", baseURLString, endpointPath, encodedFilename(filename)];
            NSURL *uploadURL = [NSURL URLWithString:urlString];
            if (uploadURL == nil) {
                return NO;
            }
            NSMutableURLRequest *uploadRequest = [NSMutableURLRequest requestWithURL:uploadURL];
            uploadRequest.HTTPMethod = @"POST";
            uploadRequest.timeoutInterval = 600.0;
            [uploadRequest setValue:(mimeType.length > 0 ? mimeType : @"application/octet-stream") forHTTPHeaderField:@"Content-Type"];
            uploadRequest.HTTPBody = data;
            return SonoraSharedPlaylistPerformRequest(uploadRequest, 600.0, nil) != nil;
        };

        NSData *coverData = cover != nil ? UIImageJPEGRepresentation(cover, 0.88) : nil;
        if (coverData.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress.message = @"Uploading cover...";
            });
            if (!uploadBinaryFile([NSString stringWithFormat:@"/api/shared-playlists/%@/cover", remoteID], @"cover.jpg", @"image/jpeg", coverData)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [progress dismissViewControllerAnimated:YES completion:nil];
                    SonoraPresentAlert(self, @"Error", @"Could not upload playlist cover.");
                });
                return;
            }
        }

        __block BOOL uploadFailed = NO;
        [tracksSnapshot enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, BOOL * _Nonnull stop) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress.message = [NSString stringWithFormat:@"Uploading track %lu/%lu...", (unsigned long)(idx + 1), (unsigned long)tracksSnapshot.count];
            });
            NSData *artworkData = track.artwork != nil ? UIImageJPEGRepresentation(track.artwork, 0.86) : nil;
            if (artworkData.length > 0) {
                NSString *artworkName = [NSString stringWithFormat:@"%@.jpg", track.identifier.length > 0 ? track.identifier : [NSString stringWithFormat:@"track_%lu", (unsigned long)idx]];
                if (!uploadBinaryFile([NSString stringWithFormat:@"/api/shared-playlists/%@/tracks/%lu/artwork", remoteID, (unsigned long)idx], artworkName, @"image/jpeg", artworkData)) {
                    uploadFailed = YES;
                    *stop = YES;
                    return;
                }
            }
            if (track.url.isFileURL) {
                NSData *audioData = [NSData dataWithContentsOfURL:track.url options:NSDataReadingMappedIfSafe error:nil];
                if (audioData.length > 0) {
                    NSString *extension = track.url.pathExtension.length > 0 ? track.url.pathExtension.lowercaseString : @"mp3";
                    NSString *mimeType = @"audio/mpeg";
                    if ([extension isEqualToString:@"m4a"]) {
                        mimeType = @"audio/mp4";
                    } else if ([extension isEqualToString:@"aac"]) {
                        mimeType = @"audio/aac";
                    } else if ([extension isEqualToString:@"wav"]) {
                        mimeType = @"audio/wav";
                    } else if ([extension isEqualToString:@"ogg"]) {
                        mimeType = @"audio/ogg";
                    } else if ([extension isEqualToString:@"flac"]) {
                        mimeType = @"audio/flac";
                    }
                    NSString *fileName = track.url.lastPathComponent.length > 0 ? track.url.lastPathComponent : [NSString stringWithFormat:@"track_%lu.%@", (unsigned long)idx, extension];
                    if (!uploadBinaryFile([NSString stringWithFormat:@"/api/shared-playlists/%@/tracks/%lu/file", remoteID, (unsigned long)idx], fileName, mimeType, audioData)) {
                        uploadFailed = YES;
                        *stop = YES;
                        return;
                    }
                }
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:YES completion:nil];
            if (uploadFailed) {
                SonoraPresentAlert(self, @"Error", @"Could not share playlist.");
                return;
            }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
            UIPopoverPresentationController *popover = share.popoverPresentationController;
            if (popover != nil) {
                popover.barButtonItem = self.navigationItem.rightBarButtonItem;
            }
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)refreshNavigationItemsForPlaylistSelectionState {
    if (self.multiSelectMode) {
        NSString *displayTitle = [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count];
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelPlaylistSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedPlaylistTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedPlaylistTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        UIBarButtonItem *tightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                      target:nil
                                                                                      action:nil];
        tightSpace.width = -8.0;
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, tightSpace, favoriteItem];
        return;
    }
    self.navigationItem.leftBarButtonItem = nil;
    [self updateOptionsButtonVisibility];
}

- (void)setPlaylistSelectionModeEnabled:(BOOL)enabled {
    if (enabled && [self isSharedPlaylistMode]) {
        return;
    }
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateNavigationTitleVisibility];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)playlistTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)togglePlaylistSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setPlaylistSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForPlaylistSelectionState];
        [self updateNavigationTitleVisibility];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if ([self isSharedPlaylistMode]) {
        return;
    }
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self playlistTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setPlaylistSelectionModeEnabled:YES];
    [self togglePlaylistSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)removeSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraPlaylistStore.sharedStore removeTrackID:trackID fromPlaylistID:self.playlistID];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)cancelPlaylistSelectionTapped {
    [self setPlaylistSelectionModeEnabled:NO];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = nil;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadData)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateSearchControllerAttachment];
    [self reloadData];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadData];
}

- (void)handlePlaybackChanged {
    [self updatePlayButtonState];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
    [self updatePlayButtonState];
    [self updateSleepButton];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search In Playlist");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.tracks.count == 0) {
        label.text = @"Tracks missing. Re-add files to On My iPhone/Sonora/Sonora";
    } else {
        label.text = @"No matching tracks.";
    }
    self.tableView.backgroundView = label;
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 374.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat sideControlSize = 46.0;
    CGFloat shuffleSize = 46.0;
    CGFloat controlsY = 272.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sideControlSize,
                                   controlsY + (playSize - sideControlSize) * 0.5,
                                   sideControlSize,
                                   sideControlSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = SonoraPlayerPrimaryColor();
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepButton = sleepButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - shuffleSize) * 0.5,
                                     shuffleSize,
                                     shuffleSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = SonoraPlayerPrimaryColor();
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:sleepButton];
    [header addSubview:playButton];
    [header addSubview:shuffleButton];

    return header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
        [self updateSleepButton];
    }
    [self updateNavigationTitleVisibility];
}

- (BOOL)isLovelyPlaylist {
    if (self.playlist == nil) {
        return NO;
    }

    NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
    if (lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) {
        return YES;
    }
    return ([self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
}

- (void)updateOptionsButtonVisibility {
    if (self.multiSelectMode) {
        return;
    }
    if (self.playlist == nil || ([self isLovelyPlaylist] && ![self isSharedPlaylistMode])) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                          weight:UIImageSymbolWeightBold];
    UIImage *optionsImage = [UIImage systemImageNamed:@"ellipsis" withConfiguration:config];
    if (optionsImage == nil) {
        optionsImage = [UIImage imageNamed:@"tab_ellipsis"];
    }
    if (optionsImage != nil) {
        UIBarButtonItem *optionsItem = [[UIBarButtonItem alloc] initWithImage:optionsImage
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(optionsTapped)];
        SonoraConfigureNavigationIconBarButtonItem(optionsItem, @"Playlist Options");
        self.navigationItem.rightBarButtonItem = optionsItem;
    } else {
        UIBarButtonItem *optionsItem = [[UIBarButtonItem alloc] initWithTitle:@"..."
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(optionsTapped)];
        SonoraConfigureNavigationIconBarButtonItem(optionsItem, @"Playlist Options");
        self.navigationItem.rightBarButtonItem = optionsItem;
    }
}

- (void)reloadData {
    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        if (snapshot == nil) {
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }
        self.sharedSnapshot = snapshot;
        SonoraPlaylist *pseudo = [[SonoraPlaylist alloc] init];
        pseudo.playlistID = snapshot.playlistID;
        pseudo.name = snapshot.name;
        NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:snapshot.tracks.count];
        [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            [trackIDs addObject:(track.identifier.length > 0 ? track.identifier : [NSString stringWithFormat:@"%@:%lu", snapshot.playlistID, (unsigned long)idx])];
        }];
        pseudo.trackIDs = [trackIDs copy];
        self.playlist = pseudo;
        self.tracks = snapshot.tracks ?: @[];
    } else {
        [SonoraPlaylistStore.sharedStore reloadPlaylists];

        self.playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
        if (self.playlist == nil) {
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }

        if (SonoraLibraryManager.sharedManager.tracks.count == 0 && self.playlist.trackIDs.count > 0) {
            [SonoraLibraryManager.sharedManager reloadTracks];
        }
        self.tracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:self.playlist library:SonoraLibraryManager.sharedManager];
    }

    [self updateOptionsButtonVisibility];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateSleepButton];
    [self updateNavigationTitleVisibility];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self applySearchFilterAndReload];
}

- (void)updateHeader {
    if (self.playlist == nil) {
        return;
    }

    self.nameLabel.text = self.playlist.name;
    UIImage *cover = nil;
    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        [self loadSharedCoverIfNeeded];
        cover = snapshot.coverImage ?: snapshot.tracks.firstObject.artwork;
    } else {
        cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:self.playlist
                                                         library:SonoraLibraryManager.sharedManager
                                                            size:CGSizeMake(240.0, 240.0)];
    }
    self.coverView.image = cover;

    if (self.playButton != nil) {
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        BOOL isLovely = ((lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) ||
                         [self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
        UIColor *targetColor = nil;
        if (isLovely) {
            targetColor = SonoraLovelyAccentRedColor();
        } else {
            UIImage *accentSource = cover;
            if (accentSource == nil || accentSource.CGImage == nil) {
                for (SonoraTrack *track in self.tracks) {
                    if (track.artwork != nil) {
                        accentSource = track.artwork;
                        break;
                    }
                }
            }

            targetColor = [SonoraArtworkAccentColorService dominantAccentColorForImage:accentSource
                                                                           fallback:SonoraAccentYellowColor()];
        }
        if (targetColor == nil) {
            targetColor = SonoraAccentYellowColor();
        }

        UIColor *currentColor = self.playButton.backgroundColor;
        if (currentColor == nil || !CGColorEqualToColor(currentColor.CGColor, targetColor.CGColor)) {
            [UIView animateWithDuration:0.22
                                  delay:0.0
                                options:(UIViewAnimationOptionAllowUserInteraction |
                                         UIViewAnimationOptionBeginFromCurrentState)
                             animations:^{
                self.playButton.backgroundColor = targetColor;
            }
                             completion:nil];
        }
    }

    [self updatePlayButtonState];
}

- (BOOL)isCurrentQueueMatchingPlaylist {
    if (self.tracks.count == 0) {
        return NO;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    return SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
}

- (void)updatePlayButtonState {
    if (self.playButton == nil) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isPlaylistPlaying = [self isCurrentQueueMatchingPlaylist] &&
    playback.isPlaying &&
    (playback.currentTrack != nil);
    NSString *symbol = isPlaylistPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = isPlaylistPlaying ? @"Pause playlist" : @"Play playlist";
}

- (void)updateNavigationTitleVisibility {
    if (self.multiSelectMode) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = nil;
        self.compactTitleVisible = YES;
        return;
    }
    if (self.playlist == nil) {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
        self.compactTitleVisible = NO;
        return;
    }

    BOOL shouldShowCompact = self.tableView.contentOffset.y > 175.0;
    if (shouldShowCompact == self.compactTitleVisible) {
        return;
    }

    self.compactTitleVisible = shouldShowCompact;
    if (shouldShowCompact) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = self.playlist.name;
    } else {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
    }
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    if ([self isCurrentQueueMatchingPlaylist] && playback.currentTrack != nil) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:queue startIndex:0];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    NSInteger randomStart = (NSInteger)arc4random_uniform((u_int32_t)self.tracks.count);
    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:randomStart];
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:YES];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepButton];
    });
}

- (void)updateSleepButton {
    if (self.sleepButton == nil) {
        return;
    }

    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    BOOL isActive = sleepTimer.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    UIColor *inactiveColor = [UIColor labelColor];
    self.sleepButton.tintColor = isActive ? SonoraAccentYellowColor() : inactiveColor;
    if (self.shuffleButton != nil) {
        self.shuffleButton.tintColor = inactiveColor;
    }
    self.sleepButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Sleep timer";
}

- (void)optionsTapped {
    if (self.playlist == nil) {
        return;
    }
    if ([self isLovelyPlaylist] && ![self isSharedPlaylistMode]) {
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.playlist.name
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        BOOL liked = [SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID];
        [sheet addAction:[UIAlertAction actionWithTitle:(liked ? @"Remove from Collections" : @"Add to Collections")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self toggleSharedPlaylistLikeTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Import to Library"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self addSharedPlaylistLocallyTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Share Link"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self shareCurrentPlaylistLinkTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        UIPopoverPresentationController *popover = sheet.popoverPresentationController;
        if (popover != nil) {
            popover.barButtonItem = self.navigationItem.rightBarButtonItem;
        }

        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename Playlist"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self renamePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Change Cover"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self changeCoverTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Add Music"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self addMusicTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Share Playlist"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self sharePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete Playlist"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self deletePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)renamePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Playlist"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Playlist Name";
        textField.text = self.playlist.name;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) {
            SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
            return;
        }

        BOOL renamed = [SonoraPlaylistStore.sharedStore renamePlaylistWithID:self.playlistID newName:name];
        if (!renamed) {
            SonoraPresentAlert(self, @"Error", @"Could not rename playlist.");
            return;
        }

        [self reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)changeCoverTapped {
    SonoraPlaylistCoverPickerViewController *coverPicker = [[SonoraPlaylistCoverPickerViewController alloc] initWithPlaylistID:self.playlistID];
    coverPicker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:coverPicker animated:YES];
}

- (void)addMusicTapped {
    SonoraPlaylistAddTracksViewController *addTracks = [[SonoraPlaylistAddTracksViewController alloc] initWithPlaylistID:self.playlistID];
    addTracks.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:addTracks animated:YES];
}

- (void)deletePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Delete Playlist?"
                                                                      message:self.playlist.name
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction * _Nonnull action) {
        BOOL deleted = [SonoraPlaylistStore.sharedStore deletePlaylistWithID:self.playlistID];
        if (!deleted) {
            SonoraPresentAlert(self, @"Error", @"Could not delete playlist.");
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    [self loadSharedArtworkIfNeededForTrack:track];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL sameQueue = [self isCurrentQueueMatchingPlaylist];
    BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self playlistTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self togglePlaylistSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateNavigationTitleVisibility];
        [self updateSearchControllerAttachment];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode || [self isSharedPlaylistMode]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"Remove"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        BOOL removed = [SonoraPlaylistStore.sharedStore removeTrackID:track.identifier fromPlaylistID:self.playlistID];
        if (!removed) {
            SonoraPresentAlert(self, @"Could Not Remove", @"Track could not be removed from playlist.");
            completionHandler(NO);
            return;
        }
        [self reloadData];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode || [self isSharedPlaylistMode]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

@end

#pragma mark - Player

@interface SonoraArtworkEqualizerBadgeView : UIView

- (void)setBarColor:(UIColor *)color;
- (void)setPlaying:(BOOL)playing;
- (void)setLevel:(CGFloat)level;

@end

@interface SonoraArtworkEqualizerBadgeView ()

@property (nonatomic, copy) NSArray<UIView *> *barViews;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *barHeightConstraints;
@property (nonatomic, assign) BOOL playing;

@end

@implementation SonoraArtworkEqualizerBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];
        self.layer.cornerRadius = 8.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        self.layer.masksToBounds = YES;

        NSArray<NSNumber *> *heights = @[@5.0, @8.0, @9.0, @6.0];
        NSMutableArray<UIView *> *bars = [NSMutableArray arrayWithCapacity:heights.count];
        NSMutableArray<NSLayoutConstraint *> *heightConstraints = [NSMutableArray arrayWithCapacity:heights.count];
        UIView *previousBar = nil;
        for (NSNumber *height in heights) {
            UIView *bar = [[UIView alloc] init];
            bar.translatesAutoresizingMaskIntoConstraints = NO;
            bar.backgroundColor = UIColor.whiteColor;
            bar.layer.cornerRadius = 1.3;
            bar.layer.masksToBounds = YES;
            [self addSubview:bar];
            [bars addObject:bar];

            NSLayoutConstraint *heightConstraint = [bar.heightAnchor constraintEqualToConstant:height.doubleValue];
            [NSLayoutConstraint activateConstraints:@[
                [bar.widthAnchor constraintEqualToConstant:2.4],
                heightConstraint,
                [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0]
            ]];
            [heightConstraints addObject:heightConstraint];
            if (previousBar == nil) {
                [bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0].active = YES;
            } else {
                [bar.leadingAnchor constraintEqualToAnchor:previousBar.trailingAnchor constant:2.5].active = YES;
            }
            previousBar = bar;
        }
        [previousBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-6.0].active = YES;
        self.barViews = [bars copy];
        self.barHeightConstraints = [heightConstraints copy];
    }
    return self;
}

- (void)setBarColor:(UIColor *)color {
    UIColor *resolved = color ?: UIColor.whiteColor;
    for (UIView *bar in self.barViews) {
        bar.backgroundColor = resolved;
    }
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    self.alpha = playing ? 1.0 : 0.90;
}

- (void)setLevel:(CGFloat)level {
    CGFloat clamped = MIN(MAX(level, 0.0), 1.0);
    NSArray<NSNumber *> *weights = @[@0.62, @0.92, @1.0, @0.76];

    for (NSUInteger index = 0; index < self.barHeightConstraints.count; index += 1) {
        CGFloat weight = [weights[index] doubleValue];
        CGFloat base = self.playing ? 4.0 : 3.2;
        CGFloat dynamic = clamped * (self.playing ? 14.0 : 5.0) * weight;
        self.barHeightConstraints[index].constant = base + dynamic;
    }

    if (self.window != nil) {
        [UIView animateWithDuration:0.16
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            [self layoutIfNeeded];
        } completion:nil];
    }
}

@end

@interface SonoraPlayerViewController ()

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *nextPreviewLabel;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *sleepTimerButton;
@property (nonatomic, strong) SonoraArtworkEqualizerBadgeView *equalizerBadgeView;
@property (nonatomic, strong) UIView *artworkLoadingOverlayView;
@property (nonatomic, strong) UIActivityIndicatorView *artworkLoadingSpinner;
@property (nonatomic, strong) NSLayoutConstraint *artworkLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *artworkTrailingConstraint;
@property (nonatomic, assign) BOOL scrubbing;

@end

@implementation SonoraPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = SonoraPlayerBackgroundColor();

    [self setupUI];
    [self applyPlayerTheme];

    if (@available(iOS 17.0, *)) {
        __weak typeof(self) weakSelf = self;
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                          withHandler:^(__kindof id<UITraitEnvironment>  _Nonnull traitEnvironment,
                                        UITraitCollection * _Nullable previousTraitCollection) {
            (void)traitEnvironment;
            (void)previousTraitCollection;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf applyPlayerTheme];
            [strongSelf updateModeIcons];
        }];
    }

    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipeDown];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeRight];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshUI)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleProgressChanged)
                                               name:SonoraPlaybackProgressDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackMeterChanged:)
                                               name:SonoraPlaybackMeterDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateFavoriteButton)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepTimerButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlayerSettingsChanged:)
                                               name:SonoraPlayerSettingsDidChangeNotification
                                             object:nil];

    [self refreshUI];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateArtworkCornerRadius];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)setupUI {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *artworkView = [[UIImageView alloc] init];
    artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkView.contentMode = UIViewContentModeScaleAspectFill;
    artworkView.layer.cornerRadius = 0.0;
    artworkView.layer.masksToBounds = YES;
    self.artworkView = artworkView;

    SonoraArtworkEqualizerBadgeView *equalizerBadge = [[SonoraArtworkEqualizerBadgeView alloc] init];
    equalizerBadge.hidden = YES;
    self.equalizerBadgeView = equalizerBadge;
    [artworkView addSubview:equalizerBadge];

    UIView *artworkLoadingOverlayView = [[UIView alloc] init];
    artworkLoadingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkLoadingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.36];
    artworkLoadingOverlayView.userInteractionEnabled = NO;
    artworkLoadingOverlayView.hidden = YES;
    self.artworkLoadingOverlayView = artworkLoadingOverlayView;

    UIActivityIndicatorView *artworkLoadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    artworkLoadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    artworkLoadingSpinner.color = UIColor.whiteColor;
    artworkLoadingSpinner.hidesWhenStopped = NO;
    self.artworkLoadingSpinner = artworkLoadingSpinner;

    [artworkLoadingOverlayView addSubview:artworkLoadingSpinner];
    [artworkView addSubview:artworkLoadingOverlayView];

    UILabel *artistLabel = [[UILabel alloc] init];
    artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
    artistLabel.textAlignment = NSTextAlignmentCenter;
    artistLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    artistLabel.numberOfLines = 1;
    self.subtitleLabel = artistLabel;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.transform = CGAffineTransformMakeScale(1.0, 0.92);
    [slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchCancel];
    self.progressSlider = slider;

    UILabel *elapsedLabel = [[UILabel alloc] init];
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    elapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.elapsedLabel = elapsedLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.textAlignment = NSTextAlignmentRight;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.durationLabel = durationLabel;

    UILabel *nextPreviewLabel = [[UILabel alloc] init];
    nextPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nextPreviewLabel.textAlignment = NSTextAlignmentLeft;
    nextPreviewLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    nextPreviewLabel.numberOfLines = 2;
    self.nextPreviewLabel = nextPreviewLabel;

    self.repeatButton = SonoraPlainIconButton(@"repeat", 24.0, 600.0);
    [self.repeatButton addTarget:self action:@selector(toggleRepeatTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.repeatButton.widthAnchor constraintEqualToConstant:42.0],
        [self.repeatButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.shuffleButton = SonoraPlainIconButton(@"shuffle", 24.0, 600.0);
    [self.shuffleButton addTarget:self action:@selector(toggleShuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.shuffleButton.widthAnchor constraintEqualToConstant:42.0],
        [self.shuffleButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.previousButton = SonoraPlainIconButton(@"backward.fill", 44.0, 700.0);
    [self.previousButton addTarget:self action:@selector(previousTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.previousButton.widthAnchor constraintEqualToConstant:64.0],
        [self.previousButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.playPauseButton = SonoraPlainIconButton(@"play.fill", 56.0, 700.0);
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.playPauseButton.widthAnchor constraintEqualToConstant:76.0],
        [self.playPauseButton.heightAnchor constraintEqualToConstant:76.0]
    ]];

    self.nextButton = SonoraPlainIconButton(@"forward.fill", 44.0, 700.0);
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.nextButton.widthAnchor constraintEqualToConstant:64.0],
        [self.nextButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.favoriteButton = SonoraPlainIconButton(@"heart", 24.0, 600.0);
    [self.favoriteButton addTarget:self action:@selector(toggleFavoriteTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.favoriteButton.widthAnchor constraintEqualToConstant:40.0],
        [self.favoriteButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    self.sleepTimerButton = SonoraPlainIconButton(@"moon.zzz", 23.0, 600.0);
    [self.sleepTimerButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.sleepTimerButton.widthAnchor constraintEqualToConstant:40.0],
        [self.sleepTimerButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    UIStackView *modeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.repeatButton, self.shuffleButton]];
    modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    modeStack.axis = UILayoutConstraintAxisVertical;
    modeStack.alignment = UIStackViewAlignmentCenter;
    modeStack.distribution = UIStackViewDistributionEqualSpacing;
    modeStack.spacing = 10.0;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.sleepTimerButton, self.favoriteButton]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisVertical;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.distribution = UIStackViewDistributionEqualSpacing;
    rightStack.spacing = 10.0;

    UIStackView *transportStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.previousButton, self.playPauseButton, self.nextButton
    ]];
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    transportStack.axis = UILayoutConstraintAxisHorizontal;
    transportStack.alignment = UIStackViewAlignmentCenter;
    transportStack.distribution = UIStackViewDistributionEqualCentering;
    transportStack.spacing = 16.0;

    UIView *controlsRow = [[UIView alloc] init];
    controlsRow.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:artworkView];
    [content addSubview:slider];
    [content addSubview:elapsedLabel];
    [content addSubview:durationLabel];
    [content addSubview:artistLabel];
    [content addSubview:titleLabel];
    [content addSubview:nextPreviewLabel];
    [content addSubview:controlsRow];

    [controlsRow addSubview:modeStack];
    [controlsRow addSubview:transportStack];
    [controlsRow addSubview:rightStack];

    [self.view addSubview:content];

    NSLayoutConstraint *artworkSquare = [artworkView.heightAnchor constraintEqualToAnchor:artworkView.widthAnchor];
    artworkSquare.priority = UILayoutPriorityDefaultHigh;
    self.artworkLeadingConstraint = [artworkView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor];
    self.artworkTrailingConstraint = [artworkView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [artworkView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        self.artworkLeadingConstraint,
        self.artworkTrailingConstraint,
        artworkSquare,
        [artworkView.heightAnchor constraintLessThanOrEqualToAnchor:content.heightAnchor multiplier:0.56],
        [equalizerBadge.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:-10.0],
        [equalizerBadge.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor constant:-10.0],
        [equalizerBadge.widthAnchor constraintEqualToConstant:30.0],
        [equalizerBadge.heightAnchor constraintEqualToConstant:24.0],
        [artworkLoadingOverlayView.topAnchor constraintEqualToAnchor:artworkView.topAnchor],
        [artworkLoadingOverlayView.leadingAnchor constraintEqualToAnchor:artworkView.leadingAnchor],
        [artworkLoadingOverlayView.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor],
        [artworkLoadingOverlayView.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor],
        [artworkLoadingSpinner.centerXAnchor constraintEqualToAnchor:artworkLoadingOverlayView.centerXAnchor],
        [artworkLoadingSpinner.centerYAnchor constraintEqualToAnchor:artworkLoadingOverlayView.centerYAnchor],

        [slider.topAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:16.0],
        [slider.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [slider.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],

        [elapsedLabel.topAnchor constraintEqualToAnchor:slider.bottomAnchor constant:3.0],
        [elapsedLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],

        [durationLabel.topAnchor constraintEqualToAnchor:elapsedLabel.topAnchor],
        [durationLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [artistLabel.topAnchor constraintEqualToAnchor:elapsedLabel.bottomAnchor constant:18.0],
        [artistLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [artistLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:artistLabel.bottomAnchor constant:6.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [controlsRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14.0],
        [controlsRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14.0],
        [controlsRow.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-6.0],
        [controlsRow.heightAnchor constraintEqualToConstant:88.0],

        [modeStack.leadingAnchor constraintEqualToAnchor:controlsRow.leadingAnchor],
        [modeStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [transportStack.centerXAnchor constraintEqualToAnchor:controlsRow.centerXAnchor],
        [transportStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [rightStack.trailingAnchor constraintEqualToAnchor:controlsRow.trailingAnchor],
        [rightStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [nextPreviewLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [nextPreviewLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],
        [nextPreviewLabel.topAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.bottomAnchor constant:16.0],
        [nextPreviewLabel.bottomAnchor constraintEqualToAnchor:controlsRow.topAnchor constant:-14.0]
    ]];
}

- (void)handleDismissSwipe {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)applyPlayerTheme {
    UIColor *primary = SonoraPlayerPrimaryColor();
    UIColor *secondary = SonoraPlayerSecondaryColor();
    SonoraPlayerFontStyle fontStyle = SonoraPlayerFontStyleFromDefaults();

    self.view.backgroundColor = SonoraPlayerBackgroundColor();
    [self updateArtworkCornerRadius];
    self.titleLabel.textColor = primary;
    self.subtitleLabel.textColor = secondary;
    self.elapsedLabel.textColor = secondary;
    self.durationLabel.textColor = secondary;
    self.nextPreviewLabel.textColor = secondary;
    self.titleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.subtitleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.nextPreviewLabel.font = SonoraPlayerFontForStyle(fontStyle, 18.0, UIFontWeightSemibold);

    self.progressSlider.minimumTrackTintColor = primary;
    self.progressSlider.maximumTrackTintColor = SonoraPlayerTimelineMaxColor();
    UIImage *thumbImage = SonoraSliderThumbImage(14.5, primary);
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateNormal];
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateHighlighted];
    self.artworkLoadingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];

    BOOL controlsEnabled = self.playPauseButton.enabled;
    UIColor *controlColor = controlsEnabled ? primary : [secondary colorWithAlphaComponent:0.65];
    NSArray<UIButton *> *buttons = @[
        self.repeatButton,
        self.shuffleButton,
        self.previousButton,
        self.playPauseButton,
        self.nextButton,
        self.favoriteButton,
        self.sleepTimerButton
    ];
    for (UIButton *button in buttons) {
        CGFloat height = CGRectGetHeight(button.bounds);
        if (height < 1.0) {
            [button layoutIfNeeded];
            height = CGRectGetHeight(button.bounds);
        }
        if (height < 1.0) {
            height = 42.0;
        }
        button.backgroundColor = UIColor.clearColor;
        button.layer.cornerRadius = 0.0;
        button.layer.masksToBounds = YES;
    }

    [self.equalizerBadgeView setBarColor:[UIColor colorWithWhite:1.0 alpha:0.96]];
    self.equalizerBadgeView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];

    self.repeatButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.shuffleButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.previousButton.tintColor = controlColor;
    self.playPauseButton.tintColor = controlColor;
    self.nextButton.tintColor = controlColor;
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
    [self updateEqualizerBadge];
}

- (void)updateArtworkCornerRadius {
    SonoraPlayerArtworkStyle artworkStyle = SonoraPlayerArtworkStyleFromDefaults();
    CGFloat horizontalInset = (artworkStyle == SonoraPlayerArtworkStyleRounded) ? 12.0 : 0.0;
    self.artworkLeadingConstraint.constant = horizontalInset;
    self.artworkTrailingConstraint.constant = -horizontalInset;
    self.artworkView.layer.cornerRadius = SonoraArtworkCornerRadiusForStyle(artworkStyle, CGRectGetWidth(self.artworkView.bounds));
    self.artworkView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.artworkView.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)handlePlayerSettingsChanged:(NSNotification *)notification {
    (void)notification;
    [self applyPlayerTheme];
    [self updateEqualizerBadge];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSDictionary<NSString *, id> *> *storedSharedPlaylists = [NSUserDefaults.standardUserDefaults arrayForKey:SonoraSharedPlaylistDefaultsKey];
        if (![storedSharedPlaylists isKindOfClass:NSArray.class] || storedSharedPlaylists.count == 0) {
            return;
        }
        if (![NSUserDefaults.standardUserDefaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey]) {
            NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:SonoraSharedPlaylistAudioCacheDirectoryPath()]
                                                                  includingPropertiesForKeys:nil
                                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                       error:nil];
            for (NSURL *fileURL in files) {
                [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
            }
            return;
        }
        for (NSDictionary<NSString *, id> *item in storedSharedPlaylists) {
            NSString *playlistID = [item[@"playlistID"] isKindOfClass:NSString.class] ? item[@"playlistID"] : @"";
            if (playlistID.length == 0) {
                continue;
            }
            SonoraSharedPlaylistSnapshot *snapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:playlistID];
            if (snapshot != nil) {
                SonoraSharedPlaylistWarmPersistentCache(snapshot);
            }
        }
    });
}

- (void)previousTapped {
    [SonoraPlaybackManager.sharedManager playPrevious];
}

- (void)playPauseTapped {
    [SonoraPlaybackManager.sharedManager togglePlayPause];
}

- (void)nextTapped {
    [SonoraPlaybackManager.sharedManager playNext];
}

- (void)toggleShuffleTapped {
    [SonoraPlaybackManager.sharedManager toggleShuffleEnabled];
}

- (void)toggleRepeatTapped {
    [SonoraPlaybackManager.sharedManager cycleRepeatMode];
}

- (void)toggleFavoriteTapped {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    if (track.identifier.length == 0) {
        return;
    }
    [SonoraFavoritesStore.sharedStore toggleFavoriteForTrackID:track.identifier];
    [self updateFavoriteButton];
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepTimerButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepTimerButton];
    });
}

- (void)updateFavoriteButton {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    BOOL isPlaceholder = [self isMiniStreamingPlaceholderTrack:track];
    if (track == nil || track.identifier.length == 0 || isPlaceholder) {
        self.favoriteButton.hidden = YES;
        self.favoriteButton.enabled = NO;
        return;
    }

    self.favoriteButton.hidden = NO;
    self.favoriteButton.enabled = YES;

    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *symbolName = isFavorite ? @"heart.fill" : @"heart";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [self.favoriteButton setImage:image forState:UIControlStateNormal];
    self.favoriteButton.tintColor = isFavorite ? [UIColor colorWithRed:1.0 green:0.35 blue:0.40 alpha:1.0]
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
}

- (void)updateSleepTimerButton {
    BOOL isActive = SonoraSleepTimerManager.sharedManager.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:23.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepTimerButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.sleepTimerButton.tintColor = isActive ? SonoraAccentYellowColor()
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
    self.sleepTimerButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(SonoraSleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)updateEqualizerBadge {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL enabled = SonoraArtworkEqualizerEnabledFromDefaults();
    BOOL hasTrack = (playback.currentTrack != nil);
    BOOL isPlaceholder = [self isMiniStreamingPlaceholderTrack:playback.currentTrack];
    BOOL visible = enabled && hasTrack && !isPlaceholder;
    self.equalizerBadgeView.hidden = !visible;
    if (!visible) {
        [self.equalizerBadgeView setPlaying:NO];
        [self.equalizerBadgeView setLevel:0.0];
        return;
    }

    BOOL isPlaying = playback.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? 0.18 : 0.06];
}

- (void)updateArtworkLoadingOverlayForTrack:(SonoraTrack * _Nullable)track {
    BOOL isMiniStreamingPlaceholder = [self isMiniStreamingPlaceholderTrack:track];
    self.artworkLoadingOverlayView.hidden = !isMiniStreamingPlaceholder;
    if (isMiniStreamingPlaceholder) {
        [self.artworkLoadingSpinner startAnimating];
    } else {
        [self.artworkLoadingSpinner stopAnimating];
    }
}

- (BOOL)isMiniStreamingPlaceholderTrack:(SonoraTrack * _Nullable)track {
    if (track == nil || track.identifier.length == 0) {
        return NO;
    }
    if (![track.identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        return NO;
    }

    NSURL *url = track.url;
    if (url == nil) {
        return YES;
    }
    if (!url.isFileURL) {
        return NO;
    }

    NSString *path = url.path ?: @"";
    return path.length == 0 || [path isEqualToString:@"/dev/null"];
}

- (void)handlePlaybackMeterChanged:(NSNotification *)notification {
    if (self.equalizerBadgeView.hidden) {
        return;
    }

    NSNumber *levelNumber = notification.userInfo[@"level"];
    CGFloat level = [levelNumber isKindOfClass:NSNumber.class] ? (CGFloat)levelNumber.doubleValue : 0.0;
    BOOL isPlaying = SonoraPlaybackManager.sharedManager.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? level : 0.06];
}

- (void)sliderTouchDown {
    self.scrubbing = YES;
}

- (void)sliderChanged {
    self.elapsedLabel.text = SonoraFormatDuration(self.progressSlider.value);
}

- (void)sliderTouchUp {
    self.scrubbing = NO;
    [SonoraPlaybackManager.sharedManager seekToTime:self.progressSlider.value];
}

- (void)handleProgressChanged {
    if (!self.scrubbing) {
        [self refreshTimelineOnly];
    }
}

- (void)refreshTimelineOnly {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSTimeInterval duration = playback.duration;
    NSTimeInterval current = playback.currentTime;

    self.progressSlider.maximumValue = MAX(duration, 1.0);
    self.progressSlider.value = MIN(current, self.progressSlider.maximumValue);

    self.elapsedLabel.text = SonoraFormatDuration(current);
    self.durationLabel.text = SonoraFormatDuration(duration);
}

- (void)refreshUI {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = playback.currentTrack;

    if (track == nil) {
        self.artworkView.image = [UIImage systemImageNamed:@"music.note.list"];
        self.artworkView.contentMode = UIViewContentModeCenter;
        self.artworkView.tintColor = SonoraPlayerPrimaryColor();
        [self updateArtworkLoadingOverlayForTrack:nil];

        self.subtitleLabel.text = @"";
        self.titleLabel.text = @"No track selected";
        self.nextPreviewLabel.text = @"Next: -";

        self.playPauseButton.enabled = NO;
        self.previousButton.enabled = NO;
        self.nextButton.enabled = NO;

        self.progressSlider.maximumValue = 1.0;
        self.progressSlider.value = 0.0;
        self.elapsedLabel.text = @"0:00";
        self.durationLabel.text = @"0:00";

        [self applyPlayerTheme];
        [self updatePlayPauseIcon];
        [self updateModeIcons];
        [self updateFavoriteButton];
        [self updateSleepTimerButton];
        return;
    }

    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.image = track.artwork;
    [self updateArtworkLoadingOverlayForTrack:track];

    self.subtitleLabel.text = (track.artist.length > 0 ? track.artist : @"");
    self.titleLabel.text = (track.title.length > 0 ? track.title : track.fileName);
    self.nextPreviewLabel.text = [self nextPreviewText];

    self.playPauseButton.enabled = YES;
    self.previousButton.enabled = YES;
    self.nextButton.enabled = YES;

    [self refreshTimelineOnly];
    [self applyPlayerTheme];
    [self updatePlayPauseIcon];
    [self updateModeIcons];
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
}

- (NSString *)nextPreviewText {
    SonoraTrack *nextTrack = [SonoraPlaybackManager.sharedManager predictedNextTrackForSkip];

    if (nextTrack == nil) {
        return @"Next: -";
    }

    NSString *title = (nextTrack.title.length > 0 ? nextTrack.title : @"Unknown");
    if (nextTrack.artist.length > 0) {
        return [NSString stringWithFormat:@"Next: %@ - %@", nextTrack.artist, title];
    }
    return [NSString stringWithFormat:@"Next: %@", title];
}

- (void)updatePlayPauseIcon {
    NSString *symbol = SonoraPlaybackManager.sharedManager.isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:56.0
                                                                                           weight:UIImageSymbolWeightBold];
    [self.playPauseButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
}

- (void)updateModeIcons {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    UIColor *inactiveColor = SonoraPlayerPrimaryColor();

    self.shuffleButton.tintColor = playback.isShuffleEnabled ? SonoraAccentYellowColor() : inactiveColor;

    NSString *repeatSymbol = @"repeat";
    switch (playback.repeatMode) {
        case SonoraRepeatModeNone:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = inactiveColor;
            break;
        case SonoraRepeatModeQueue:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
        case SonoraRepeatModeTrack:
            repeatSymbol = @"repeat.1";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
    }

    UIImageSymbolConfiguration *repeatConfig = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [self.repeatButton setImage:[UIImage systemImageNamed:repeatSymbol withConfiguration:repeatConfig] forState:UIControlStateNormal];
}

@end
