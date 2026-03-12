#import "SonoraSharedPlaylists.h"
#import "SonoraSettings.h"

static NSString * const SonoraMiniStreamingDefaultBackendBaseURLString = @"https://api.corebrew.ru";
static NSString * const SonoraSharedPlaylistDefaultsKey = @"sonora.sharedPlaylists.v1";
static NSString * const SonoraSharedPlaylistSyntheticPrefix = @"shared:";
static NSString * const SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey = @"sonora.sharedPlaylists.suppressDidChangeNotification";
static NSString * const SonoraSharedPlaylistManifestFileName = @"shared_playlists_manifest_v2.json";
static NSString * const SonoraSharedPlaylistErrorDomain = @"SonoraSharedPlaylistErrorDomain";

static NSString *SonoraSharedPlaylistSafeFileComponent(NSString *value);

static UIImage * _Nullable SonoraSharedPlaylistImageFromData(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    return [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
}

NSString *SonoraSharedPlaylistStorageDirectoryPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"SonoraSharedPlaylists"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString * _Nullable SonoraSharedPlaylistWriteImageInDirectory(UIImage *image,
                                                                      NSString *preferredName,
                                                                      NSString *directoryPath) {
    if (image == nil) {
        return nil;
    }
    NSData *data = UIImageJPEGRepresentation(image, 0.84);
    if (data.length == 0) {
        return nil;
    }
    NSString *fileName = preferredName.length > 0 ? preferredName : [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString.lowercaseString];
    if (directoryPath.length == 0) {
        directoryPath = SonoraSharedPlaylistStorageDirectoryPath();
    }
    NSString *path = [directoryPath stringByAppendingPathComponent:fileName];
    if (![data writeToFile:path atomically:YES]) {
        return nil;
    }
    return path.lastPathComponent;
}

static UIImage * _Nullable SonoraSharedPlaylistReadImageNamedInDirectory(NSString *fileName, NSString *directoryPath) {
    if (fileName.length == 0) {
        return nil;
    }
    if (directoryPath.length == 0) {
        directoryPath = SonoraSharedPlaylistStorageDirectoryPath();
    }
    NSString *path = [directoryPath stringByAppendingPathComponent:fileName];
    NSData *data = [NSData dataWithContentsOfFile:path];
    return SonoraSharedPlaylistImageFromData(data);
}

static NSError *SonoraSharedPlaylistError(NSInteger code, NSString *description) {
    NSDictionary<NSString *, id> *userInfo = description.length > 0
    ? @{ NSLocalizedDescriptionKey : description }
    : @{};
    return [NSError errorWithDomain:SonoraSharedPlaylistErrorDomain code:code userInfo:userInfo];
}

static NSURLSession *SonoraSharedPlaylistURLSession(void) {
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 60.0;
        configuration.timeoutIntervalForResource = 600.0;
        configuration.waitsForConnectivity = NO;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static NSMutableURLRequest *SonoraSharedPlaylistMutableRequest(NSURL *url, NSTimeInterval timeout) {
    if (url == nil) {
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = MAX(timeout, 30.0);
    return request;
}

static NSString *SonoraSharedPlaylistFileExtensionForResponse(NSURLResponse *response, NSURL *remoteURL) {
    NSString *extension = response.suggestedFilename.pathExtension.lowercaseString;
    if (extension.length == 0) {
        extension = remoteURL.pathExtension.length > 0 ? remoteURL.pathExtension.lowercaseString : @"";
    }
    if (extension.length > 0) {
        return extension;
    }

    NSString *mimeType = response.MIMEType.lowercaseString ?: @"";
    if ([mimeType containsString:@"mp4"]) {
        return @"m4a";
    }
    if ([mimeType containsString:@"aac"]) {
        return @"aac";
    }
    if ([mimeType containsString:@"wav"]) {
        return @"wav";
    }
    if ([mimeType containsString:@"ogg"]) {
        return @"ogg";
    }
    if ([mimeType containsString:@"flac"]) {
        return @"flac";
    }
    if ([mimeType containsString:@"jpeg"] || [mimeType containsString:@"jpg"]) {
        return @"jpg";
    }
    if ([mimeType containsString:@"png"]) {
        return @"png";
    }
    return @"mp3";
}

static NSURL *SonoraSharedPlaylistUniqueDestinationURL(NSURL *directoryURL,
                                                       NSString *suggestedBaseName,
                                                       NSString *extension) {
    NSString *baseName = SonoraSharedPlaylistSafeFileComponent(suggestedBaseName);
    NSURL *destinationURL = [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, extension]];
    NSUInteger suffix = 1;
    while ([NSFileManager.defaultManager fileExistsAtPath:destinationURL.path]) {
        destinationURL = [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu.%@",
                                                                    baseName,
                                                                    (unsigned long)suffix,
                                                                    extension]];
        suffix += 1;
    }
    return destinationURL;
}

static void SonoraSharedPlaylistDownloadFileToDirectory(NSURL *remoteURL,
                                                        NSTimeInterval timeout,
                                                        NSString *suggestedBaseName,
                                                        NSURL *directoryURL,
                                                        unsigned long long maximumBytes,
                                                        void (^completion)(NSURL * _Nullable fileURL,
                                                                           NSURLResponse * _Nullable response,
                                                                           NSError * _Nullable error)) {
    if (completion == nil) {
        return;
    }
    if (remoteURL == nil || directoryURL == nil) {
        completion(nil, nil, SonoraSharedPlaylistError(1001, @"Shared playlist URL is invalid."));
        return;
    }

    NSMutableURLRequest *request = SonoraSharedPlaylistMutableRequest(remoteURL, timeout);
    NSURLSessionDownloadTask *task = [SonoraSharedPlaylistURLSession() downloadTaskWithRequest:request
                                                                              completionHandler:^(NSURL * _Nullable location,
                                                                                                  NSURLResponse * _Nullable response,
                                                                                                  NSError * _Nullable error) {
        if (error != nil || location == nil) {
            completion(nil, response, error ?: SonoraSharedPlaylistError(1002, @"Shared playlist download failed."));
            return;
        }

        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:location.path error:nil];
        unsigned long long downloadedBytes = [attributes[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)]
        ? [attributes[NSFileSize] unsignedLongLongValue]
        : 0ull;
        if (maximumBytes != ULLONG_MAX && downloadedBytes > maximumBytes) {
            [NSFileManager.defaultManager removeItemAtURL:location error:nil];
            completion(nil, response, SonoraSharedPlaylistError(1003, @"Shared playlist file exceeds cache limits."));
            return;
        }

        [NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
        NSString *extension = SonoraSharedPlaylistFileExtensionForResponse(response, remoteURL);
        NSURL *destinationURL = SonoraSharedPlaylistUniqueDestinationURL(directoryURL, suggestedBaseName, extension);
        NSError *moveError = nil;
        [NSFileManager.defaultManager removeItemAtURL:destinationURL error:nil];
        if (![NSFileManager.defaultManager moveItemAtURL:location toURL:destinationURL error:&moveError]) {
            completion(nil, response, moveError ?: SonoraSharedPlaylistError(1004, @"Could not store shared playlist file."));
            return;
        }
        completion(destinationURL, response, nil);
    }];
    [task resume];
}

NSString *SonoraSharedPlaylistSyntheticID(NSString *remoteID) {
    NSString *resolved = [remoteID isKindOfClass:NSString.class] ? remoteID : @"";
    return [NSString stringWithFormat:@"%@%@", SonoraSharedPlaylistSyntheticPrefix, resolved];
}

NSString *SonoraSharedPlaylistBackendBaseURLString(void) {
    NSString *configured = [NSBundle.mainBundle objectForInfoDictionaryKey:@"BACKEND_BASE_URL"];
    if ([configured isKindOfClass:NSString.class] && configured.length > 0) {
        return [configured stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return SonoraMiniStreamingDefaultBackendBaseURLString;
}

NSString *SonoraSharedPlaylistNormalizeText(NSString *value) {
    NSString *trimmed = [[value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return trimmed ?: @"";
}

NSString *SonoraSharedPlaylistAudioCacheDirectoryPath(void) {
    NSString *directory = [SonoraSharedPlaylistStorageDirectoryPath() stringByAppendingPathComponent:@"audio"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString *SonoraSharedPlaylistAudioCacheDirectoryPathForStorageDirectory(NSString *storageDirectoryPath) {
    NSString *directory = [storageDirectoryPath stringByAppendingPathComponent:@"audio"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

void SonoraSharedPlaylistDataFromURL(NSURL *url,
                                     NSTimeInterval timeout,
                                     SonoraSharedPlaylistDataCompletion completion) {
    if (completion == nil) {
        return;
    }
    if (url == nil) {
        completion(nil, nil, SonoraSharedPlaylistError(1010, @"Shared playlist URL is invalid."));
        return;
    }

    NSMutableURLRequest *request = SonoraSharedPlaylistMutableRequest(url, timeout);
    NSURLSessionDataTask *task = [SonoraSharedPlaylistURLSession() dataTaskWithRequest:request
                                                                     completionHandler:^(NSData * _Nullable data,
                                                                                         NSURLResponse * _Nullable response,
                                                                                         NSError * _Nullable error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error == nil && (http == nil || (http.statusCode >= 200 && http.statusCode < 300))) {
            completion(data ?: NSData.data, response, nil);
            return;
        }
        completion(nil,
                   response,
                   error ?: SonoraSharedPlaylistError(http.statusCode ?: 1011, @"Shared playlist request failed."));
    }];
    [task resume];
}

void SonoraSharedPlaylistPerformRequest(NSURLRequest *request,
                                        NSTimeInterval timeout,
                                        SonoraSharedPlaylistRequestCompletion completion) {
    if (completion == nil) {
        return;
    }
    if (request == nil) {
        completion(nil, nil, SonoraSharedPlaylistError(1020, @"Shared playlist request is missing."));
        return;
    }

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.timeoutInterval = MAX(timeout, 30.0);

    NSURLSessionDataTask *task = [SonoraSharedPlaylistURLSession() dataTaskWithRequest:mutableRequest
                                                                     completionHandler:^(NSData * _Nullable data,
                                                                                         NSURLResponse * _Nullable response,
                                                                                         NSError * _Nullable error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error == nil && http != nil && http.statusCode >= 200 && http.statusCode < 300) {
            completion(data ?: NSData.data, http, nil);
            return;
        }
        completion(nil,
                   http,
                   error ?: SonoraSharedPlaylistError(http.statusCode ?: 1021, @"Shared playlist request failed."));
    }];
    [task resume];
}

void SonoraSharedPlaylistUploadFileRequest(NSURLRequest *request,
                                           NSURL *fileURL,
                                           NSTimeInterval timeout,
                                           SonoraSharedPlaylistRequestCompletion completion) {
    if (completion == nil) {
        return;
    }
    if (request == nil || !fileURL.isFileURL) {
        completion(nil, nil, SonoraSharedPlaylistError(1030, @"Shared playlist upload file is invalid."));
        return;
    }

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.timeoutInterval = MAX(timeout, 30.0);

    NSURLSessionUploadTask *task = [SonoraSharedPlaylistURLSession() uploadTaskWithRequest:mutableRequest
                                                                                   fromFile:fileURL
                                                                          completionHandler:^(NSData * _Nullable data,
                                                                                              NSURLResponse * _Nullable response,
                                                                                              NSError * _Nullable error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error == nil && http != nil && http.statusCode >= 200 && http.statusCode < 300) {
            completion(data ?: NSData.data, http, nil);
            return;
        }
        completion(nil,
                   http,
                   error ?: SonoraSharedPlaylistError(http.statusCode ?: 1031, @"Shared playlist upload failed."));
    }];
    [task resume];
}

void SonoraSharedPlaylistAppendMultipartText(NSMutableData *body, NSString *boundary, NSString *name, NSString *value) {
    if (body == nil || boundary.length == 0 || name.length == 0 || value == nil) {
        return;
    }
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

void SonoraSharedPlaylistAppendMultipartFile(NSMutableData *body,
                                             NSString *boundary,
                                             NSString *name,
                                             NSString *filename,
                                             NSString *mimeType,
                                             NSData *data) {
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

void SonoraSharedPlaylistDownloadedFileURL(NSString *urlString,
                                           NSString *suggestedBaseName,
                                           SonoraSharedPlaylistDownloadedFileCompletion completion) {
    if (completion == nil) {
        return;
    }
    NSURL *remoteURL = [NSURL URLWithString:urlString];
    if (remoteURL == nil) {
        completion(nil, SonoraSharedPlaylistError(1040, @"Shared playlist URL is invalid."));
        return;
    }
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    SonoraSharedPlaylistDownloadFileToDirectory(remoteURL,
                                                600.0,
                                                suggestedBaseName,
                                                musicDirectoryURL,
                                                ULLONG_MAX,
                                                ^(NSURL * _Nullable fileURL, __unused NSURLResponse * _Nullable response, NSError * _Nullable error) {
        completion(fileURL, error);
    });
}

SonoraSharedPlaylistSnapshot * _Nullable SonoraSharedPlaylistSnapshotFromPayload(NSDictionary<NSString *, id> *payload,
                                                                                 NSString *fallbackBaseURL) {
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
    snapshot.tracks = tracks.copy;
    snapshot.trackArtworkURLByTrackID = trackArtworkURLByTrackID.copy;
    snapshot.trackRemoteFileURLByTrackID = trackRemoteFileURLByTrackID.copy;
    return snapshot;
}

static BOOL SonoraSharedPlaylistShouldSuppressDidChangeNotification(void) {
    return [NSThread.currentThread.threadDictionary[SonoraSharedPlaylistSuppressDidChangeNotificationThreadKey] boolValue];
}

void SonoraSharedPlaylistPerformWithoutDidChangeNotification(dispatch_block_t block) {
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

void SonoraSharedPlaylistWarmPersistentCache(SonoraSharedPlaylistSnapshot *snapshot,
                                             SonoraSharedPlaylistWarmCompletion completion) {
    if (snapshot == nil) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typedef void (^SonoraSharedPlaylistWarmStep)(dispatch_block_t next);
        NSMutableArray<SonoraSharedPlaylistWarmStep> *steps = [NSMutableArray array];
        __block BOOL didPersistUpdates = NO;

        if (snapshot.coverImage == nil && snapshot.coverURL.length > 0) {
            [steps addObject:[^(dispatch_block_t next) {
                NSURL *coverURL = [NSURL URLWithString:snapshot.coverURL];
                if (coverURL == nil) {
                    next();
                    return;
                }
                SonoraSharedPlaylistDataFromURL(coverURL, 120.0, ^(NSData * _Nullable data, __unused NSURLResponse * _Nullable response, __unused NSError * _Nullable error) {
                    UIImage *image = SonoraSharedPlaylistImageFromData(data);
                    if (image != nil) {
                        snapshot.coverImage = image;
                        didPersistUpdates = YES;
                    }
                    next();
                });
            } copy]];
        }

        [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            if (track.artwork == nil && track.identifier.length > 0) {
                NSString *artworkURLString = snapshot.trackArtworkURLByTrackID[track.identifier];
                if (artworkURLString.length > 0) {
                    [steps addObject:[^(dispatch_block_t next) {
                        NSURL *artworkURL = [NSURL URLWithString:artworkURLString];
                        if (artworkURL == nil) {
                            next();
                            return;
                        }
                        SonoraSharedPlaylistDataFromURL(artworkURL, 120.0, ^(NSData * _Nullable data, __unused NSURLResponse * _Nullable response, __unused NSError * _Nullable error) {
                            UIImage *image = SonoraSharedPlaylistImageFromData(data);
                            if (image != nil) {
                                track.artwork = image;
                                didPersistUpdates = YES;
                            }
                            next();
                        });
                    } copy]];
                }
            }

            if (!SonoraSettingsCacheOnlinePlaylistTracksEnabled()) {
                return;
            }

            NSString *remoteFileURL = snapshot.trackRemoteFileURLByTrackID[track.identifier ?: @""];
            if (remoteFileURL.length == 0 && !track.url.isFileURL) {
                remoteFileURL = track.url.absoluteString ?: @"";
            }
            if (remoteFileURL.length == 0) {
                return;
            }

            NSString *existingLocalPath = track.url.isFileURL ? track.url.path : @"";
            if (existingLocalPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:existingLocalPath]) {
                [steps addObject:[^(dispatch_block_t next) {
                    [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate : NSDate.date }
                                                   ofItemAtPath:existingLocalPath
                                                          error:nil];
                    next();
                } copy]];
                return;
            }

            NSInteger maxMB = SonoraSettingsOnlinePlaylistCacheMaxMB();
            unsigned long long limitBytes = (maxMB > 0)
            ? ((unsigned long long)maxMB) * 1024ULL * 1024ULL
            : (1024ULL * 1024ULL * 1024ULL);
            NSURL *audioDirectoryURL = [NSURL fileURLWithPath:SonoraSharedPlaylistAudioCacheDirectoryPath() isDirectory:YES];
            NSString *suggestedName = [NSString stringWithFormat:@"%@_%lu",
                                       snapshot.remoteID.length > 0 ? snapshot.remoteID : @"shared",
                                       (unsigned long)idx];
            [steps addObject:[^(dispatch_block_t next) {
                NSURL *remoteURL = [NSURL URLWithString:remoteFileURL];
                if (remoteURL == nil) {
                    next();
                    return;
                }
                SonoraSharedPlaylistDownloadFileToDirectory(remoteURL,
                                                            600.0,
                                                            suggestedName,
                                                            audioDirectoryURL,
                                                            limitBytes,
                                                            ^(NSURL * _Nullable fileURL, __unused NSURLResponse * _Nullable response, __unused NSError * _Nullable error) {
                    if (fileURL != nil) {
                        track.url = fileURL;
                        didPersistUpdates = YES;
                    }
                    next();
                });
            } copy]];
        }];

        __block void (^runStepAtIndex)(NSUInteger);
        runStepAtIndex = ^(NSUInteger index) {
            if (index >= steps.count) {
                if (didPersistUpdates) {
                    SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshot];
                    });
                }
                if (completion != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(didPersistUpdates);
                    });
                }
                return;
            }
            SonoraSharedPlaylistWarmStep step = steps[index];
            step(^{
                runStepAtIndex(index + 1);
            });
        };
        runStepAtIndex(0);
    });
}

