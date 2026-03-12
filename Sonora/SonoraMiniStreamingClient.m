#import "SonoraMiniStreamingClient.h"

static NSString * const SonoraMiniStreamingDefaultBackendBaseURLString = @"https://api.corebrew.ru";
static NSString * const SonoraMiniStreamingBackendSearchPath = @"/api/spotify/search";
static NSString * const SonoraMiniStreamingBackendDownloadPath = @"/api/download";
static NSString * const SonoraMiniStreamingSpotifyTokenURLString = @"https://accounts.spotify.com/api/token";
static NSString * const SonoraMiniStreamingSpotifySearchURLString = @"https://api.spotify.com/v1/search";
static NSString * const SonoraMiniStreamingRapidAPIDownloadURLString = @"https://spotify-music-mp3-downloader-api.p.rapidapi.com/download";
static NSString * const SonoraMiniStreamingRapidAPIDownloader9URLString = @"https://spotify-downloader9.p.rapidapi.com/downloadSong";
static NSString * const SonoraMiniStreamingDefaultRapidAPIHost = @"spotify-music-mp3-downloader-api.p.rapidapi.com";
static NSString * const SonoraMiniStreamingKeyBrokerMarkURLString = @"https://api.corebrew.ru/api/mark";
static NSString * const SonoraMiniStreamingErrorDomain = @"SonoraMiniStreamingErrorDomain";
static NSString * const SonoraMiniStreamingInstallUnavailableMessage = @"Установка временно недоступна, попробуйте завтра.";

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

static NSError *SonoraMiniStreamingError(NSInteger code, NSString *message) {
    NSString *resolvedMessage = message.length > 0 ? message : @"Unexpected mini streaming error.";
    return [NSError errorWithDomain:SonoraMiniStreamingErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey: resolvedMessage
                           }];
}

@implementation SonoraMiniStreamingTrack
@end

@implementation SonoraMiniStreamingArtist
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
            __weak void (^weakAttemptCandidateAtIndex)(NSUInteger) = nil;
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
                    weakAttemptCandidateAtIndex(index + 1);
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
                        weakAttemptCandidateAtIndex(index + 1);
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
                    weakAttemptCandidateAtIndex(index + 1);
                }];
                [task resume];
            };

            weakAttemptCandidateAtIndex = attemptCandidateAtIndex;
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