@implementation SonoraSharedPlaylistSnapshot
@end

@interface SonoraSharedPlaylistStore ()

@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, strong) NSURL *storageDirectoryURL;
@property (nonatomic, strong) NSURL *manifestFileURL;

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

- (instancetype)init {
    NSURL *storageDirectoryURL = [NSURL fileURLWithPath:SonoraSharedPlaylistStorageDirectoryPath() isDirectory:YES];
    return [self initWithUserDefaults:NSUserDefaults.standardUserDefaults
                  storageDirectoryURL:storageDirectoryURL];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
                 storageDirectoryURL:(NSURL *)storageDirectoryURL {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _userDefaults = userDefaults ?: NSUserDefaults.standardUserDefaults;
    _storageDirectoryURL = storageDirectoryURL ?: [NSURL fileURLWithPath:SonoraSharedPlaylistStorageDirectoryPath() isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:_storageDirectoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    _manifestFileURL = [_storageDirectoryURL URLByAppendingPathComponent:SonoraSharedPlaylistManifestFileName];
    [self migrateLegacyStoredDictionariesIfNeeded];
    return self;
}

- (NSArray<NSDictionary<NSString *, id> *> *)legacyStoredDictionaries {
    NSArray *items = [self.userDefaults arrayForKey:SonoraSharedPlaylistDefaultsKey];
    if (![items isKindOfClass:NSArray.class]) {
        return @[];
    }
    return items;
}

- (NSArray<NSDictionary<NSString *, id> *> *)manifestStoredDictionaries {
    NSData *data = [NSData dataWithContentsOfURL:self.manifestFileURL options:0 error:nil];
    if (data.length == 0) {
        return @[];
    }
    id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:NSArray.class]) {
        return @[];
    }
    return (NSArray<NSDictionary<NSString *, id> *> *)payload;
}

- (NSArray<NSDictionary<NSString *, id> *> *)storedDictionaries {
    BOOL manifestExists = [NSFileManager.defaultManager fileExistsAtPath:self.manifestFileURL.path];
    NSArray<NSDictionary<NSString *, id> *> *items = [self manifestStoredDictionaries];
    if (manifestExists || items.count > 0) {
        return items;
    }
    return [self legacyStoredDictionaries];
}

- (void)writeStoredDictionaries:(NSArray<NSDictionary<NSString *, id> *> *)items {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(items ?: @[]) options:0 error:nil];
    if (data.length > 0 || items.count == 0) {
        [data writeToURL:self.manifestFileURL options:NSDataWritingAtomic error:nil];
    }
    [self.userDefaults removeObjectForKey:SonoraSharedPlaylistDefaultsKey];
}

- (void)migrateLegacyStoredDictionariesIfNeeded {
    if ([NSFileManager.defaultManager fileExistsAtPath:self.manifestFileURL.path]) {
        return;
    }
    NSArray<NSDictionary<NSString *, id> *> *legacyItems = [self legacyStoredDictionaries];
    if (legacyItems.count == 0) {
        return;
    }
    [self writeStoredDictionaries:legacyItems];
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
        playlist.trackIDs = trackIDs.copy;
        [playlists addObject:playlist];
    }
    return playlists.copy;
}

- (void)refreshAllPersistentCachesIfNeeded {
    for (NSDictionary<NSString *, id> *item in [self storedDictionaries]) {
        NSString *playlistID = [item[@"playlistID"] isKindOfClass:NSString.class] ? item[@"playlistID"] : @"";
        if (playlistID.length == 0) {
            continue;
        }
        SonoraSharedPlaylistSnapshot *snapshot = [self snapshotForPlaylistID:playlistID];
        if (snapshot != nil) {
            SonoraSharedPlaylistWarmPersistentCache(snapshot, nil);
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
        snapshot.coverImage = SonoraSharedPlaylistReadImageNamedInDirectory([item[@"coverFileName"] isKindOfClass:NSString.class] ? item[@"coverFileName"] : @"",
                                                                            self.storageDirectoryURL.path);

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
            track.artwork = SonoraSharedPlaylistReadImageNamedInDirectory([trackDict[@"artworkFileName"] isKindOfClass:NSString.class] ? trackDict[@"artworkFileName"] : @"",
                                                                          self.storageDirectoryURL.path);
            NSString *artworkURLString = [trackDict[@"artworkURL"] isKindOfClass:NSString.class] ? trackDict[@"artworkURL"] : @"";
            if (artworkURLString.length > 0) {
                trackArtworkURLByTrackID[track.identifier] = artworkURLString;
            }
            [tracks addObject:track];
        }];
        snapshot.tracks = tracks.copy;
        snapshot.trackArtworkURLByTrackID = trackArtworkURLByTrackID.copy;
        snapshot.trackRemoteFileURLByTrackID = trackRemoteFileURLByTrackID.copy;
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

    NSString *coverFileName = SonoraSharedPlaylistWriteImageInDirectory(snapshot.coverImage,
                                                                        [NSString stringWithFormat:@"%@_cover.jpg", snapshot.remoteID.length > 0 ? snapshot.remoteID : NSUUID.UUID.UUIDString.lowercaseString],
                                                                        self.storageDirectoryURL.path);
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
        NSString *artworkName = SonoraSharedPlaylistWriteImageInDirectory(track.artwork,
                                                                          [NSString stringWithFormat:@"%@_%lu.jpg", snapshot.remoteID.length > 0 ? snapshot.remoteID : @"shared", (unsigned long)idx],
                                                                          self.storageDirectoryURL.path);
        if (artworkName.length > 0) {
            trackDict[@"artworkFileName"] = artworkName;
        }
        [trackItems addObject:trackDict];
    }];
    dictionary[@"tracks"] = trackItems.copy;

    [stored insertObject:dictionary.copy atIndex:0];
    [self writeStoredDictionaries:stored.copy];
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
    NSString *audioCacheDirectory = SonoraSharedPlaylistAudioCacheDirectoryPathForStorageDirectory(self.storageDirectoryURL.path);
    for (NSDictionary<NSString *, id> *item in itemsToRemove) {
        NSString *coverFileName = [item[@"coverFileName"] isKindOfClass:NSString.class] ? item[@"coverFileName"] : @"";
        if (coverFileName.length > 0) {
            NSString *coverPath = [self.storageDirectoryURL.path stringByAppendingPathComponent:coverFileName];
            [NSFileManager.defaultManager removeItemAtPath:coverPath error:nil];
        }
        NSArray *trackItems = [item[@"tracks"] isKindOfClass:NSArray.class] ? item[@"tracks"] : @[];
        for (NSDictionary<NSString *, id> *trackItem in trackItems) {
            NSString *artworkFileName = [trackItem[@"artworkFileName"] isKindOfClass:NSString.class] ? trackItem[@"artworkFileName"] : @"";
            if (artworkFileName.length > 0) {
                NSString *artworkPath = [self.storageDirectoryURL.path stringByAppendingPathComponent:artworkFileName];
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
    [self writeStoredDictionaries:stored.copy];
    if (!SonoraSharedPlaylistShouldSuppressDidChangeNotification()) {
        SonoraSharedPlaylistPostDidChangeNotification();
    }
}

@end
